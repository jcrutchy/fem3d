program dxf2femgeo;

// Converts the ENTITIES section of an ASCII DXF file to FEM3DGEO 1.0.
// Supports LINE, CIRCLE, and ARC (the entities that actually matter
// for a fastener-hole panel: outline lines, hole circles, filleted-
// corner arcs) -- every other entity type (LWPOLYLINE, SPLINE, TEXT,
// INSERT/block references, DIMENSION, ...) is read past (its group
// codes consumed so the parser doesn't desynchronise) and logged as a
// GEO009 "unsupported geometry" diagnostic, never silently dropped
// (spec rule 6) -- see the WARNING lines this prints to stderr.
//
// Scope decision, worth being explicit about: this adaptor emits
// VERTEX/CURVE/EDGE records only -- a "wireframe soup" -- and does NOT
// attempt to reconstruct LOOP/SURFACE/FACE/BODY topology from it (e.g.
// noticing that 4 lines form a closed rectangle, or that a circle is a
// hole IN that rectangle rather than a free-floating entity). That
// reconstruction needs real geometric reasoning about which edges
// bound which region, which is a downstream tool's job in the
// streaming pipeline (spec section 16: "step2femgeo | femgeocheck |
// geomclean | automesh"), not this format-translation adaptor's -- see
// femgeo/docs/TODO.md.
//
// Coincident points across different DXF entities (e.g. two LINEs that
// share an endpoint) are welded to the SAME VERTEX record if they're
// within the model's coincidence tolerance -- without this, adjoining
// edges could never be assembled into a closed loop downstream, since
// they'd reference different (if numerically near-identical) vertices.
//
// Each DXF layer becomes a SET grouping the edges on it (spec section
// 12) -- real DXF drawings commonly put rivet holes on their own layer
// separate from the panel outline, and that grouping is exactly the
// kind of provenance worth carrying through rather than discarding.
//
// Usage: dxf2femgeo model.dxf > model.fgeo
//        dxf2femgeo -             (stdin -> stdout)

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, fem_geometry_types, fem_geometry_io, fem_geometry_validate;

const
  WeldTolerance = 1.0E-6;
  DegToRad = Pi / 180.0;

type
  TRawEntity = record
    EType: string;
    Layer: string;
    HasP1, HasP2, HasRadius, HasStartAngle, HasEndAngle: Boolean;
    P1, P2: TGeoVec3;
    Radius, StartAngle, EndAngle: Double;
  end;

var
  model: TFEMGeometryModel;
  diags: TGeoDiagnostics;
  nLine, nCircle, nArc, nUnsupported: Integer;
  DxfFS: TFormatSettings;
  DxfFSReady: Boolean = False;

// DXF always writes numbers with a '.' decimal point, whatever the machine's
// regional settings are. StrToFloatDef without explicit format settings uses the
// OS locale, so on a comma-decimal system "12.34" silently converted to 0 and the
// geometry came out as a cloud of zero-coordinate points with no error.
function DxfNum(const S: string): Double;
begin
  if not DxfFSReady then
  begin
    DxfFS := DefaultFormatSettings;
    DxfFS.DecimalSeparator := '.';
    DxfFS.ThousandSeparator := ',';
    DxfFSReady := True;
  end;
  Result := StrToFloatDef(Trim(S), 0, DxfFS);
end;

function AddOrWeldVertex(const P: TGeoVec3): Integer;
var
  i, n: Integer;
begin
  for i := 0 to High(model.Vertices) do
    if Sqrt(Sqr(model.Vertices[i].P.X-P.X) + Sqr(model.Vertices[i].P.Y-P.Y) + Sqr(model.Vertices[i].P.Z-P.Z)) <= WeldTolerance then
    begin
      Result := model.Vertices[i].Id;
      Exit;
    end;
  n := Length(model.Vertices);
  SetLength(model.Vertices, n + 1);
  model.Vertices[n].Id := n + 1;
  model.Vertices[n].P := P;
  Result := model.Vertices[n].Id;
end;

function NextCurveId: Integer;
begin
  Result := Length(model.Curves) + 1;
end;

