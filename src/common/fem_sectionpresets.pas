unit fem_sectionpresets;

// Parametric section shapes for the native section editor: rectangle, circular
// and rectangular hollow sections, I/H beam with root fillets, parallel-flange
// channel, angle and tee. Each builds a TSketch (so they can be edited like
// anything drawn by hand). No LCL dependency; the closed-form properties of
// every shape are checked in the unit tests.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_section_types, fem_sketch;

type
  TPresetParam = record
    Name: string;      // short key, e.g. 'tf'
    Caption: string;   // shown in the dialog, e.g. 'Flange thickness tf'
    DefaultValue: Double;
  end;

  TPresetDef = record
    Id: string;
    Caption: string;
    Params: array of TPresetParam;
  end;

function PresetCount: Integer;
function PresetDefAt(Index: Integer): TPresetDef;
function FindPreset(const Id: string): Integer;

// Factor that turns the millimetre default dimensions into the given length
// unit (mm 1, cm 0.1, m 0.001, in 1/25.4; anything else 1).
function DefaultScaleForUnit(const LengthUnit: string): Double;

// Values are in the same order as the preset's parameters. Returns False with a
// message when the dimensions do not make a valid shape.
function BuildPreset(const Id: string; const Values: array of Double;
  const LengthUnit: string; out S: TSketch; out Err: string): Boolean;

implementation

var
  Defs: array of TPresetDef;

