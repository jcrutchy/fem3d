unit fem_geometry_validate;

// Geometry checker for the FEM3DGEO diagnostic codes (spec section 14).
// Unlike fem3d's own fem_validate.pas (which only has hard errors),
// FEM3DGEO explicitly distinguishes errors from warnings: "A checker
// exits non-zero if errors exist. Warnings do not by themselves fail a
// check." (spec section 14) -- so every diagnostic here carries its own
// severity, and the caller (femgeocheck) only fails on the errors.
//
// Code -> meaning, per spec section 14 (each function below is named
// after the code it's responsible for):
//   GEO001 invalid reference        GEO006 non-manifold topology
//   GEO002 duplicate ID             GEO007 duplicate/coincident geometry
//   GEO003 dangling topology        GEO008 zero-length/degenerate geometry
//   GEO004 open/non-contiguous loop GEO009 unsupported geometry
//   GEO005 invalid orientation/normal  GEO010 unit/tolerance problem
//
// GEO009 (unsupported geometry) is mostly an ADAPTOR-side diagnostic
// (spec rule 6: "No importer may silently discard an unsupported
// source entity") rather than something a well-formed .fgeo file
// itself would trigger -- fem_geometry_io.LoadFGeo already rejects an
// unrecognized curve/surface kind as a hard parse error, so by the
// time a model reaches this unit its own entity kinds are already
// known-valid. CheckGeometry still exposes RecordUnsupported so an
// adaptor can log through the same diagnostic list/severity machinery
// as everything else, for one consistent reporting path.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_geometry_types;

type
  TGeoSeverity = (gsError, gsWarning);

  TGeoDiagnostic = record
    Code: string;      // 'GEO001'..'GEO010'
    Severity: TGeoSeverity;
    Msg: string;
  end;
  TGeoDiagnosticArray = array of TGeoDiagnostic;

  TGeoDiagnostics = record
    Items: TGeoDiagnosticArray;
  end;

procedure InitDiagnostics(out D: TGeoDiagnostics);
procedure AddDiagnostic(var D: TGeoDiagnostics; const Code: string; Severity: TGeoSeverity; const Msg: string);
function HasErrors(const D: TGeoDiagnostics): Boolean;
function ErrorCount(const D: TGeoDiagnostics): Integer;
function WarningCount(const D: TGeoDiagnostics): Integer;

// Adaptor-side helper: log a source entity that could not be converted
// (spec rule 6 -- never silently drop it). Always a warning, not an
// error, by itself: an importer that faithfully reports what it
// couldn't convert has done its job correctly even if the result is an
// incomplete geometry; whether that incompleteness matters is a
// downstream/engineering-judgement question, not this diagnostic's to
// decide.
procedure RecordUnsupported(var D: TGeoDiagnostics; const SourceEntityDescription: string);

// Runs every GEO001-GEO008/GEO010 check against Model (GEO009 is the
// adaptor-side RecordUnsupported above, not a Model-level check) and
// appends every diagnostic found to D. Geometric tolerance checks
// (GEO007 coincidence, GEO008 degeneracy) use Model.Header's own
// declared tolerances when present (spec section 4: TOLERANCE), else
// the DefaultCoincidenceTolerance/DefaultAngleTolerance constants below.
procedure CheckGeometry(const Model: TFEMGeometryModel; var D: TGeoDiagnostics);

const
  DefaultCoincidenceTolerance = 1.0E-6;
  DefaultAngleTolerance = 1.0E-8;

implementation

procedure InitDiagnostics(out D: TGeoDiagnostics);
begin
  SetLength(D.Items, 0);
end;

procedure AddDiagnostic(var D: TGeoDiagnostics; const Code: string; Severity: TGeoSeverity; const Msg: string);
begin
  SetLength(D.Items, Length(D.Items) + 1);
  D.Items[High(D.Items)].Code := Code;
  D.Items[High(D.Items)].Severity := Severity;
  D.Items[High(D.Items)].Msg := Msg;
end;

function HasErrors(const D: TGeoDiagnostics): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(D.Items) do
    if D.Items[i].Severity = gsError then begin Result := True; Exit; end;
end;

function ErrorCount(const D: TGeoDiagnostics): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(D.Items) do
    if D.Items[i].Severity = gsError then Inc(Result);
end;

function WarningCount(const D: TGeoDiagnostics): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(D.Items) do
    if D.Items[i].Severity = gsWarning then Inc(Result);
