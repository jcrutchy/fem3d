unit fem_sketch;

// The editable model behind the native section editor: a "sketch" is a set of
// closed profiles in the XY plane -- each either a chain of line/arc segments
// or a full circle -- flagged solid or hole. It converts to and from the
// FEM3DGEO model (so files are written by the canonical writer and checked by
// the same validator the command-line tools use), and has an undo/redo
// history. No LCL dependency.
//
// Holes are not tied to a particular solid in the sketch; when the geometry
// model is built, each hole is assigned to the smallest solid that contains it.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math,
  fem_geometry_types, fem_section_types;

type
  TSegKind = (skLine, skArc);

  // One segment of a chain: P0 -> P1, and for an arc the point PM that the arc
  // passes through between them (a three-point arc, like ARC3).
  TSketchSeg = record
    Kind: TSegKind;
    P0, PM, P1: TPoint2D;
  end;
  TSketchSegArray = array of TSketchSeg;

  TProfileKind = (pkChain, pkCircle);

  TSketchProfile = record
    Kind: TProfileKind;
    IsHole: Boolean;
    Segs: TSketchSegArray;       // chain: closed (Segs[i].P1 = Segs[i+1].P0)
    Center: TPoint2D;            // circle
    Radius: Double;              // circle
  end;
  TSketchProfileArray = array of TSketchProfile;

  TSketch = record
    Name: string;
    LengthUnit: string;
    HasHeader: Boolean;          // header kept from an imported file
    Header: TFEMGeoHeader;
    Profiles: TSketchProfileArray;
  end;

  TSketchBox = record
    XMin, XMax, YMin, YMax: Double;
    Valid: Boolean;
  end;

// ---------------------------------------------------------------- building
procedure SketchInit(out S: TSketch; const AName, AUnit: string);
// Deep copy (dynamic arrays inside records are shared by plain assignment).
procedure SketchCopy(const A: TSketch; out B: TSketch);

function MakeLineSeg(const A, B: TPoint2D): TSketchSeg;
function MakeArcSeg(const A, M, B: TPoint2D): TSketchSeg;
function MakeChainProfile(const Segs: array of TSketchSeg; AHole: Boolean): TSketchProfile;
function MakePolygonProfile(const Pts: array of TPoint2D; AHole: Boolean): TSketchProfile;
function MakeRectProfile(X0, Y0, X1, Y1: Double; AHole: Boolean): TSketchProfile;
function MakeCircleProfile(CX, CY, R: Double; AHole: Boolean): TSketchProfile;

// ---------------------------------------------------------------- geometry
// Three-point arc to centre/radius/start angle/signed sweep (radians).
function ArcCircle(const P0, PM, P1: TPoint2D; out CX, CY, R, A0, Sweep: Double): Boolean;
// Polygon approximation (arcs and circles sampled at <= MaxStepRad per step).
procedure ProfileFlatten(const P: TSketchProfile; out Pts: TPoint2DArray;
  MaxStepRad: Double = 0.1);
function PolygonSignedArea(const Pts: TPoint2DArray): Double;
function PointInPolygon(const Pts: TPoint2DArray; X, Y: Double): Boolean;
function ProfileContains(const P: TSketchProfile; X, Y: Double): Boolean;
function ProfileArea(const P: TSketchProfile): Double;     // absolute value
function ProfileBounds(const P: TSketchProfile): TSketchBox;
function SketchBounds(const S: TSketch): TSketchBox;
// Distance from (X, Y) to the profile's outline.
function ProfileEdgeDistance(const P: TSketchProfile; X, Y: Double): Double;
function ProfileVertexCount(const P: TSketchProfile): Integer;
function ProfileVertex(const P: TSketchProfile; I: Integer): TPoint2D;
// A new shape drawn at (X, Y) is a hole when an odd number of existing
// profiles contain that point (a shape inside a solid is a hole, a shape
// inside that hole is solid again, and so on).
function DefaultHoleAt(const S: TSketch; X, Y: Double): Boolean;
// A point strictly inside the profile (for concave shapes too).
function ProfileInteriorPoint(const P: TSketchProfile): TPoint2D;

// ---------------------------------------------------------------- editing
// These change the sketch in place; call TSketchDoc.Checkpoint first.
function SkAddProfile(var S: TSketch; const P: TSketchProfile): Integer;
procedure SkDeleteProfile(var S: TSketch; I: Integer);
procedure SkMoveProfile(var S: TSketch; I: Integer; DX, DY: Double);
procedure SkMoveVertex(var S: TSketch; I, V: Integer; X, Y: Double);
procedure SkSetHole(var S: TSketch; I: Integer; AHole: Boolean);
procedure SkSetCircleRadius(var S: TSketch; I: Integer; R: Double);
// Appends the profiles of Other, shifted by (DX, DY).
procedure SkAppend(var S: TSketch; const Other: TSketch; DX, DY: Double);

// ---------------------------------------------------------------- geometry model
// Builds the FEM3DGEO model. UnassignedHoles counts holes that lie inside no
// solid (they are left out of the model).
procedure SketchToGeo(const S: TSketch; out Geo: TFEMGeometryModel;
  out UnassignedHoles: Integer);
// Reads the sections out of a geometry model (planar faces with LINE, ARC3 and
// CIRCLE edges). False, with a reason, if the model uses anything else.
function GeoToSketch(const Geo: TFEMGeometryModel; const AName: string;
  out S: TSketch; out Err: string): Boolean;