function P2(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

procedure AddDef(const AId, ACaption: string; const ANames, ACaptions: array of string;
  const ADefaults: array of Double);
var
  N, I: Integer;
begin
  N := Length(Defs);
  SetLength(Defs, N + 1);
  Defs[N].Id := AId;
  Defs[N].Caption := ACaption;
  SetLength(Defs[N].Params, Length(ANames));
  for I := 0 to High(ANames) do
  begin
    Defs[N].Params[I].Name := ANames[I];
    Defs[N].Params[I].Caption := ACaptions[I];
    Defs[N].Params[I].DefaultValue := ADefaults[I];
  end;
end;

procedure InitDefs;
begin
  AddDef('rect', 'Rectangle', ['b', 'h'], ['Width b', 'Height h'], [100, 200]);
  AddDef('chs', 'Circular hollow section', ['D', 't'], ['Outside diameter D', 'Wall thickness t'], [168.3, 6.4]);
  AddDef('rhs', 'Rectangular hollow section', ['b', 'h', 't'],
    ['Width b', 'Height h', 'Wall thickness t'], [100, 150, 6]);
  AddDef('ibeam', 'I / H section (with root fillets)', ['d', 'bf', 'tf', 'tw', 'r'],
    ['Depth d', 'Flange width bf', 'Flange thickness tf', 'Web thickness tw', 'Root radius r'],
    [203.2, 133, 7.8, 5.8, 8.9]);
  AddDef('channel', 'Parallel-flange channel', ['d', 'bf', 'tf', 'tw', 'r'],
    ['Depth d', 'Flange width bf', 'Flange thickness tf', 'Web thickness tw', 'Root radius r'],
    [200, 75, 12.5, 6, 12]);
  AddDef('angle', 'Angle (equal or unequal)', ['b', 'd', 't', 'r'],
    ['Horizontal leg b', 'Vertical leg d', 'Thickness t', 'Root radius r'],
    [100, 150, 12, 10]);
  AddDef('tee', 'Tee', ['bf', 'd', 'tf', 'tw'],
    ['Flange width bf', 'Overall depth d', 'Flange thickness tf', 'Web thickness tw'],
    [150, 150, 12, 8]);
end;

function PresetCount: Integer;
begin
  Result := Length(Defs);
end;

function PresetDefAt(Index: Integer): TPresetDef;
begin
  Result := Defs[Index];
end;

function FindPreset(const Id: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Defs) do
    if SameText(Defs[I].Id, Id) then Exit(I);
  Result := -1;
end;

function DefaultScaleForUnit(const LengthUnit: string): Double;
begin
  if SameText(LengthUnit, 'm') then Result := 0.001
  else if SameText(LengthUnit, 'cm') then Result := 0.1
  else if SameText(LengthUnit, 'in') then Result := 1.0 / 25.4
  else if SameText(LengthUnit, 'ft') then Result := 1.0 / 304.8
  else Result := 1.0;
end;

// A concave fillet arc from P0 to P1 about centre C, as an arc segment through
// the point of the arc nearest the corner.
function FilletSeg(const P0, P1, C: TPoint2D; R: Double): TSketchSeg;
var
  MX, MY, L: Double;
begin
  MX := 0.5 * (P0.X + P1.X) - C.X;
  MY := 0.5 * (P0.Y + P1.Y) - C.Y;
  L := Sqrt(MX * MX + MY * MY);
  Result := MakeArcSeg(P0, P2(C.X + R * MX / L, C.Y + R * MY / L), P1);
end;

// Builds a closed chain from a list of corner points where some corners carry
// a fillet. Pts[i] with Fillet[i] > 0 is replaced by an arc: the corner is cut
// back by Fillet[i] along both edges.
function RoundedChain(const Pts: array of TPoint2D; const Fillet: array of Double;
  AHole: Boolean): TSketchProfile;
var
  N, I: Integer;
  Prev, Next: TPoint2D;
  A, B, C: TPoint2D;
  Segs: TSketchSegArray;
  Cnt: Integer;
  Entry, Exit_: array of TPoint2D;
  Rad: Double;
  DX1, DY1, DX2, DY2, L1, L2: Double;

  procedure Push(const S: TSketchSeg);
  begin
    SetLength(Segs, Cnt + 1);
    Segs[Cnt] := S;
    Inc(Cnt);
  end;

begin
  N := Length(Pts);
  SetLength(Entry, N);
  SetLength(Exit_, N);
  for I := 0 to N - 1 do
  begin
    Prev := Pts[(I + N - 1) mod N];
    Next := Pts[(I + 1) mod N];
    Rad := Fillet[I];
    if Rad > 1.0E-12 then
    begin
      DX1 := Prev.X - Pts[I].X; DY1 := Prev.Y - Pts[I].Y;
      DX2 := Next.X - Pts[I].X; DY2 := Next.Y - Pts[I].Y;
      L1 := Sqrt(DX1 * DX1 + DY1 * DY1);
      L2 := Sqrt(DX2 * DX2 + DY2 * DY2);
      Entry[I] := P2(Pts[I].X + Rad * DX1 / L1, Pts[I].Y + Rad * DY1 / L1);
      Exit_[I] := P2(Pts[I].X + Rad * DX2 / L2, Pts[I].Y + Rad * DY2 / L2);
    end
    else
    begin
      Entry[I] := Pts[I];
      Exit_[I] := Pts[I];
    end;
  end;
  Cnt := 0;
  for I := 0 to N - 1 do
  begin
    // the fillet (if any) at corner I, then the straight run to corner I+1
    if Fillet[I] > 1.0E-12 then
    begin
      // for the 90 degree corners used here the arc centre is the corner moved
      // inward by the radius along both edges
      A := Entry[I];
      B := Exit_[I];
      C := P2(A.X + B.X - Pts[I].X, A.Y + B.Y - Pts[I].Y);
      Push(FilletSeg(A, B, C, Fillet[I]));
    end;
    A := Exit_[I];
    B := Entry[(I + 1) mod N];
    if (Abs(A.X - B.X) > 1.0E-12) or (Abs(A.Y - B.Y) > 1.0E-12) then
      Push(MakeLineSeg(A, B));
  end;
  Result := MakeChainProfile(Segs, AHole);
end;

function BuildPreset(const Id: string; const Values: array of Double;
  const LengthUnit: string; out S: TSketch; out Err: string): Boolean;
var
  Idx, I: Integer;
  Def: TPresetDef;
  V: array of Double;
  b, h, t, D, Dia, bf, tf, tw, r, w, Hh, B2, yi: Double;
  Pts: array of TPoint2D;
  Fil: array of Double;
  Outer, Inner: TSketchProfile;
  UnitName: string;

  procedure Fail(const Msg: string);
  begin
    Err := Msg;
    Result := False;
  end;

begin
  Result := False;
  Err := '';
  Idx := FindPreset(Id);
  UnitName := LengthUnit;
  if UnitName = '' then UnitName := 'mm';
  SketchInit(S, '', UnitName);
  if Idx < 0 then begin Fail('Unknown shape "' + Id + '".'); Exit; end;
  Def := Defs[Idx];
  if Length(Values) <> Length(Def.Params) then
  begin
    Fail('Wrong number of dimensions for ' + Def.Caption + '.');
    Exit;
  end;
  SetLength(V, Length(Values));
  for I := 0 to High(Values) do
  begin
    V[I] := Values[I];
    if not (V[I] > 0) and not ((Def.Params[I].Name = 'r') and (V[I] = 0)) then
    begin
      Fail(Def.Params[I].Caption + ' must be greater than zero.');
      Exit;
    end;
  end;
  S.Name := Def.Caption;

  if Id = 'rect' then
  begin
    b := V[0]; h := V[1];
    SkAddProfile(S, MakeRectProfile(-b / 2, -h / 2, b / 2, h / 2, False));
    S.Name := Format('Rectangle %.6gx%.6g', [b, h]);
  end
  else if Id = 'chs' then
  begin
    Dia := V[0]; t := V[1];
    if 2 * t >= Dia then begin Fail('The wall thickness must be less than half the diameter.'); Exit; end;
    SkAddProfile(S, MakeCircleProfile(0, 0, Dia / 2, False));
    SkAddProfile(S, MakeCircleProfile(0, 0, Dia / 2 - t, True));
    S.Name := Format('CHS %.6gx%.6g', [Dia, t]);
  end
  else if Id = 'rhs' then
  begin
    b := V[0]; h := V[1]; t := V[2];
    if (2 * t >= b) or (2 * t >= h) then begin Fail('The wall thickness must be less than half of each side.'); Exit; end;
    SkAddProfile(S, MakeRectProfile(-b / 2, -h / 2, b / 2, h / 2, False));
    SkAddProfile(S, MakeRectProfile(-b / 2 + t, -h / 2 + t, b / 2 - t, h / 2 - t, True));
    S.Name := Format('RHS %.6gx%.6gx%.6g', [b, h, t]);
  end
  else if Id = 'ibeam' then
  begin
    D := V[0]; bf := V[1]; tf := V[2]; tw := V[3]; r := V[4];
    if 2 * tf >= D then begin Fail('The flanges (2 tf) must be thinner than the depth.'); Exit; end;
    if tw >= bf then begin Fail('The web must be thinner than the flange width.'); Exit; end;
    if (r > (bf - tw) / 2) or (r > (D - 2 * tf) / 2) then
    begin Fail('The root radius is too large for this section.'); Exit; end;
    Hh := D / 2; B2 := bf / 2; w := tw / 2; yi := Hh - tf;
    SetLength(Pts, 12);
    SetLength(Fil, 12);
    Pts[0]  := P2(-B2, -Hh);  Fil[0]  := 0;
    Pts[1]  := P2(B2, -Hh);   Fil[1]  := 0;
    Pts[2]  := P2(B2, -yi);   Fil[2]  := 0;
    Pts[3]  := P2(w, -yi);    Fil[3]  := r;
    Pts[4]  := P2(w, yi);     Fil[4]  := r;
    Pts[5]  := P2(B2, yi);    Fil[5]  := 0;
    Pts[6]  := P2(B2, Hh);    Fil[6]  := 0;
    Pts[7]  := P2(-B2, Hh);   Fil[7]  := 0;
    Pts[8]  := P2(-B2, yi);   Fil[8]  := 0;
    Pts[9]  := P2(-w, yi);    Fil[9]  := r;
    Pts[10] := P2(-w, -yi);   Fil[10] := r;
    Pts[11] := P2(-B2, -yi);  Fil[11] := 0;
    SkAddProfile(S, RoundedChain(Pts, Fil, False));
    S.Name := Format('I-section %.6gx%.6g', [D, bf]);
  end
  else if Id = 'channel' then
  begin
    D := V[0]; bf := V[1]; tf := V[2]; tw := V[3]; r := V[4];
    if 2 * tf >= D then begin Fail('The flanges (2 tf) must be thinner than the depth.'); Exit; end;
    if tw >= bf then begin Fail('The web must be thinner than the flange width.'); Exit; end;
    if (r > bf - tw) or (r > (D - 2 * tf) / 2) then
    begin Fail('The root radius is too large for this section.'); Exit; end;
    SetLength(Pts, 8);
    SetLength(Fil, 8);
    Pts[0] := P2(0, 0);          Fil[0] := 0;
    Pts[1] := P2(bf, 0);         Fil[1] := 0;
    Pts[2] := P2(bf, tf);        Fil[2] := 0;
    Pts[3] := P2(tw, tf);        Fil[3] := r;
    Pts[4] := P2(tw, D - tf);    Fil[4] := r;
    Pts[5] := P2(bf, D - tf);    Fil[5] := 0;
    Pts[6] := P2(bf, D);         Fil[6] := 0;
    Pts[7] := P2(0, D);          Fil[7] := 0;
    SkAddProfile(S, RoundedChain(Pts, Fil, False));
    S.Name := Format('Channel %.6gx%.6g', [D, bf]);
  end
  else if Id = 'angle' then
  begin
    b := V[0]; D := V[1]; t := V[2]; r := V[3];
    if (t >= b) or (t >= D) then begin Fail('The thickness must be less than both legs.'); Exit; end;
    if (r > b - t) or (r > D - t) then begin Fail('The root radius is too large for this section.'); Exit; end;
    SetLength(Pts, 6);
    SetLength(Fil, 6);
    Pts[0] := P2(0, 0);   Fil[0] := 0;
    Pts[1] := P2(b, 0);   Fil[1] := 0;
    Pts[2] := P2(b, t);   Fil[2] := 0;
    Pts[3] := P2(t, t);   Fil[3] := r;
    Pts[4] := P2(t, D);   Fil[4] := 0;
    Pts[5] := P2(0, D);   Fil[5] := 0;
    SkAddProfile(S, RoundedChain(Pts, Fil, False));
    S.Name := Format('Angle %.6gx%.6gx%.6g', [D, b, t]);
  end
  else if Id = 'tee' then
  begin
    bf := V[0]; D := V[1]; tf := V[2]; tw := V[3];
    if tf >= D then begin Fail('The flange must be thinner than the overall depth.'); Exit; end;
    if tw >= bf then begin Fail('The web must be thinner than the flange width.'); Exit; end;
    B2 := bf / 2; w := tw / 2;
    SetLength(Pts, 8);
    Pts[0] := P2(-w, 0);
    Pts[1] := P2(w, 0);
    Pts[2] := P2(w, D - tf);
    Pts[3] := P2(B2, D - tf);
    Pts[4] := P2(B2, D);
    Pts[5] := P2(-B2, D);
    Pts[6] := P2(-B2, D - tf);
    Pts[7] := P2(-w, D - tf);
    SkAddProfile(S, MakePolygonProfile(Pts, False));
    S.Name := Format('Tee %.6gx%.6g', [D, bf]);
  end;
  Result := True;
end;

initialization
  InitDefs;
end.