end;

procedure RecordUnsupported(var D: TGeoDiagnostics; const SourceEntityDescription: string);
begin
  AddDiagnostic(D, 'GEO009', gsWarning,
    Format('unsupported source geometry, not converted: %s', [SourceEntityDescription]));
end;

function VLen(const V: TGeoVec3): Double;
begin
  Result := Sqrt(V.X*V.X + V.Y*V.Y + V.Z*V.Z);
end;

function VDist(const A, B: TGeoVec3): Double;
begin
  Result := Sqrt(Sqr(A.X-B.X) + Sqr(A.Y-B.Y) + Sqr(A.Z-B.Z));
end;

function VSub(const A, B: TGeoVec3): TGeoVec3;
begin
  Result.X := A.X-B.X; Result.Y := A.Y-B.Y; Result.Z := A.Z-B.Z;
end;

function VCross(const A, B: TGeoVec3): TGeoVec3;
begin
  Result.X := A.Y*B.Z - A.Z*B.Y;
  Result.Y := A.Z*B.X - A.X*B.Z;
  Result.Z := A.X*B.Y - A.Y*B.X;
end;

procedure CheckGeometry(const Model: TFEMGeometryModel; var D: TGeoDiagnostics);
var
  coincTol, angTol: Double;
  i, j, k: Integer;

  // ---- id -> exists lookups, one small linear-scan helper per entity
  // type. Geometry-import-scale models (hundreds to a few thousand
  // entities per part, not fem3d's own mesh-scale thousands-of-nodes
  // models) -- a hash map would be premature here; see femgeo/docs/TODO.md
  // if that assumption stops holding.
  function VertexExists(Id: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Vertices) do if Model.Vertices[ii].Id = Id then begin Result := True; Exit; end;
  end;
  function VertexByIdx(Id: Integer; out Idx: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Vertices) do if Model.Vertices[ii].Id = Id then begin Idx := ii; Result := True; Exit; end;
  end;
  function CurveExists(Id: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Curves) do if Model.Curves[ii].Id = Id then begin Result := True; Exit; end;
  end;
  function EdgeByIdx(Id: Integer; out Idx: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Edges) do if Model.Edges[ii].Id = Id then begin Idx := ii; Result := True; Exit; end;
  end;
  function LoopExists(Id: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Loops) do if Model.Loops[ii].Id = Id then begin Result := True; Exit; end;
  end;
  function SurfaceExists(Id: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Surfaces) do if Model.Surfaces[ii].Id = Id then begin Result := True; Exit; end;
  end;
  function FaceExists(Id: Integer): Boolean;
  var ii: Integer;
  begin
    Result := False;
    for ii := 0 to High(Model.Faces) do if Model.Faces[ii].Id = Id then begin Result := True; Exit; end;
  end;

  // ---- GEO002: duplicate IDs within one entity class ----
  procedure CheckDuplicateIds(const Ids: array of Integer; const ClassName: string);
  var
    a, b: Integer;
  begin
    for a := 0 to High(Ids) do
      for b := a + 1 to High(Ids) do
        if Ids[a] = Ids[b] then
          AddDiagnostic(D, 'GEO002', gsError, Format('duplicate %s id %d', [ClassName, Ids[a]]));
  end;

  // GEO004 helper: walk a loop's edge uses in order; each use's
  // traversal END vertex (its edge's start or end, per BOTH the
  // edge's own stored Sense and this use's Sense within the loop --
  // two independent sign flips) must equal the NEXT use's traversal
  // START, and the last use's end must equal the first use's start
  // for the loop to close.
  procedure CheckLoopContinuity(LoopIdx: Integer);
  var
    travStart, travEnd: array of Integer;
    u, edgeIdx, storedStart, storedEnd: Integer;
    ok: Boolean;
  begin
    if Length(Model.Loops[LoopIdx].EdgeUses) = 0 then
    begin
      AddDiagnostic(D, 'GEO004', gsError, Format('LOOP %d has no edges', [Model.Loops[LoopIdx].Id]));
      Exit;
    end;

    SetLength(travStart, Length(Model.Loops[LoopIdx].EdgeUses));
    SetLength(travEnd, Length(Model.Loops[LoopIdx].EdgeUses));
    ok := True;
    for u := 0 to High(Model.Loops[LoopIdx].EdgeUses) do
    begin
      if not EdgeByIdx(Model.Loops[LoopIdx].EdgeUses[u].EdgeId, edgeIdx) then
      begin
        ok := False; // already reported as GEO001 above
        Break;
      end;
      storedStart := Model.Edges[edgeIdx].StartVertexId;
      storedEnd := Model.Edges[edgeIdx].EndVertexId;
      if Model.Loops[LoopIdx].EdgeUses[u].Sense >= 0 then
      begin
        travStart[u] := storedStart;
        travEnd[u] := storedEnd;
      end
      else
      begin
        travStart[u] := storedEnd;
        travEnd[u] := storedStart;
      end;
    end;
    if not ok then Exit;

    for u := 0 to High(travStart) - 1 do
      if travEnd[u] <> travStart[u + 1] then
        AddDiagnostic(D, 'GEO004', gsError,
          Format('LOOP %d is not contiguous: edge use %d ends at vertex %d but the next use starts at vertex %d',
            [Model.Loops[LoopIdx].Id, u + 1, travEnd[u], travStart[u + 1]]));
    if travEnd[High(travEnd)] <> travStart[0] then
      AddDiagnostic(D, 'GEO004', gsWarning,
        Format('LOOP %d does not close (ends at vertex %d, starts at vertex %d) -- ' +
          'only an error for a face boundary, which spec section 8 requires to be closed; ' +
          'an intentionally open loop elsewhere is not itself invalid',
          [Model.Loops[LoopIdx].Id, travEnd[High(travEnd)], travStart[0]]));
  end;

  // How many loops use a given edge -- shared by GEO003 (0 uses, an
  // orphan edge) and GEO006 (more than 2, non-manifold).
  function CountLoopUsesOfEdge(EdgeId: Integer): Integer;
  var
    lp, u: Integer;
  begin
    Result := 0;
    for lp := 0 to High(Model.Loops) do
      for u := 0 to High(Model.Loops[lp].EdgeUses) do
        if Model.Loops[lp].EdgeUses[u].EdgeId = EdgeId then Inc(Result);
  end;