function NextEdgeId: Integer;
begin
  Result := Length(model.Edges) + 1;
end;

procedure AddToLayerSet(const Layer: string; EdgeId: Integer);
var
  i, n, m: Integer;
  found: Boolean;
begin
  found := False;
  for i := 0 to High(model.Sets) do
    if model.Sets[i].Name = Layer then
    begin
      m := Length(model.Sets[i].EntityIds);
      SetLength(model.Sets[i].EntityIds, m + 1);
      model.Sets[i].EntityIds[m] := EdgeId;
      found := True;
      Break;
    end;
  if not found then
  begin
    n := Length(model.Sets);
    SetLength(model.Sets, n + 1);
    model.Sets[n].Id := n + 1;
    model.Sets[n].Name := Layer;
    model.Sets[n].EntityKind := geEdge;
    SetLength(model.Sets[n].EntityIds, 1);
    model.Sets[n].EntityIds[0] := EdgeId;
  end;
end;

procedure EmitLine(const E: TRawEntity);
var
  v1, v2, cId, eId: Integer;
  dir: TGeoVec3;
begin
  if (not E.HasP1) or (not E.HasP2) then
  begin
    RecordUnsupported(diags, Format('LINE on layer "%s" is missing an endpoint (group 10/20/30 or 11/21/31) -- skipped', [E.Layer]));
    Exit;
  end;
  v1 := AddOrWeldVertex(E.P1);
  v2 := AddOrWeldVertex(E.P2);
  dir.X := E.P2.X - E.P1.X; dir.Y := E.P2.Y - E.P1.Y; dir.Z := E.P2.Z - E.P1.Z;
  cId := NextCurveId;
  SetLength(model.Curves, cId);
  model.Curves[cId-1].Id := cId;
  model.Curves[cId-1].Kind := gcLine;
  model.Curves[cId-1].LineOrigin := E.P1;
  model.Curves[cId-1].LineDirection := dir;
  eId := NextEdgeId;
  SetLength(model.Edges, eId);
  model.Edges[eId-1].Id := eId;
  model.Edges[eId-1].StartVertexId := v1;
  model.Edges[eId-1].EndVertexId := v2;
  model.Edges[eId-1].CurveId := cId;
  model.Edges[eId-1].T0 := 0;
  model.Edges[eId-1].T1 := 1;
  model.Edges[eId-1].Sense := 1;
  AddToLayerSet(E.Layer, eId);
  Inc(nLine);
end;

procedure EmitCircle(const E: TRawEntity);
var
  v1, cId, eId: Integer;
  startPt, normal: TGeoVec3;
begin
  if (not E.HasP1) or (not E.HasRadius) then
  begin
    RecordUnsupported(diags, Format('CIRCLE on layer "%s" is missing center (10/20/30) or radius (40) -- skipped', [E.Layer]));
    Exit;
  end;
  startPt.X := E.P1.X + E.Radius; startPt.Y := E.P1.Y; startPt.Z := E.P1.Z;
  v1 := AddOrWeldVertex(startPt);
  normal := V3(0, 0, 1); // DXF CIRCLE lies in the entity's own XY plane (OCS); v1.0 assumes world XY -- see femgeo/docs/TODO.md re DXF OCS/extrusion-direction handling
  cId := NextCurveId;
  SetLength(model.Curves, cId);
  model.Curves[cId-1].Id := cId;
  model.Curves[cId-1].Kind := gcCircle;
  model.Curves[cId-1].CircleCenter := E.P1;
  model.Curves[cId-1].CircleNormal := normal;
  model.Curves[cId-1].CircleRadius := E.Radius;
  eId := NextEdgeId;
  SetLength(model.Edges, eId);
  model.Edges[eId-1].Id := eId;
  model.Edges[eId-1].StartVertexId := v1;
  model.Edges[eId-1].EndVertexId := v1;
  model.Edges[eId-1].CurveId := cId;
  model.Edges[eId-1].T0 := 0;
  model.Edges[eId-1].T1 := 2 * Pi;
  model.Edges[eId-1].Sense := 1;
  AddToLayerSet(E.Layer, eId);
  Inc(nCircle);