// ---------------------------------------------------------------- history
type
  TSketchDoc = class
  private
    FUndo, FRedo: array of TSketch;
    FUndoNames, FRedoNames: array of string;
  public
    Sketch: TSketch;
    Dirty: Boolean;
    constructor Create;
    procedure NewSketch(const AName, AUnit: string);
    // Replaces the sketch without recording history (loading a file).
    procedure Replace(const ASketch: TSketch; AClearHistory: Boolean = True);
    // Call BEFORE changing Sketch: remembers the current state under a name.
    procedure Checkpoint(const AName: string);
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function UndoName: string;
    function RedoName: string;
    procedure Undo;
    procedure Redo;
    function UndoDepth: Integer;
    procedure ClearHistory;
  end;

implementation

const
  TwoPi = 2.0 * Pi;

// Rounds to the 15 significant digits the .fgeo writer prints. The model built
// from a sketch is then bit-identical to the same model after being saved and
// loaded again, so the editor and the command-line tools tessellate arcs the
// same way (a sweep that is an exact multiple of the arc step can otherwise
// land on either side of the CEIL and change the polygon by a segment).
function Canon(V: Double): Double;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloat(FloatToStrF(V, ffGeneral, 15, 0, FS), FS);
end;

function V3C(X, Y: Double): TGeoVec3;
begin
  Result := V3(Canon(X), Canon(Y), 0);
end;