var
  idsBuf: array of Integer;
begin
  if Model.Header.HasTolerance then
  begin
    coincTol := Model.Header.TolCoincidence;
    angTol := Model.Header.TolAngle;
  end
  else
  begin
    coincTol := DefaultCoincidenceTolerance;
    angTol := DefaultAngleTolerance;
  end;

  // GEO010: unit/tolerance problems -----------------------------------
  if not Model.Header.HasUnits then
    AddDiagnostic(D, 'GEO010', gsWarning, 'no UNITS record -- length unit is unspecified')
  else if (Model.Header.LengthUnit = '') or (Model.Header.LengthUnit = 'UNKNOWN') then
    AddDiagnostic(D, 'GEO010', gsWarning, 'UNITS length=UNKNOWN -- geometry values have no declared scale');
  if Model.Header.HasTolerance then
  begin
    if Model.Header.TolCoincidence <= 0 then
      AddDiagnostic(D, 'GEO010', gsError, Format('TOLERANCE coincidence=%g must be positive', [Model.Header.TolCoincidence]));
    if Model.Header.TolAngle <= 0 then
      AddDiagnostic(D, 'GEO010', gsError, Format('TOLERANCE angle=%g must be positive', [Model.Header.TolAngle]));
  end;

  // GEO002: duplicate IDs, one entity class at a time ------------------
  SetLength(idsBuf, Length(Model.Vertices));
  for i := 0 to High(Model.Vertices) do idsBuf[i] := Model.Vertices[i].Id;
  CheckDuplicateIds(idsBuf, 'VERTEX');
  SetLength(idsBuf, Length(Model.Curves));
  for i := 0 to High(Model.Curves) do idsBuf[i] := Model.Curves[i].Id;
  CheckDuplicateIds(idsBuf, 'CURVE');
  SetLength(idsBuf, Length(Model.Edges));
  for i := 0 to High(Model.Edges) do idsBuf[i] := Model.Edges[i].Id;
  CheckDuplicateIds(idsBuf, 'EDGE');
  SetLength(idsBuf, Length(Model.Loops));
  for i := 0 to High(Model.Loops) do idsBuf[i] := Model.Loops[i].Id;
  CheckDuplicateIds(idsBuf, 'LOOP');
  SetLength(idsBuf, Length(Model.Surfaces));
  for i := 0 to High(Model.Surfaces) do idsBuf[i] := Model.Surfaces[i].Id;
  CheckDuplicateIds(idsBuf, 'SURFACE');
  SetLength(idsBuf, Length(Model.Faces));
  for i := 0 to High(Model.Faces) do idsBuf[i] := Model.Faces[i].Id;
  CheckDuplicateIds(idsBuf, 'FACE');
  SetLength(idsBuf, Length(Model.Bodies));
  for i := 0 to High(Model.Bodies) do idsBuf[i] := Model.Bodies[i].Id;
  CheckDuplicateIds(idsBuf, 'BODY');

  // GEO001: invalid (dangling) references, plus GEO008 zero-length
  // edges, checked together per edge since both need the edge's own
  // resolved endpoints -----------------------------------------------
  for i := 0 to High(Model.Edges) do
  begin
    if not VertexExists(Model.Edges[i].StartVertexId) then
      AddDiagnostic(D, 'GEO001', gsError,
        Format('EDGE %d references nonexistent startVertex %d', [Model.Edges[i].Id, Model.Edges[i].StartVertexId]));
    if not VertexExists(Model.Edges[i].EndVertexId) then
      AddDiagnostic(D, 'GEO001', gsError,
        Format('EDGE %d references nonexistent endVertex %d', [Model.Edges[i].Id, Model.Edges[i].EndVertexId]));
    if not CurveExists(Model.Edges[i].CurveId) then
      AddDiagnostic(D, 'GEO001', gsError,
        Format('EDGE %d references nonexistent curve %d', [Model.Edges[i].Id, Model.Edges[i].CurveId]));
  end;

  for i := 0 to High(Model.Edges) do
  begin
    j := -1; k := -1;
    if VertexByIdx(Model.Edges[i].StartVertexId, j) and VertexByIdx(Model.Edges[i].EndVertexId, k) then
      if (j <> k) and (VDist(Model.Vertices[j].P, Model.Vertices[k].P) <= coincTol) then
        AddDiagnostic(D, 'GEO008', gsWarning,
          Format('EDGE %d has coincident start/end vertices (%d, %d) within tolerance -- degenerate edge',
            [Model.Edges[i].Id, Model.Edges[i].StartVertexId, Model.Edges[i].EndVertexId]));
  end;

  for i := 0 to High(Model.Loops) do
    for j := 0 to High(Model.Loops[i].EdgeUses) do
      if not EdgeByIdx(Model.Loops[i].EdgeUses[j].EdgeId, k) then
        AddDiagnostic(D, 'GEO001', gsError,
          Format('LOOP %d references nonexistent edge %d', [Model.Loops[i].Id, Model.Loops[i].EdgeUses[j].EdgeId]));

  for i := 0 to High(Model.Faces) do
  begin
    if not SurfaceExists(Model.Faces[i].SurfaceId) then
      AddDiagnostic(D, 'GEO001', gsError,
        Format('FACE %d references nonexistent surface %d', [Model.Faces[i].Id, Model.Faces[i].SurfaceId]));
    if not LoopExists(Model.Faces[i].OuterLoopId) then
      AddDiagnostic(D, 'GEO001', gsError,
        Format('FACE %d references nonexistent outer loop %d', [Model.Faces[i].Id, Model.Faces[i].OuterLoopId]));
    for j := 0 to High(Model.Faces[i].InnerLoopIds) do
      if not LoopExists(Model.Faces[i].InnerLoopIds[j]) then
        AddDiagnostic(D, 'GEO001', gsError,
          Format('FACE %d references nonexistent inner loop %d', [Model.Faces[i].Id, Model.Faces[i].InnerLoopIds[j]]));
  end;

  for i := 0 to High(Model.Bodies) do
    for j := 0 to High(Model.Bodies[i].FaceIds) do
      if not FaceExists(Model.Bodies[i].FaceIds[j]) then
        AddDiagnostic(D, 'GEO001', gsError,
          Format('BODY %d references nonexistent face %d', [Model.Bodies[i].Id, Model.Bodies[i].FaceIds[j]]));

  // GEO004: open/non-contiguous loop -----------------------------------
  for i := 0 to High(Model.Loops) do
    CheckLoopContinuity(i);

  // GEO005: invalid orientation/normal ---------------------------------
  for i := 0 to High(Model.Surfaces) do
    if VLen(Model.Surfaces[i].PlaneNormal) <= coincTol then
      AddDiagnostic(D, 'GEO005', gsError, Format('SURFACE %d has a zero (or near-zero) normal', [Model.Surfaces[i].Id]));

  for i := 0 to High(Model.Curves) do
    if Model.Curves[i].Kind = gcCircle then
      if VLen(Model.Curves[i].CircleNormal) <= coincTol then
        AddDiagnostic(D, 'GEO005', gsError, Format('CURVE %d (CIRCLE) has a zero (or near-zero) normal', [Model.Curves[i].Id]));

  // GEO008: degenerate geometry -----------------------------------------
  for i := 0 to High(Model.Curves) do
  begin
    case Model.Curves[i].Kind of
      gcLine:
        if VLen(Model.Curves[i].LineDirection) <= coincTol then
          AddDiagnostic(D, 'GEO008', gsError, Format('CURVE %d (LINE) has a zero-length direction', [Model.Curves[i].Id]));
      gcCircle:
        if Model.Curves[i].CircleRadius <= coincTol then
          AddDiagnostic(D, 'GEO008', gsError, Format('CURVE %d (CIRCLE) has a non-positive radius', [Model.Curves[i].Id]));
      gcArc3:
        begin
          if (VDist(Model.Curves[i].Arc3Start, Model.Curves[i].Arc3Mid) <= coincTol)
             or (VDist(Model.Curves[i].Arc3Mid, Model.Curves[i].Arc3End) <= coincTol)
             or (VDist(Model.Curves[i].Arc3Start, Model.Curves[i].Arc3End) <= coincTol) then
            AddDiagnostic(D, 'GEO008', gsError, Format('CURVE %d (ARC3) has two coincident defining points', [Model.Curves[i].Id]))
          else if VLen(VCross(VSub(Model.Curves[i].Arc3Mid, Model.Curves[i].Arc3Start),
                              VSub(Model.Curves[i].Arc3End, Model.Curves[i].Arc3Start))) <= coincTol then
            AddDiagnostic(D, 'GEO008', gsError, Format('CURVE %d (ARC3) has three collinear points -- degenerate arc', [Model.Curves[i].Id]));
        end;
    end;
  end;

  // GEO007: duplicate/coincident geometry (vertices only, for now --
  // see femgeo/docs/TODO.md for extending this to curves/surfaces) ----
  for i := 0 to High(Model.Vertices) do
    for j := i + 1 to High(Model.Vertices) do
      if VDist(Model.Vertices[i].P, Model.Vertices[j].P) <= coincTol then
        AddDiagnostic(D, 'GEO007', gsWarning,
          Format('VERTEX %d and VERTEX %d are coincident within tolerance',
            [Model.Vertices[i].Id, Model.Vertices[j].Id]));

  // GEO003: dangling topology (a vertex or edge that exists but is used
  // by nothing) ---------------------------------------------------------
  for i := 0 to High(Model.Vertices) do
  begin
    k := 0;
    for j := 0 to High(Model.Edges) do
      if (Model.Edges[j].StartVertexId = Model.Vertices[i].Id) or (Model.Edges[j].EndVertexId = Model.Vertices[i].Id) then
        Inc(k);
    if k = 0 then
      AddDiagnostic(D, 'GEO003', gsWarning, Format('VERTEX %d is not used by any edge', [Model.Vertices[i].Id]));
  end;
  for i := 0 to High(Model.Edges) do
    if CountLoopUsesOfEdge(Model.Edges[i].Id) = 0 then
      AddDiagnostic(D, 'GEO003', gsWarning, Format('EDGE %d is not used by any loop', [Model.Edges[i].Id]));

  // GEO006: non-manifold topology -- an edge used by more than 2 loops.
  // (Version 1.0 explicitly allows an open/non-watertight body, so an
  // edge used by exactly 0 or 1 loop is NOT flagged here -- that's
  // GEO003's job above, a different concern: "unused" vs "over-used".)
  for i := 0 to High(Model.Edges) do
  begin
    k := CountLoopUsesOfEdge(Model.Edges[i].Id);
    if k > 2 then
      AddDiagnostic(D, 'GEO006', gsWarning,
        Format('EDGE %d is used by %d loops (non-manifold -- a normal edge is shared by at most 2)',
          [Model.Edges[i].Id, k]));
  end;
end;

end.