end;

procedure EmitArc(const E: TRawEntity);
var
  v1, v2, cId, eId: Integer;
  startPt, endPt, midPt: TGeoVec3;
  a0, a1, aMid, aSweep: Double;
begin
  if (not E.HasP1) or (not E.HasRadius) or (not E.HasStartAngle) or (not E.HasEndAngle) then
  begin
    RecordUnsupported(diags, Format('ARC on layer "%s" is missing center, radius, or start/end angle -- skipped', [E.Layer]));
    Exit;
  end;
  a0 := E.StartAngle * DegToRad;
  a1 := E.EndAngle * DegToRad;
  // DXF ARCs sweep counter-clockwise from start angle to end angle;
  // if end < start numerically the sweep wraps through 360 degrees.
  aSweep := a1 - a0;
  while aSweep <= 0 do aSweep := aSweep + 2*Pi;
  aMid := a0 + aSweep / 2;

  startPt.X := E.P1.X + E.Radius*Cos(a0); startPt.Y := E.P1.Y + E.Radius*Sin(a0); startPt.Z := E.P1.Z;
  endPt.X   := E.P1.X + E.Radius*Cos(a1); endPt.Y   := E.P1.Y + E.Radius*Sin(a1); endPt.Z   := E.P1.Z;
  midPt.X   := E.P1.X + E.Radius*Cos(aMid); midPt.Y := E.P1.Y + E.Radius*Sin(aMid); midPt.Z  := E.P1.Z;

  v1 := AddOrWeldVertex(startPt);
  v2 := AddOrWeldVertex(endPt);
  cId := NextCurveId;
  SetLength(model.Curves, cId);
  model.Curves[cId-1].Id := cId;
  model.Curves[cId-1].Kind := gcArc3;
  model.Curves[cId-1].Arc3Start := startPt;
  model.Curves[cId-1].Arc3Mid := midPt;
  model.Curves[cId-1].Arc3End := endPt;
  eId := NextEdgeId;
  SetLength(model.Edges, eId);
  model.Edges[eId-1].Id := eId;
  model.Edges[eId-1].StartVertexId := v1;
  model.Edges[eId-1].EndVertexId := v2;
  model.Edges[eId-1].CurveId := cId;
  model.Edges[eId-1].T0 := 0;
  model.Edges[eId-1].T1 := 1;
  model.Edges[eId-1].Sense := 1;
  AddToLayerSet(E.Layer, eId);
  Inc(nArc);
end;

procedure EmitEntity(const E: TRawEntity);
begin
  if E.EType = 'LINE' then EmitLine(E)
  else if E.EType = 'CIRCLE' then EmitCircle(E)
  else if E.EType = 'ARC' then EmitArc(E)
  else
  begin
    RecordUnsupported(diags, Format('%s on layer "%s" -- entity type not yet supported by dxf2femgeo', [E.EType, E.Layer]));
    Inc(nUnsupported);
  end;
end;

procedure ParseDxf(Lines: TStringList);
var
  i, code: Integer;
  codeStr, val: string;
  inEntities: Boolean;
  cur: TRawEntity;
  haveEntity: Boolean;

  procedure ResetCur;
  begin
    cur.EType := '';
    cur.Layer := '0';
    cur.HasP1 := False; cur.HasP2 := False; cur.HasRadius := False;
    cur.HasStartAngle := False; cur.HasEndAngle := False;
    cur.P1 := V3(0,0,0); cur.P2 := V3(0,0,0);
    cur.Radius := 0; cur.StartAngle := 0; cur.EndAngle := 0;
  end;