function P2(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

procedure SketchInit(out S: TSketch; const AName, AUnit: string);
begin
  S.Name := AName;
  S.LengthUnit := AUnit;
  S.HasHeader := False;
  FillChar(S.Header, SizeOf(S.Header), 0);
  S.Profiles := nil;
end;

procedure SketchCopy(const A: TSketch; out B: TSketch);
var
  I: Integer;
begin
  B.Name := A.Name;
  B.LengthUnit := A.LengthUnit;
  B.HasHeader := A.HasHeader;
  B.Header := A.Header;
  SetLength(B.Profiles, Length(A.Profiles));
  for I := 0 to High(A.Profiles) do
  begin
    B.Profiles[I] := A.Profiles[I];
    B.Profiles[I].Segs := Copy(A.Profiles[I].Segs);
  end;
end;

function MakeLineSeg(const A, B: TPoint2D): TSketchSeg;
begin
  Result.Kind := skLine;
  Result.P0 := A;
  Result.P1 := B;
  Result.PM := P2(0.5 * (A.X + B.X), 0.5 * (A.Y + B.Y));
end;

function MakeArcSeg(const A, M, B: TPoint2D): TSketchSeg;
begin
  Result.Kind := skArc;
  Result.P0 := A;
  Result.PM := M;
  Result.P1 := B;
end;

function MakeChainProfile(const Segs: array of TSketchSeg; AHole: Boolean): TSketchProfile;
var
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkChain;
  Result.IsHole := AHole;
  SetLength(Result.Segs, Length(Segs));
  for I := 0 to High(Segs) do Result.Segs[I] := Segs[I];
end;

function MakePolygonProfile(const Pts: array of TPoint2D; AHole: Boolean): TSketchProfile;
var
  I, N: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkChain;
  Result.IsHole := AHole;
  N := Length(Pts);
  SetLength(Result.Segs, N);
  for I := 0 to N - 1 do
    Result.Segs[I] := MakeLineSeg(Pts[I], Pts[(I + 1) mod N]);
end;

function MakeRectProfile(X0, Y0, X1, Y1: Double; AHole: Boolean): TSketchProfile;
var
  Pts: array[0..3] of TPoint2D;
  T: Double;
begin
  if X1 < X0 then begin T := X0; X0 := X1; X1 := T; end;
  if Y1 < Y0 then begin T := Y0; Y0 := Y1; Y1 := T; end;
  Pts[0] := P2(X0, Y0);
  Pts[1] := P2(X1, Y0);
  Pts[2] := P2(X1, Y1);
  Pts[3] := P2(X0, Y1);
  Result := MakePolygonProfile(Pts, AHole);
end;

function MakeCircleProfile(CX, CY, R: Double; AHole: Boolean): TSketchProfile;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkCircle;
  Result.IsHole := AHole;
  Result.Center := P2(CX, CY);
  Result.Radius := R;
end;

// ---------------------------------------------------------------- geometry

function ArcCircle(const P0, PM, P1: TPoint2D; out CX, CY, R, A0, Sweep: Double): Boolean;
var
  D, NumT, T, AMid, AEnd, D1, D2: Double;
begin
  Result := False;
  D := (PM.X - P0.X) * (P1.Y - PM.Y) - (PM.Y - P0.Y) * (P1.X - PM.X);
  if Abs(D) < 1.0E-12 then Exit;
  NumT := (P1.X - P0.X) * (P1.X - PM.X) + (P1.Y - P0.Y) * (P1.Y - PM.Y);
  T := NumT / (2.0 * D);
  CX := 0.5 * (P0.X + PM.X) - T * (PM.Y - P0.Y);
  CY := 0.5 * (P0.Y + PM.Y) + T * (PM.X - P0.X);
  R := Sqrt(Sqr(P0.X - CX) + Sqr(P0.Y - CY));
  A0 := ArcTan2(P0.Y - CY, P0.X - CX);
  AMid := ArcTan2(PM.Y - CY, PM.X - CX);
  AEnd := ArcTan2(P1.Y - CY, P1.X - CX);
  D1 := AMid - A0;
  while D1 <= -Pi do D1 := D1 + TwoPi;
  while D1 > Pi do D1 := D1 - TwoPi;
  D2 := AEnd - AMid;
  while D2 <= -Pi do D2 := D2 + TwoPi;
  while D2 > Pi do D2 := D2 - TwoPi;
  Sweep := D1 + D2;
  Result := True;
end;

procedure ProfileFlatten(const P: TSketchProfile; out Pts: TPoint2DArray;
  MaxStepRad: Double);
var
  I, K, N, Count: Integer;
  CX, CY, R, A0, Sw, Ang: Double;
  Seg: TSketchSeg;
begin
  Pts := nil;
  if MaxStepRad <= 0 then MaxStepRad := 0.1;
  if P.Kind = pkCircle then
  begin
    N := Max(24, Ceil(TwoPi / MaxStepRad));
    SetLength(Pts, N);
    for I := 0 to N - 1 do
    begin
      Ang := TwoPi * I / N;
      Pts[I] := P2(P.Center.X + P.Radius * Cos(Ang), P.Center.Y + P.Radius * Sin(Ang));
    end;
    Exit;
  end;
  Count := 0;
  for I := 0 to High(P.Segs) do
  begin
    Seg := P.Segs[I];
    if (Seg.Kind = skArc) and ArcCircle(Seg.P0, Seg.PM, Seg.P1, CX, CY, R, A0, Sw) then
    begin
      N := Max(2, Ceil(Abs(Sw) / MaxStepRad));
      SetLength(Pts, Count + N);
      for K := 0 to N - 1 do
      begin
        Ang := A0 + Sw * K / N;
        Pts[Count + K] := P2(CX + R * Cos(Ang), CY + R * Sin(Ang));
      end;
      Pts[Count] := Seg.P0;     // exact start point
      Inc(Count, N);
    end
    else
    begin
      SetLength(Pts, Count + 1);
      Pts[Count] := Seg.P0;
      Inc(Count);
    end;
  end;
end;

function PolygonSignedArea(const Pts: TPoint2DArray): Double;
var
  I, N: Integer;
begin
  Result := 0;
  N := Length(Pts);
  for I := 0 to N - 1 do
    Result := Result + (Pts[I].X * Pts[(I + 1) mod N].Y - Pts[(I + 1) mod N].X * Pts[I].Y);
  Result := 0.5 * Result;
end;

function PointInPolygon(const Pts: TPoint2DArray; X, Y: Double): Boolean;
var
  I, J, N: Integer;
begin
  Result := False;
  N := Length(Pts);
  if N < 3 then Exit;
  J := N - 1;
  for I := 0 to N - 1 do
  begin
    if ((Pts[I].Y > Y) <> (Pts[J].Y > Y)) and
       (X < (Pts[J].X - Pts[I].X) * (Y - Pts[I].Y) / (Pts[J].Y - Pts[I].Y) + Pts[I].X) then
      Result := not Result;
    J := I;
  end;
end;

function ProfileContains(const P: TSketchProfile; X, Y: Double): Boolean;
var
  Pts: TPoint2DArray;
begin
  if P.Kind = pkCircle then
    Exit(Sqr(X - P.Center.X) + Sqr(Y - P.Center.Y) < Sqr(P.Radius));
  ProfileFlatten(P, Pts, 0.05);
  Result := PointInPolygon(Pts, X, Y);
end;

function ProfileArea(const P: TSketchProfile): Double;
var
  Pts: TPoint2DArray;
begin
  if P.Kind = pkCircle then Exit(Pi * Sqr(P.Radius));
  ProfileFlatten(P, Pts, 0.02);
  Result := Abs(PolygonSignedArea(Pts));
end;

function ProfileBounds(const P: TSketchProfile): TSketchBox;
var
  Pts: TPoint2DArray;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if P.Kind = pkCircle then
  begin
    Result.XMin := P.Center.X - P.Radius;
    Result.XMax := P.Center.X + P.Radius;
    Result.YMin := P.Center.Y - P.Radius;
    Result.YMax := P.Center.Y + P.Radius;
    Result.Valid := True;
    Exit;
  end;
  ProfileFlatten(P, Pts, 0.05);
  for I := 0 to High(Pts) do
  begin
    if not Result.Valid then
    begin
      Result.XMin := Pts[I].X; Result.XMax := Pts[I].X;
      Result.YMin := Pts[I].Y; Result.YMax := Pts[I].Y;
      Result.Valid := True;
    end
    else
    begin
      if Pts[I].X < Result.XMin then Result.XMin := Pts[I].X;
      if Pts[I].X > Result.XMax then Result.XMax := Pts[I].X;
      if Pts[I].Y < Result.YMin then Result.YMin := Pts[I].Y;
      if Pts[I].Y > Result.YMax then Result.YMax := Pts[I].Y;
    end;
  end;
end;

function SketchBounds(const S: TSketch): TSketchBox;
var
  I: Integer;
  B: TSketchBox;
begin
  FillChar(Result, SizeOf(Result), 0);
  for I := 0 to High(S.Profiles) do
  begin
    B := ProfileBounds(S.Profiles[I]);
    if not B.Valid then Continue;
    if not Result.Valid then
      Result := B
    else
    begin
      Result.XMin := Min(Result.XMin, B.XMin);
      Result.XMax := Max(Result.XMax, B.XMax);
      Result.YMin := Min(Result.YMin, B.YMin);
      Result.YMax := Max(Result.YMax, B.YMax);
    end;
  end;
end;

function SegDist(const A, B: TPoint2D; X, Y: Double): Double;
var
  DX, DY, L2, T: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  L2 := DX * DX + DY * DY;
  if L2 < 1.0E-30 then Exit(Sqrt(Sqr(X - A.X) + Sqr(Y - A.Y)));
  T := ((X - A.X) * DX + (Y - A.Y) * DY) / L2;
  if T < 0 then T := 0;
  if T > 1 then T := 1;
  Result := Sqrt(Sqr(X - (A.X + T * DX)) + Sqr(Y - (A.Y + T * DY)));
end;

function ProfileEdgeDistance(const P: TSketchProfile; X, Y: Double): Double;
var
  Pts: TPoint2DArray;
  I, N: Integer;
begin
  if P.Kind = pkCircle then
    Exit(Abs(Sqrt(Sqr(X - P.Center.X) + Sqr(Y - P.Center.Y)) - P.Radius));
  ProfileFlatten(P, Pts, 0.05);
  N := Length(Pts);
  Result := 1.0E300;
  for I := 0 to N - 1 do
    Result := Min(Result, SegDist(Pts[I], Pts[(I + 1) mod N], X, Y));
end;

function ProfileVertexCount(const P: TSketchProfile): Integer;
begin
  if P.Kind = pkChain then Result := Length(P.Segs) else Result := 0;
end;

function ProfileVertex(const P: TSketchProfile; I: Integer): TPoint2D;
begin
  Result := P.Segs[I].P0;
end;

function DefaultHoleAt(const S: TSketch; X, Y: Double): Boolean;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to High(S.Profiles) do
    if ProfileContains(S.Profiles[I], X, Y) then Inc(N);
  Result := Odd(N);
end;

function ProfileInteriorPoint(const P: TSketchProfile): TPoint2D;
var
  Pts: TPoint2DArray;
  B: TSketchBox;
  Y, Tmp, BestW: Double;
  Xs: array of Double;
  I, J, N, K: Integer;
begin
  if P.Kind = pkCircle then Exit(P.Center);
  ProfileFlatten(P, Pts, 0.05);
  B := ProfileBounds(P);
  Result := P2(0.5 * (B.XMin + B.XMax), 0.5 * (B.YMin + B.YMax));
  if Length(Pts) < 3 then Exit;
  BestW := -1;
  // scan a few horizontal lines; take the middle of the widest interval found
  for K := 1 to 7 do
  begin
    Y := B.YMin + (B.YMax - B.YMin) * K / 8.0;
    SetLength(Xs, 0);
    N := Length(Pts);
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      if (Pts[I].Y > Y) <> (Pts[J].Y > Y) then
      begin
        SetLength(Xs, Length(Xs) + 1);
        Xs[High(Xs)] := Pts[I].X + (Y - Pts[I].Y) * (Pts[J].X - Pts[I].X) / (Pts[J].Y - Pts[I].Y);
      end;
    end;
    for I := 0 to High(Xs) do
      for J := I + 1 to High(Xs) do
        if Xs[J] < Xs[I] then begin Tmp := Xs[I]; Xs[I] := Xs[J]; Xs[J] := Tmp; end;
    I := 0;
    while I + 1 <= High(Xs) do
    begin
      if Xs[I + 1] - Xs[I] > BestW then
      begin
        BestW := Xs[I + 1] - Xs[I];
        Result := P2(0.5 * (Xs[I] + Xs[I + 1]), Y);
      end;
      Inc(I, 2);
    end;
  end;
end;

// ---------------------------------------------------------------- editing

function SkAddProfile(var S: TSketch; const P: TSketchProfile): Integer;
begin
  Result := Length(S.Profiles);
  SetLength(S.Profiles, Result + 1);
  S.Profiles[Result] := P;
  S.Profiles[Result].Segs := Copy(P.Segs);
end;

procedure SkDeleteProfile(var S: TSketch; I: Integer);
var
  K: Integer;
begin
  if (I < 0) or (I > High(S.Profiles)) then Exit;
  for K := I to High(S.Profiles) - 1 do
    S.Profiles[K] := S.Profiles[K + 1];
  SetLength(S.Profiles, Length(S.Profiles) - 1);
end;

procedure SkMoveProfile(var S: TSketch; I: Integer; DX, DY: Double);
var
  K: Integer;
begin
  if (I < 0) or (I > High(S.Profiles)) then Exit;
  with S.Profiles[I] do
    if Kind = pkCircle then
    begin
      Center.X := Center.X + DX;
      Center.Y := Center.Y + DY;
    end
    else
      for K := 0 to High(Segs) do
      begin
        Segs[K].P0.X := Segs[K].P0.X + DX;  Segs[K].P0.Y := Segs[K].P0.Y + DY;
        Segs[K].PM.X := Segs[K].PM.X + DX;  Segs[K].PM.Y := Segs[K].PM.Y + DY;
        Segs[K].P1.X := Segs[K].P1.X + DX;  Segs[K].P1.Y := Segs[K].P1.Y + DY;
      end;
end;

procedure SkMoveVertex(var S: TSketch; I, V: Integer; X, Y: Double);
var
  N, Prev: Integer;
begin
  if (I < 0) or (I > High(S.Profiles)) then Exit;
  with S.Profiles[I] do
  begin
    if Kind <> pkChain then Exit;
    N := Length(Segs);
    if (V < 0) or (V >= N) then Exit;
    Prev := (V + N - 1) mod N;
    Segs[V].P0 := P2(X, Y);
    Segs[Prev].P1 := P2(X, Y);
    // a straight segment's midpoint follows its end points
    if Segs[V].Kind = skLine then
      Segs[V].PM := P2(0.5 * (Segs[V].P0.X + Segs[V].P1.X), 0.5 * (Segs[V].P0.Y + Segs[V].P1.Y));
    if Segs[Prev].Kind = skLine then
      Segs[Prev].PM := P2(0.5 * (Segs[Prev].P0.X + Segs[Prev].P1.X), 0.5 * (Segs[Prev].P0.Y + Segs[Prev].P1.Y));
  end;
end;

procedure SkSetHole(var S: TSketch; I: Integer; AHole: Boolean);
begin
  if (I >= 0) and (I <= High(S.Profiles)) then S.Profiles[I].IsHole := AHole;
end;

procedure SkSetCircleRadius(var S: TSketch; I: Integer; R: Double);
begin
  if (I >= 0) and (I <= High(S.Profiles)) and (S.Profiles[I].Kind = pkCircle) and (R > 0) then
    S.Profiles[I].Radius := R;
end;

procedure SkAppend(var S: TSketch; const Other: TSketch; DX, DY: Double);
var
  I, N: Integer;
begin
  for I := 0 to High(Other.Profiles) do
  begin
    N := SkAddProfile(S, Other.Profiles[I]);
    SkMoveProfile(S, N, DX, DY);
  end;
end;

// ---------------------------------------------------------------- geometry model

procedure SketchToGeo(const S: TSketch; out Geo: TFEMGeometryModel;
  out UnassignedHoles: Integer);
var
  Solids: array of Integer;        // profile indices of the solids
  Owner: array of Integer;         // per profile: for a hole, its solid's index into Solids, else -1
  LoopId: array of Integer;        // per profile: the loop written for it
  I, J, K, NSolid, Best: Integer;
  Pts: TPoint2DArray;
  BestArea, A: Double;
  NextV, NextC, NextE, NextL, SurfId: Integer;
  Face: TGeoFace;
  Body: TGeoBody;

  function AddVertex(const P: TPoint2D): Integer;
  begin
    Result := NextV;
    Inc(NextV);
    SetLength(Geo.Vertices, Length(Geo.Vertices) + 1);
    Geo.Vertices[High(Geo.Vertices)].Id := Result;
    Geo.Vertices[High(Geo.Vertices)].P := V3C(P.X, P.Y);
  end;

  function AddCurve(const C: TGeoCurve): Integer;
  begin
    Result := NextC;
    Inc(NextC);
    SetLength(Geo.Curves, Length(Geo.Curves) + 1);
    Geo.Curves[High(Geo.Curves)] := C;
    Geo.Curves[High(Geo.Curves)].Id := Result;
  end;

  function AddEdge(AV0, AV1, ACurve: Integer; AT0, AT1: Double): Integer;
  begin
    Result := NextE;
    Inc(NextE);
    SetLength(Geo.Edges, Length(Geo.Edges) + 1);
    // (parameter names differ from the record's fields on purpose: inside a
    // "with" block a parameter called T0 would be shadowed by the field T0)
    Geo.Edges[High(Geo.Edges)].Id := Result;
    Geo.Edges[High(Geo.Edges)].StartVertexId := AV0;
    Geo.Edges[High(Geo.Edges)].EndVertexId := AV1;
    Geo.Edges[High(Geo.Edges)].CurveId := ACurve;
    Geo.Edges[High(Geo.Edges)].T0 := AT0;
    Geo.Edges[High(Geo.Edges)].T1 := AT1;
    Geo.Edges[High(Geo.Edges)].Sense := 1;
  end;

  // Writes the profile's vertices, curves, edges and loop; returns the loop id.
  function WriteLoop(const P: TSketchProfile; WantCCW: Boolean): Integer;
  var
    Segs: TSketchSegArray;
    N, Q, V0, VStart, EId, CId: Integer;
    FlatPts: TPoint2DArray;
    Cu: TGeoCurve;
    Lp: TGeoLoop;
    Tmp: TSketchSeg;
    Rev: Boolean;
  begin
    Lp.Id := NextL;
    Inc(NextL);
    Lp.EdgeUses := nil;
    if P.Kind = pkCircle then
    begin
      V0 := AddVertex(P2(P.Center.X + P.Radius, P.Center.Y));
      FillChar(Cu, SizeOf(Cu), 0);
      Cu.Kind := gcCircle;
      Cu.CircleCenter := V3C(P.Center.X, P.Center.Y);
      Cu.CircleNormal := V3(0, 0, 1);
      Cu.CircleRadius := Canon(P.Radius);
      CId := AddCurve(Cu);
      EId := AddEdge(V0, V0, CId, 0, Canon(TwoPi));
      SetLength(Lp.EdgeUses, 1);
      Lp.EdgeUses[0].EdgeId := EId;
      Lp.EdgeUses[0].Sense := 1;
    end
    else
    begin
      Segs := Copy(P.Segs);
      N := Length(Segs);
      ProfileFlatten(P, FlatPts, 0.1);
      Rev := (PolygonSignedArea(FlatPts) > 0) <> WantCCW;
      if Rev then
      begin
        for Q := 0 to (N div 2) - 1 do
        begin
          Tmp := Segs[Q];
          Segs[Q] := Segs[N - 1 - Q];
          Segs[N - 1 - Q] := Tmp;
        end;
        for Q := 0 to N - 1 do
        begin
          Tmp := Segs[Q];
          Segs[Q].P0 := Tmp.P1;
          Segs[Q].P1 := Tmp.P0;
        end;
      end;
      VStart := NextV;
      for Q := 0 to N - 1 do AddVertex(Segs[Q].P0);
      SetLength(Lp.EdgeUses, N);
      for Q := 0 to N - 1 do
      begin
        FillChar(Cu, SizeOf(Cu), 0);
        if Segs[Q].Kind = skArc then
        begin
          Cu.Kind := gcArc3;
          Cu.Arc3Start := V3C(Segs[Q].P0.X, Segs[Q].P0.Y);
          Cu.Arc3Mid := V3C(Segs[Q].PM.X, Segs[Q].PM.Y);
          Cu.Arc3End := V3C(Segs[Q].P1.X, Segs[Q].P1.Y);
        end
        else
        begin
          Cu.Kind := gcLine;
          Cu.LineOrigin := V3C(Segs[Q].P0.X, Segs[Q].P0.Y);
          Cu.LineDirection := V3C(Segs[Q].P1.X - Segs[Q].P0.X, Segs[Q].P1.Y - Segs[Q].P0.Y);
        end;
        CId := AddCurve(Cu);
        EId := AddEdge(VStart + Q, VStart + ((Q + 1) mod N), CId, 0, 1);
        Lp.EdgeUses[Q].EdgeId := EId;
        Lp.EdgeUses[Q].Sense := 1;
      end;
    end;
    SetLength(Geo.Loops, Length(Geo.Loops) + 1);
    Geo.Loops[High(Geo.Loops)] := Lp;
    Result := Lp.Id;
  end;

begin
  Geo := Default(TFEMGeometryModel);
  UnassignedHoles := 0;
  NextV := 1; NextC := 1; NextE := 1; NextL := 1; SurfId := 1;

  // header
  if S.HasHeader then Geo.Header := S.Header;
  Geo.Header.HasUnits := True;
  if S.LengthUnit <> '' then Geo.Header.LengthUnit := S.LengthUnit;
  if Geo.Header.LengthUnit = '' then Geo.Header.LengthUnit := 'mm';
  Geo.Header.HasCoordSys := True;
  Geo.Header.CoordSys := 'CARTESIAN';
  Geo.Header.HasSource := True;
  if Geo.Header.SourceFormat = '' then Geo.Header.SourceFormat := 'MANUAL';
  Geo.Header.SourceName := S.Name;

  // which profiles are solids, which hole belongs to which solid
  NSolid := 0;
  SetLength(Owner, Length(S.Profiles));
  SetLength(LoopId, Length(S.Profiles));
  for I := 0 to High(S.Profiles) do
  begin
    Owner[I] := -1;
    LoopId[I] := -1;
    if not S.Profiles[I].IsHole then
    begin
      SetLength(Solids, NSolid + 1);
      Solids[NSolid] := I;
      Inc(NSolid);
    end;
  end;
  for I := 0 to High(S.Profiles) do
    if S.Profiles[I].IsHole then
    begin
      ProfileFlatten(S.Profiles[I], Pts, 0.1);
      Best := -1;
      BestArea := 1.0E300;
      if Length(Pts) > 0 then
        for J := 0 to NSolid - 1 do
          if ProfileContains(S.Profiles[Solids[J]], Pts[0].X, Pts[0].Y) then
          begin
            A := ProfileArea(S.Profiles[Solids[J]]);
            if A < BestArea then begin BestArea := A; Best := J; end;
          end;
      Owner[I] := Best;
      if Best < 0 then Inc(UnassignedHoles);
    end;

  if NSolid = 0 then Exit;

  // loops: solids counter-clockwise, holes clockwise
  for I := 0 to High(S.Profiles) do
    if (not S.Profiles[I].IsHole) or (Owner[I] >= 0) then
      LoopId[I] := WriteLoop(S.Profiles[I], not S.Profiles[I].IsHole);

  SetLength(Geo.Surfaces, 1);
  Geo.Surfaces[0].Id := SurfId;
  Geo.Surfaces[0].Kind := gsPlane;
  Geo.Surfaces[0].PlaneOrigin := V3(0, 0, 0);
  Geo.Surfaces[0].PlaneNormal := V3(0, 0, 1);

  Body.Id := 1;
  Body.FaceIds := nil;
  for J := 0 to NSolid - 1 do
  begin
    Face.Id := J + 1;
    Face.SurfaceId := SurfId;
    Face.OuterLoopId := LoopId[Solids[J]];
    Face.InnerLoopIds := nil;
    for I := 0 to High(S.Profiles) do
      if S.Profiles[I].IsHole and (Owner[I] = J) then
      begin
        K := Length(Face.InnerLoopIds);
        SetLength(Face.InnerLoopIds, K + 1);
        Face.InnerLoopIds[K] := LoopId[I];
      end;
    SetLength(Geo.Faces, Length(Geo.Faces) + 1);
    Geo.Faces[High(Geo.Faces)] := Face;
    SetLength(Body.FaceIds, Length(Body.FaceIds) + 1);
    Body.FaceIds[High(Body.FaceIds)] := Face.Id;
  end;
  SetLength(Geo.Bodies, 1);
  Geo.Bodies[0] := Body;
end;

function GeoToSketch(const Geo: TFEMGeometryModel; const AName: string;
  out S: TSketch; out Err: string): Boolean;
var
  F, K: Integer;

  function FindVertex(Id: Integer; out P: TPoint2D): Boolean;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Geo.Vertices) do
      if Geo.Vertices[Q].Id = Id then
      begin
        P := P2(Geo.Vertices[Q].P.X, Geo.Vertices[Q].P.Y);
        Exit(True);
      end;
    Result := False;
  end;

  function FindCurve(Id: Integer; out C: TGeoCurve): Boolean;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Geo.Curves) do
      if Geo.Curves[Q].Id = Id then begin C := Geo.Curves[Q]; Exit(True); end;
    Result := False;
  end;

  function FindEdge(Id: Integer; out E: TGeoEdge): Boolean;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Geo.Edges) do
      if Geo.Edges[Q].Id = Id then begin E := Geo.Edges[Q]; Exit(True); end;
    Result := False;
  end;

  function FindLoop(Id: Integer; out L: TGeoLoop): Boolean;
  var
    Q: Integer;
  begin
    for Q := 0 to High(Geo.Loops) do
      if Geo.Loops[Q].Id = Id then begin L := Geo.Loops[Q]; Exit(True); end;
    Result := False;
  end;

  function LoopToProfile(const L: TGeoLoop; AHole: Boolean; out Prof: TSketchProfile): Boolean;
  var
    U, N: Integer;
    Ed: TGeoEdge;
    Cv: TGeoCurve;
    VA, VB, PMid: TPoint2D;
    SV, EV: Integer;
    CX, CY, R, A0, Sw, Ang, Dir, TMid, Tol: Double;
    Segs: TSketchSegArray;
    Closed: Boolean;
  begin
    Result := False;
    FillChar(Prof, SizeOf(Prof), 0);
    N := Length(L.EdgeUses);
    if N = 0 then begin Err := 'A loop has no edges.'; Exit; end;

    // a single self-closing circular edge is a circle
    if N = 1 then
    begin
      if FindEdge(L.EdgeUses[0].EdgeId, Ed) and FindCurve(Ed.CurveId, Cv) and
         (Cv.Kind = gcCircle) and (Ed.StartVertexId = Ed.EndVertexId) and
         (Abs(Abs(Ed.T1 - Ed.T0) - TwoPi) < 1.0E-6) then
      begin
        if Abs(Cv.CircleNormal.Z) < 1.0E-9 then
        begin
          Err := 'A circle is not in the XY plane.';
          Exit;
        end;
        Prof := MakeCircleProfile(Cv.CircleCenter.X, Cv.CircleCenter.Y, Cv.CircleRadius, AHole);
        Exit(True);
      end;
    end;

    SetLength(Segs, N);
    for U := 0 to N - 1 do
    begin
      if not FindEdge(L.EdgeUses[U].EdgeId, Ed) then
      begin Err := 'A loop refers to a missing edge.'; Exit; end;
      if L.EdgeUses[U].Sense >= 0 then begin SV := Ed.StartVertexId; EV := Ed.EndVertexId; end
      else begin SV := Ed.EndVertexId; EV := Ed.StartVertexId; end;
      if not FindVertex(SV, VA) or not FindVertex(EV, VB) then
      begin Err := 'An edge refers to a missing vertex.'; Exit; end;
      if not FindCurve(Ed.CurveId, Cv) then
      begin Err := 'An edge refers to a missing curve.'; Exit; end;
      case Cv.Kind of
        gcLine:
          Segs[U] := MakeLineSeg(VA, VB);
        gcArc3:
          begin
            if (Ed.T0 = 0) and (Ed.T1 = 1) then
              PMid := P2(Cv.Arc3Mid.X, Cv.Arc3Mid.Y)
            else
            begin
              if not ArcCircle(P2(Cv.Arc3Start.X, Cv.Arc3Start.Y), P2(Cv.Arc3Mid.X, Cv.Arc3Mid.Y),
                   P2(Cv.Arc3End.X, Cv.Arc3End.Y), CX, CY, R, A0, Sw) then
              begin Err := 'An arc has collinear points.'; Exit; end;
              TMid := 0.5 * (Ed.T0 + Ed.T1);
              Ang := A0 + Sw * TMid;
              PMid := P2(CX + R * Cos(Ang), CY + R * Sin(Ang));
            end;
            Segs[U] := MakeArcSeg(VA, PMid, VB);
          end;
        gcCircle:
          begin
            if Abs(Cv.CircleNormal.Z) < 1.0E-9 then
            begin Err := 'A circle is not in the XY plane.'; Exit; end;
            if Cv.CircleNormal.Z >= 0 then Dir := 1 else Dir := -1;
            TMid := 0.5 * (Ed.T0 + Ed.T1);
            Ang := Dir * TMid;
            PMid := P2(Cv.CircleCenter.X + Cv.CircleRadius * Cos(Ang),
                       Cv.CircleCenter.Y + Cv.CircleRadius * Sin(Ang));
            Segs[U] := MakeArcSeg(VA, PMid, VB);
          end;
      else
        Err := 'Unsupported curve kind.';
        Exit;
      end;
    end;

    // consecutive segments must join up
    Tol := 1.0E-6;
    Closed := True;
    for U := 0 to N - 1 do
      if (Abs(Segs[U].P1.X - Segs[(U + 1) mod N].P0.X) > Tol * Max(1.0, Abs(Segs[U].P1.X))) or
         (Abs(Segs[U].P1.Y - Segs[(U + 1) mod N].P0.Y) > Tol * Max(1.0, Abs(Segs[U].P1.Y))) then
        Closed := False;
    if not Closed then
    begin Err := 'A loop is not closed in the order its edges are listed.'; Exit; end;

    Prof := MakeChainProfile(Segs, AHole);
    Result := True;
  end;

  function AddLoop(LoopIdVal: Integer; AHole: Boolean): Boolean;
  var
    L: TGeoLoop;
    Prof: TSketchProfile;
  begin
    Result := False;
    if not FindLoop(LoopIdVal, L) then begin Err := 'A face refers to a missing loop.'; Exit; end;
    if not LoopToProfile(L, AHole, Prof) then Exit;
    SkAddProfile(S, Prof);
    Result := True;
  end;

  function SurfaceIsXY(Id: Integer): Boolean;
  var
    Q: Integer;
  begin
    Result := False;
    for Q := 0 to High(Geo.Surfaces) do
      if Geo.Surfaces[Q].Id = Id then
        Exit((Geo.Surfaces[Q].Kind = gsPlane) and
             (Abs(Geo.Surfaces[Q].PlaneNormal.Z) > 1.0E-9) and
             (Abs(Geo.Surfaces[Q].PlaneNormal.X) < 1.0E-9 * Abs(Geo.Surfaces[Q].PlaneNormal.Z)) and
             (Abs(Geo.Surfaces[Q].PlaneNormal.Y) < 1.0E-9 * Abs(Geo.Surfaces[Q].PlaneNormal.Z)));
  end;

begin
  SketchInit(S, AName, 'mm');
  Err := '';
  S.HasHeader := True;
  S.Header := Geo.Header;
  if Geo.Header.HasUnits and (Geo.Header.LengthUnit <> '') then S.LengthUnit := Geo.Header.LengthUnit;
  if Geo.Header.HasSource and (Geo.Header.SourceName <> '') then S.Name := Geo.Header.SourceName;

  if Length(Geo.Faces) = 0 then
  begin
    Err := 'The file contains no faces.';
    Exit(False);
  end;
  for F := 0 to High(Geo.Faces) do
  begin
    if not SurfaceIsXY(Geo.Faces[F].SurfaceId) then
    begin
      Err := 'Only faces on a plane parallel to XY can be edited (face ' +
        IntToStr(Geo.Faces[F].Id) + ').';
      Exit(False);
    end;
    if not AddLoop(Geo.Faces[F].OuterLoopId, False) then Exit(False);
    for K := 0 to High(Geo.Faces[F].InnerLoopIds) do
      if not AddLoop(Geo.Faces[F].InnerLoopIds[K], True) then Exit(False);
  end;
  Result := True;
end;

// ---------------------------------------------------------------- history

constructor TSketchDoc.Create;
begin
  inherited Create;
  SketchInit(Sketch, 'Section', 'mm');
  Dirty := False;