begin
  inEntities := False;
  haveEntity := False;
  ResetCur;
  i := 0;
  while i + 1 < Lines.Count do
  begin
    codeStr := Trim(Lines[i]);
    val := Trim(Lines[i+1]);
    Inc(i, 2);
    if not TryStrToInt(codeStr, code) then Continue; // malformed pair: skip forward defensively
    if code = 999 then Continue; // DXF comment

    if (code = 0) and (val = 'SECTION') then Continue;
    if (code = 2) and (not inEntities) and (val = 'ENTITIES') then
    begin
      inEntities := True;
      Continue;
    end;
    if not inEntities then Continue;
    if (code = 0) and (val = 'ENDSEC') then
    begin
      if haveEntity then EmitEntity(cur);
      Break;
    end;

    if code = 0 then
    begin
      if haveEntity then EmitEntity(cur);
      ResetCur;
      cur.EType := val;
      haveEntity := True;
      Continue;
    end;

    if not haveEntity then Continue;

    case code of
      8:  cur.Layer := val;
      10: begin cur.P1.X := DxfNum(val); cur.HasP1 := True; end;
      20: cur.P1.Y := DxfNum(val);
      30: cur.P1.Z := DxfNum(val);
      11: begin cur.P2.X := DxfNum(val); cur.HasP2 := True; end;
      21: cur.P2.Y := DxfNum(val);
      31: cur.P2.Z := DxfNum(val);
      40: begin cur.Radius := DxfNum(val); cur.HasRadius := True; end;
      50: begin cur.StartAngle := DxfNum(val); cur.HasStartAngle := True; end;
      51: begin cur.EndAngle := DxfNum(val); cur.HasEndAngle := True; end;
    end;
  end;
end;

var
  lines: TStringList;
  inFile: string;
  d: TGeoDiagnostic;
  outStream, inStream: TStream;

begin
  {$IFDEF FEM_TEST_COMMA_LOCALE}
  // Test hook: build with -dFEM_TEST_COMMA_LOCALE to emulate a comma-decimal
  // regional setting (German, Spanish, ... Windows). The output for any DXF
  // must be byte-identical to the normal build's.
  DefaultFormatSettings.DecimalSeparator := ',';
  DefaultFormatSettings.ThousandSeparator := '.';
  {$ENDIF}
  if ParamCount <> 1 then
  begin
    WriteLn(StdErr, 'Usage: dxf2femgeo <file.dxf | ->');
    Halt(2);
  end;
  inFile := ParamStr(1);

  SetLength(model.Vertices, 0); SetLength(model.Curves, 0); SetLength(model.Edges, 0);
  SetLength(model.Loops, 0); SetLength(model.Surfaces, 0); SetLength(model.Faces, 0);
  SetLength(model.Bodies, 0); SetLength(model.Sets, 0); SetLength(model.Meta, 0);
  model.Header.HasUnits := True;
  model.Header.LengthUnit := 'UNKNOWN'; // DXF's own $INSUNITS header var isn't read yet -- see TODO.md
  model.Header.ForceUnit := ''; model.Header.StressUnit := '';
  model.Header.HasCoordSys := True;
  model.Header.CoordSys := 'CARTESIAN';
  model.Header.HasTolerance := False;
  model.Header.HasSource := True;
  model.Header.SourceFormat := 'DXF';
  model.Header.SourceName := ExtractFileName(inFile);

  InitDiagnostics(diags);
  nLine := 0; nCircle := 0; nArc := 0; nUnsupported := 0;

  lines := TStringList.Create;
  try
    if inFile = '-' then
    begin
      inStream := THandleStream.Create(StdInputHandle);
      try
        lines.LoadFromStream(inStream);
      finally
        inStream.Free;
      end;
    end
    else
      lines.LoadFromFile(inFile);
    ParseDxf(lines);
  finally
    lines.Free;
  end;

  for d in diags.Items do
    WriteLn(StdErr, Format('dxf2femgeo: %s %s', [d.Code, d.Msg]));
  WriteLn(StdErr, Format('dxf2femgeo: %d LINE, %d CIRCLE, %d ARC converted; %d entity(ies) not supported',
    [nLine, nCircle, nArc, nUnsupported]));

  // Output is always stdout, whether input was a file or "-" -- spec
  // section 16's streaming contract ("file -> stdout", "stdin ->
  // stdout") means the adaptor never writes a file itself; the caller
  // redirects (dxf2femgeo model.dxf > model.fgeo) if a file is wanted.
  outStream := THandleStream.Create(StdOutputHandle);
  try
    WriteFGeo(model, outStream);
  finally
    outStream.Free;
  end;
end.