end;

procedure TSketchDoc.NewSketch(const AName, AUnit: string);
begin
  SketchInit(Sketch, AName, AUnit);
  ClearHistory;
  Dirty := False;
end;

procedure TSketchDoc.Replace(const ASketch: TSketch; AClearHistory: Boolean);
begin
  SketchCopy(ASketch, Sketch);
  if AClearHistory then ClearHistory;
  Dirty := False;
end;

procedure TSketchDoc.ClearHistory;
begin
  FUndo := nil;
  FRedo := nil;
  FUndoNames := nil;
  FRedoNames := nil;
end;

procedure TSketchDoc.Checkpoint(const AName: string);
var
  N: Integer;
begin
  N := Length(FUndo);
  SetLength(FUndo, N + 1);
  SetLength(FUndoNames, N + 1);
  SketchCopy(Sketch, FUndo[N]);
  FUndoNames[N] := AName;
  FRedo := nil;
  FRedoNames := nil;
  Dirty := True;
end;

function TSketchDoc.CanUndo: Boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TSketchDoc.CanRedo: Boolean;
begin
  Result := Length(FRedo) > 0;
end;

function TSketchDoc.UndoName: string;
begin
  if CanUndo then Result := FUndoNames[High(FUndoNames)] else Result := '';
end;

function TSketchDoc.RedoName: string;
begin
  if CanRedo then Result := FRedoNames[High(FRedoNames)] else Result := '';
end;

function TSketchDoc.UndoDepth: Integer;
begin
  Result := Length(FUndo);
end;

procedure TSketchDoc.Undo;
var
  N, M: Integer;
begin
  N := Length(FUndo);
  if N = 0 then Exit;
  M := Length(FRedo);
  SetLength(FRedo, M + 1);
  SetLength(FRedoNames, M + 1);
  SketchCopy(Sketch, FRedo[M]);
  FRedoNames[M] := FUndoNames[N - 1];
  SketchCopy(FUndo[N - 1], Sketch);
  SetLength(FUndo, N - 1);
  SetLength(FUndoNames, N - 1);
  Dirty := True;
end;

procedure TSketchDoc.Redo;
var
  N, M: Integer;
begin
  M := Length(FRedo);
  if M = 0 then Exit;
  N := Length(FUndo);
  SetLength(FUndo, N + 1);
  SetLength(FUndoNames, N + 1);
  SketchCopy(Sketch, FUndo[N]);
  FUndoNames[N] := FRedoNames[M - 1];
  SketchCopy(FRedo[M - 1], Sketch);
  SetLength(FRedo, M - 1);
  SetLength(FRedoNames, M - 1);
  Dirty := True;
end;

end.
