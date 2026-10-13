program run_sketch_test;
{$mode objfpc}{$H+}

// Tests the editable section sketch, snapping and parametric presets. Run from
// the repository root (test.bat does).

uses
  SysUtils, Classes, Math,
  fem_geometry_types, fem_geometry_io, fem_geometry_validate,
  fem_section_types, fem_section_calc, fem_section_io,
  fem_sketch, fem_snap2d, fem_sectionpresets;

var
  Passed, Failed: Integer;

procedure Check(const Name: string; Cond: Boolean; const Detail: string = '');
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('PASS  ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name, '  ', Detail);
  end;
end;

function Near(A, B: Double; Rel: Double = 1.0E-9): Boolean;
begin
  Result := Abs(A - B) <= Rel * Max(1.0, Max(Abs(A), Abs(B)));
end;

function P2(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

// sketch -> model -> validate -> faces -> properties, as the editor does
function Analyse(const S: TSketch; out Props: TSectionProperties; out Errs: Integer;
  out Warns: Integer): Boolean;
var
  Geo: TFEMGeometryModel;
  Faces: TSectionFaceArray;
  D: TGeoDiagnostics;
  Err: string;
  Unassigned: Integer;
begin
  SketchToGeo(S, Geo, Unassigned);
  InitDiagnostics(D);
  CheckGeometry(Geo, D);
  Errs := ErrorCount(D);
  Warns := WarningCount(D);
  FillChar(Props, SizeOf(Props), 0);
  Result := BuildSectionFaces(Geo, Faces, Err);
  if Result then
  begin
    Props.LengthUnit := S.LengthUnit;
    ComputeSectionProperties(Faces, Props, False);
  end;
end;

function GeoText(const S: TSketch): string;
var
  Geo: TFEMGeometryModel;
  MS: TMemoryStream;
  U: Integer;
begin
  SketchToGeo(S, Geo, U);
  MS := TMemoryStream.Create;
  try
    WriteFGeo(Geo, MS);
    SetLength(Result, MS.Size);
    MS.Position := 0;
    if MS.Size > 0 then MS.ReadBuffer(Result[1], MS.Size);
  finally
    MS.Free;
  end;
end;

// ---------------------------------------------------------------- sketch

procedure TestSketchBasics;
var
  S: TSketch;
  Pr: TSectionProperties;
  E, W: Integer;
  Geo: TFEMGeometryModel;
  U: Integer;
  R2: Double;
begin
  WriteLn('--- sketch -> model ---');
  SketchInit(S, 'Test', 'mm');
  SkAddProfile(S, MakeRectProfile(-50, -100, 50, 100, False));
  Check('a rectangle is a valid section', Analyse(S, Pr, E, W) and (E = 0) and (W = 0),
    Format('errors=%d warnings=%d', [E, W]));
  Check('rectangle area = b h', Near(Pr.Area, 100 * 200));
  Check('rectangle Ixx = b h^3 / 12', Near(Pr.Ixx, 100 * Power(200, 3) / 12));
  Check('rectangle Iyy = h b^3 / 12', Near(Pr.Iyy, 200 * Power(100, 3) / 12));
  Check('rectangle centroid at the origin', Near(Pr.CentroidX, 0) and Near(Pr.CentroidY, 0));

  // hole
  R2 := 20;
  SkAddProfile(S, MakeCircleProfile(10, 5, R2, True));
  Check('a rectangle with a circular hole is valid', Analyse(S, Pr, E, W) and (E = 0), IntToStr(E));
  Check('area = b h - pi r^2 (to the polygon approximation of the circle)',
    Abs(Pr.Area - (20000 - Pi * R2 * R2)) / 20000 < 5.0E-4, FloatToStr(Pr.Area));

  // the hole is assigned to the solid containing it
  SketchToGeo(S, Geo, U);
  Check('exactly one face with one inner loop',
    (Length(Geo.Faces) = 1) and (Length(Geo.Faces[0].InnerLoopIds) = 1) and (U = 0));

  // a hole outside every solid is reported and left out
  SkAddProfile(S, MakeCircleProfile(500, 500, 10, True));
  SketchToGeo(S, Geo, U);
  Check('a hole outside every solid is counted as unassigned', U = 1);
  Check('...and the rest of the section is still valid', Analyse(S, Pr, E, W) and (E = 0));

  // hole winding does not matter
  SketchInit(S, 'Winding', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 100, 100, False));
  SkAddProfile(S, MakePolygonProfile([P2(20, 20), P2(60, 20), P2(60, 60), P2(20, 60)], True));
  Analyse(S, Pr, E, W);
  R2 := Pr.Ixx;
  SketchInit(S, 'Winding', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 100, 100, False));
  SkAddProfile(S, MakePolygonProfile([P2(20, 60), P2(60, 60), P2(60, 20), P2(20, 20)], True));
  Check('a hole drawn clockwise or counter-clockwise gives the same section',
    Analyse(S, Pr, E, W) and (E = 0) and Near(Pr.Ixx, R2) and Near(Pr.Area, 10000 - 1600));

  // two separate solids
  SketchInit(S, 'Two', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 10, 10, False));
  SkAddProfile(S, MakeRectProfile(20, 0, 30, 10, False));
  SketchToGeo(S, Geo, U);
  Check('two separate solids make two faces', Length(Geo.Faces) = 2);
  Check('...and their areas add', Analyse(S, Pr, E, W) and (E = 0) and Near(Pr.Area, 200));

  // island inside a hole
  SketchInit(S, 'Nested', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 100, 100, False));
  SkAddProfile(S, MakeRectProfile(10, 10, 90, 90, True));
  SkAddProfile(S, MakeRectProfile(40, 40, 60, 60, False));
  SketchToGeo(S, Geo, U);
  Check('a solid inside a hole is its own face', (Length(Geo.Faces) = 2) and (U = 0));
  Check('...with area outer - hole + island', Analyse(S, Pr, E, W) and (E = 0) and
    Near(Pr.Area, 10000 - 6400 + 400), FloatToStr(Pr.Area));
  Check('default hole: a shape drawn in the solid material is a hole', DefaultHoleAt(S, 5, 5));
  Check('default hole: a shape drawn inside a hole is solid again (an island)', not DefaultHoleAt(S, 20, 20));
  Check('default hole: a shape drawn on the island is a hole again', DefaultHoleAt(S, 50, 50));
  Check('default hole: a shape drawn outside everything is solid', not DefaultHoleAt(S, 500, 500));

  // interior point of a concave shape (an L) must be inside it
  SketchInit(S, 'L', 'mm');
  SkAddProfile(S, MakePolygonProfile([P2(0, 0), P2(100, 0), P2(100, 10), P2(10, 10), P2(10, 100), P2(0, 100)], False));
  Check('interior point of a concave L is inside the L',
    ProfileContains(S.Profiles[0], ProfileInteriorPoint(S.Profiles[0]).X, ProfileInteriorPoint(S.Profiles[0]).Y));
  Check('interior point of a circle is its centre', Near(ProfileInteriorPoint(MakeCircleProfile(3, 4, 5, False)).X, 3));

  // empty sketch
  SketchInit(S, 'Empty', 'mm');
  Check('an empty sketch is not a section', not Analyse(S, Pr, E, W));
end;

procedure TestGeometryHelpers;
var
  S: TSketch;
  P: TSketchProfile;
  B: TSketchBox;
  Pts: TPoint2DArray;
  Segs: array[0..1] of TSketchSeg;
begin
  WriteLn('--- geometry helpers ---');
  P := MakeRectProfile(0, 0, 40, 20, False);
  B := ProfileBounds(P);
  Check('rectangle bounds', B.Valid and Near(B.XMin, 0) and Near(B.XMax, 40) and Near(B.YMax, 20));
  Check('rectangle area', Near(ProfileArea(P), 800));
  Check('point inside / outside a rectangle', ProfileContains(P, 20, 10) and not ProfileContains(P, 50, 10));
  Check('distance to the outline', Near(ProfileEdgeDistance(P, 20, 10), 10) and Near(ProfileEdgeDistance(P, 45, 10), 5));
  Check('rectangle has 4 vertices', ProfileVertexCount(P) = 4);
  P := MakeCircleProfile(5, 5, 10, False);
  Check('circle area (flattened)', Abs(ProfileArea(P) - Pi * 100) / (Pi * 100) < 1.0E-3);
  Check('distance to a circle outline', Near(ProfileEdgeDistance(P, 5, 5), 10) and Near(ProfileEdgeDistance(P, 25, 5), 10));

  // a half disc: a diameter plus a three-point arc through the top
  Segs[0] := MakeLineSeg(P2(-10, 0), P2(10, 0));
  Segs[1] := MakeArcSeg(P2(10, 0), P2(0, 10), P2(-10, 0));
  P := MakeChainProfile(Segs, False);
  Check('half disc from a line and an arc: area pi r^2 / 2 within 0.1%',
    Abs(ProfileArea(P) - Pi * 100 / 2) / (Pi * 50) < 1.0E-3, FloatToStr(ProfileArea(P)));
  ProfileFlatten(P, Pts);
  Check('the flattened arc stays on the circle', Abs(Sqrt(Sqr(Pts[3].X) + Sqr(Pts[3].Y)) - 10) < 1.0E-9);

  SketchInit(S, 'x', 'mm');
  Check('empty sketch has no bounds', not SketchBounds(S).Valid);
  SkAddProfile(S, MakeRectProfile(0, 0, 1, 1, False));
  SkAddProfile(S, MakeCircleProfile(10, 10, 2, False));
  B := SketchBounds(S);
  Check('sketch bounds cover every profile', B.Valid and Near(B.XMin, 0) and Near(B.XMax, 12) and Near(B.YMax, 12));
end;

procedure TestEdits;
var
  S: TSketch;
  B: TSketchBox;
begin
  WriteLn('--- edits ---');
  SketchInit(S, 'E', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 10, 10, False));
  SkAddProfile(S, MakeCircleProfile(5, 5, 2, True));
  SkMoveProfile(S, 0, 100, 50);
  B := ProfileBounds(S.Profiles[0]);
  Check('move a chain', Near(B.XMin, 100) and Near(B.XMax, 110) and Near(B.YMin, 50));
  SkMoveProfile(S, 1, 100, 50);
  Check('move a circle', Near(S.Profiles[1].Center.X, 105) and Near(S.Profiles[1].Center.Y, 55));
  SkMoveVertex(S, 0, 2, 120, 70);
  Check('move a vertex: both neighbouring segments follow',
    Near(S.Profiles[0].Segs[2].P0.X, 120) and Near(S.Profiles[0].Segs[1].P1.X, 120) and
    Near(S.Profiles[0].Segs[1].P1.Y, 70));
  Check('move a vertex: a straight segment keeps a midpoint on the line',
    Near(S.Profiles[0].Segs[1].PM.X, 0.5 * (110 + 120)));
  SkSetHole(S, 0, True);
  Check('set hole', S.Profiles[0].IsHole);
  SkSetCircleRadius(S, 1, 3.5);
  Check('set circle radius', Near(S.Profiles[1].Radius, 3.5));
  SkSetCircleRadius(S, 1, -1);
  Check('a non-positive radius is ignored', Near(S.Profiles[1].Radius, 3.5));
  SkDeleteProfile(S, 0);
  Check('delete a profile', (Length(S.Profiles) = 1) and (S.Profiles[0].Kind = pkCircle));
  SkDeleteProfile(S, 7);
  Check('deleting an index that does not exist is harmless', Length(S.Profiles) = 1);
end;

procedure TestHistory;
var
  D: TSketchDoc;
  Copy1: TSketch;
begin
  WriteLn('--- undo / redo ---');
  D := TSketchDoc.Create;
  try
    Check('a new document is clean with nothing to undo', (not D.Dirty) and (not D.CanUndo) and (not D.CanRedo));
    D.Checkpoint('Add rectangle');
    SkAddProfile(D.Sketch, MakeRectProfile(0, 0, 10, 10, False));
    Check('after an edit: dirty, can undo, name recorded', D.Dirty and D.CanUndo and (D.UndoName = 'Add rectangle'));
    D.Checkpoint('Move');
    SkMoveProfile(D.Sketch, 0, 100, 0);
    Check('moved', Near(ProfileBounds(D.Sketch.Profiles[0]).XMin, 100));
    D.Undo;
    Check('undo restores the position (nested arrays are not shared with the snapshot)',
      Near(ProfileBounds(D.Sketch.Profiles[0]).XMin, 0));
    Check('redo available after undo, with its name', D.CanRedo and (D.RedoName = 'Move'));
    D.Redo;
    Check('redo re-applies it', Near(ProfileBounds(D.Sketch.Profiles[0]).XMin, 100));
    D.Undo;
    D.Undo;
    Check('undo twice returns to the empty sketch', Length(D.Sketch.Profiles) = 0);
    Check('...and nothing is left to undo', not D.CanUndo);
    D.Redo;
    D.Checkpoint('Another edit');
    Check('a new edit clears the redo stack', not D.CanRedo);

    SketchCopy(D.Sketch, Copy1);
    SkMoveProfile(D.Sketch, 0, 5, 5);
    Check('a deep copy is independent of the original',
      Near(ProfileBounds(Copy1.Profiles[0]).XMin, ProfileBounds(D.Sketch.Profiles[0]).XMin - 5));

    D.NewSketch('Fresh', 'in');
    Check('NewSketch resets the document', (not D.Dirty) and (not D.CanUndo) and (D.Sketch.LengthUnit = 'in'));
  finally
    D.Free;
  end;
end;

// ---------------------------------------------------------------- files

function SectionNumbers(const Doc: TSketch; out Pr: TSectionProperties): Boolean;
var
  E, W: Integer;
begin
  Result := Analyse(Doc, Pr, E, W) and (E = 0);
end;

procedure TestImportExport(const Path: string);
var
  Geo: TFEMGeometryModel;
  S, S2: TSketch;
  Err: string;
  Faces: TSectionFaceArray;
  Orig, Pr: TSectionProperties;
  Text1, Text2: string;
  Geo2: TFEMGeometryModel;
  U, Arcs, I, K: Integer;
begin
  WriteLn('--- import / export: ', ExtractFileName(Path), ' ---');
  if not LoadFGeoFile(Path, Geo, Err) then
  begin
    Check('load ' + Path, False, Err);
    Exit;
  end;
  FillChar(Orig, SizeOf(Orig), 0);
  BuildSectionFaces(Geo, Faces, Err);
  Orig.LengthUnit := 'mm';
  ComputeSectionProperties(Faces, Orig, False);

  Check('import into a sketch', GeoToSketch(Geo, 'x', S, Err), Err);
  Check('the sketch has profiles', Length(S.Profiles) >= 1);
  Arcs := 0;
  for I := 0 to High(S.Profiles) do
    for K := 0 to High(S.Profiles[I].Segs) do
      if S.Profiles[I].Segs[K].Kind = skArc then Inc(Arcs);
  WriteLn('      (', Length(S.Profiles), ' profile(s), ', Arcs, ' arc segment(s))');

  // 1e-6, not 1e-12: the section builder splits an arc into Ceil(sweep / step)
  // pieces, which flips by one piece when the sweep is an exact multiple of the
  // step and the file's last digits differ from ours (a hand-written 16-digit
  // 2 pi, say). The effect is ~1e-8 on the area; files the editor itself saves
  // agree with the command-line tools exactly (see the next test group).
  Check('re-exported section is valid and has the original area and inertia',
    SectionNumbers(S, Pr) and (Abs(Pr.Area - Orig.Area) / Orig.Area < 1.0E-6) and
    (Abs(Pr.Ixx - Orig.Ixx) / Orig.Ixx < 1.0E-6) and (Abs(Pr.Iyy - Orig.Iyy) / Orig.Iyy < 1.0E-6),
    FloatToStr(Pr.Area) + ' vs ' + FloatToStr(Orig.Area));
  Check('the header (units) survives', S.LengthUnit = Geo.Header.LengthUnit);

  // export -> import -> export is a fixed point
  Text1 := GeoText(S);
  SketchToGeo(S, Geo2, U);
  Check('import of our own export works', GeoToSketch(Geo2, 'x', S2, Err), Err);
  Text2 := GeoText(S2);
  Check('export -> import -> export gives identical text', Text1 = Text2);
end;

procedure TestImportRefusals;
var
  Geo: TFEMGeometryModel;
  S: TSketch;
  Err: string;
begin
  WriteLn('--- import refusals ---');
  Geo := Default(TFEMGeometryModel);
  Check('a model with no faces is refused with a message', (not GeoToSketch(Geo, 'x', S, Err)) and (Err <> ''));
end;

// ---------------------------------------------------------------- snapping

// The model built from a sketch must be identical to the same model after being
// saved and loaded again, otherwise the editor's numbers could differ from what
// the command-line tools compute from the saved file.
procedure TestEditorMatchesCli;
var
  S: TSketch;
  G1, G2: TFEMGeometryModel;
  F1, F2: TSectionFaceArray;
  P1, P2p: TSectionProperties;
  Err, Path: string;
  U, I, K: Integer;
  Def: TPresetDef;
  Vals: array of Double;
  SamePoints, SameArea: Boolean;
begin
  WriteLn('--- the editor and the command-line tools see the same model ---');
  Path := IncludeTrailingPathDelimiter(GetTempDir) + 'sketch_roundtrip.fgeo';
  for I := 0 to PresetCount - 1 do
  begin
    Def := PresetDefAt(I);
    SetLength(Vals, Length(Def.Params));
    for K := 0 to High(Vals) do Vals[K] := Def.Params[K].DefaultValue;
    BuildPreset(Def.Id, Vals, 'mm', S, Err);
    SketchToGeo(S, G1, U);
    WriteFGeoFile(G1, Path);
    LoadFGeoFile(Path, G2, Err);
    BuildSectionFaces(G1, F1, Err);
    BuildSectionFaces(G2, F2, Err);
    FillChar(P1, SizeOf(P1), 0);
    FillChar(P2p, SizeOf(P2p), 0);
    ComputeSectionProperties(F1, P1, False);
    ComputeSectionProperties(F2, P2p, False);
    SamePoints := (Length(F1) = Length(F2)) and (Length(F1[0].OuterLoop.Points) = Length(F2[0].OuterLoop.Points));
    SameArea := Abs(P1.Area - P2p.Area) <= 1.0E-13 * P1.Area;
    Check(Def.Id + ': in-memory model and the saved-then-loaded model tessellate identically',
      SamePoints and SameArea, Format('area %.12g vs %.12g', [P1.Area, P2p.Area]));
  end;
  DeleteFile(Path);
end;

procedure TestSnap;
var
  S: TSketch;
  R: TSnapResult;
begin
  WriteLn('--- snapping ---');
  SketchInit(S, 'S', 'mm');
  SkAddProfile(S, MakeRectProfile(0, 0, 100, 50, False));
  SkAddProfile(S, MakeCircleProfile(200, 25, 10, False));

  R := SnapPoint(S, 2, 1, 5, 10, True, False);
  Check('snap to a vertex', (R.Kind = snVertex) and Near(R.X, 0) and Near(R.Y, 0));
  R := SnapPoint(S, 20, 20, 5, 10, True, False);
  Check('nothing within the tolerance: no snap, point unchanged',
    (R.Kind = snNone) and Near(R.X, 20) and Near(R.Y, 20));
  R := SnapPoint(S, 51, 2, 5, 10, True, False);
  Check('snap to a segment midpoint', (R.Kind = snMidpoint) and Near(R.X, 50) and Near(R.Y, 0));
  R := SnapPoint(S, 201, 24, 5, 10, True, False);
  Check('snap to a circle centre', (R.Kind = snCenter) and Near(R.X, 200) and Near(R.Y, 25));
  R := SnapPoint(S, 211, 26, 5, 10, True, False);
  Check('snap to a circle quadrant point', (R.Kind = snQuadrant) and Near(R.X, 210) and Near(R.Y, 25));
  R := SnapPoint(S, 53, 17, 1, 10, False, True);
  Check('grid snap rounds to the grid', (R.Kind = snGrid) and Near(R.X, 50) and Near(R.Y, 20));
  R := SnapPoint(S, 2, 1, 5, 10, True, True);
  Check('object snaps beat the grid', R.Kind = snVertex);
  R := SnapPoint(S, 2, 1, 5, 10, False, False);
  Check('snapping can be switched off', R.Kind = snNone);
  R := SnapPoint(S, 2, 1, 5, 10, True, False, 0);
  Check('an excluded profile is ignored (it is being dragged)', R.Kind = snNone);
  R := SnapPoint(S, 2, 1, 5, 10, True, False, 0, 0);
  Check('only the vertex being moved is ignored on its own profile', R.Kind = snNone);
  R := SnapPoint(S, 101, 1, 5, 10, True, False, 0, 0);
  Check('...other vertices of that profile still snap', (R.Kind = snVertex) and Near(R.X, 100) and Near(R.Y, 0));

  Check('ortho keeps the larger movement horizontal',
    (OrthoPoint(P2(10, 10), 50, 14).X = 50) and (OrthoPoint(P2(10, 10), 50, 14).Y = 10));
  Check('ortho keeps the larger movement vertical',
    (OrthoPoint(P2(10, 10), 12, 40).X = 10) and (OrthoPoint(P2(10, 10), 12, 40).Y = 40));
end;

// ---------------------------------------------------------------- presets

procedure TestPresets;
var
  I, K: Integer;
  Def: TPresetDef;
  Vals: array of Double;
  S, S2: TSketch;
  Err: string;
  Pr: TSectionProperties;
  E, W: Integer;
  b, h, t, d, bf, tf, tw, r, A, Xc, Yc, Ixx: Double;
begin
  WriteLn('--- presets ---');
  Check('there are presets', PresetCount >= 7);
  Check('lookup by id', (FindPreset('ibeam') >= 0) and (FindPreset('nonsense') = -1));

  // every preset builds with its defaults, validates cleanly and computes
  for I := 0 to PresetCount - 1 do
  begin
    Def := PresetDefAt(I);
    SetLength(Vals, Length(Def.Params));
    for K := 0 to High(Vals) do Vals[K] := Def.Params[K].DefaultValue;
    Check('default ' + Def.Id + ': builds', BuildPreset(Def.Id, Vals, 'mm', S, Err), Err);
    Check('default ' + Def.Id + ': valid geometry, no warnings, area > 0',
      Analyse(S, Pr, E, W) and (E = 0) and (W = 0) and (Pr.Area > 0),
      Format('errors=%d warnings=%d', [E, W]));
    BuildPreset(Def.Id, Vals, 'mm', S2, Err);
    Check('default ' + Def.Id + ': deterministic', GeoText(S) = GeoText(S2));
  end;

  // closed-form checks
  Check('rect', BuildPreset('rect', [100, 200], 'mm', S, Err) and Analyse(S, Pr, E, W) and
    Near(Pr.Area, 20000) and Near(Pr.Ixx, 100 * Power(200, 3) / 12));

  b := 100; h := 150; t := 6;
  BuildPreset('rhs', [b, h, t], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  Check('rhs area and Ixx (sharp corners, exact)',
    Near(Pr.Area, b * h - (b - 2 * t) * (h - 2 * t)) and
    Near(Pr.Ixx, (b * Power(h, 3) - (b - 2 * t) * Power(h - 2 * t, 3)) / 12));

  d := 168.3; t := 6.4;
  BuildPreset('chs', [d, t], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  Check('chs area within 0.1% of pi/4 (D^2 - d^2)',
    Abs(Pr.Area - Pi / 4 * (d * d - Sqr(d - 2 * t))) / Pr.Area < 1.0E-3, FloatToStr(Pr.Area));
  Check('chs Ixx within 0.2% of pi/64 (D^4 - d^4)',
    Abs(Pr.Ixx - Pi / 64 * (Power(d, 4) - Power(d - 2 * t, 4))) / Pr.Ixx < 2.0E-3);

  d := 203.2; bf := 133; tf := 7.8; tw := 5.8; r := 0;
  BuildPreset('ibeam', [d, bf, tf, tw, r], 'mm', S, Err);
  Check('ibeam with r = 0 builds', Err = '', Err);
  Analyse(S, Pr, E, W);
  Check('ibeam without fillets: area and Ixx exact',
    Near(Pr.Area, 2 * bf * tf + (d - 2 * tf) * tw) and
    Near(Pr.Ixx, (bf * Power(d, 3) - (bf - tw) * Power(d - 2 * tf, 3)) / 12));
  Check('ibeam: Iyy exact', Near(Pr.Iyy, (2 * tf * Power(bf, 3) + (d - 2 * tf) * Power(tw, 3)) / 12));

  r := 8.9;
  BuildPreset('ibeam', [d, bf, tf, tw, r], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  A := 2 * bf * tf + (d - 2 * tf) * tw + 4 * (1 - Pi / 4) * r * r;
  Check('ibeam with root fillets: area = web + flanges + 4 (1 - pi/4) r^2 (0.03%)',
    Abs(Pr.Area - A) / A < 3.0E-4, FloatToStr(Pr.Area) + ' vs ' + FloatToStr(A));
  Check('ibeam 200UB25.4 dimensions give the catalogue area 3230.9 mm^2 (0.1%)',
    Abs(Pr.Area - 3230.9) / 3230.9 < 1.0E-3);
  Check('ibeam is symmetric: centroid at the origin', (Abs(Pr.CentroidX) < 1.0E-9) and (Abs(Pr.CentroidY) < 1.0E-9));

  d := 200; bf := 75; tf := 12.5; tw := 6; r := 0;
  BuildPreset('channel', [d, bf, tf, tw, r], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  Check('channel without fillets: area exact',
    Near(Pr.Area, d * tw + 2 * (bf - tw) * tf));
  A := d * tw + 2 * (bf - tw) * tf;
  Xc := (d * tw * tw / 2 + 2 * (bf - tw) * tf * (tw + (bf - tw) / 2)) / A;
  Check('channel centroid x from the back', Near(Pr.CentroidX, Xc) and Near(Pr.CentroidY, d / 2));
  Check('channel Ixx about the centroid',
    Near(Pr.Ixx, (bf * Power(d, 3) - (bf - tw) * Power(d - 2 * tf, 3)) / 12));

  b := 100; d := 150; t := 12; r := 0;
  BuildPreset('angle', [b, d, t, r], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  A := t * (b + d - t);
  Xc := (b * t * b / 2 + (d - t) * t * t / 2) / A;
  Yc := (b * t * t / 2 + (d - t) * t * (t + (d - t) / 2)) / A;
  Check('angle without fillet: area and centroid exact',
    Near(Pr.Area, A) and Near(Pr.CentroidX, Xc) and Near(Pr.CentroidY, Yc));
  BuildPreset('angle', [b, d, t, 10], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  Check('angle with a root fillet: area + (1 - pi/4) r^2',
    Abs(Pr.Area - (A + (1 - Pi / 4) * 100)) / A < 3.0E-4);

  bf := 150; d := 150; tf := 12; tw := 8;
  BuildPreset('tee', [bf, d, tf, tw], 'mm', S, Err);
  Analyse(S, Pr, E, W);
  A := bf * tf + (d - tf) * tw;
  Yc := ((d - tf) * tw * (d - tf) / 2 + bf * tf * (d - tf / 2)) / A;
  Check('tee: area and centroid exact', Near(Pr.Area, A) and Near(Pr.CentroidY, Yc) and Near(Pr.CentroidX, 0));

  // refusals
  Check('negative dimension refused', not BuildPreset('rect', [-1, 10], 'mm', S, Err) and (Err <> ''));
  Check('zero dimension refused', not BuildPreset('rect', [0, 10], 'mm', S, Err));
  Check('wrong number of dimensions refused', not BuildPreset('rect', [10], 'mm', S, Err));
  Check('unknown shape refused', not BuildPreset('nope', [1], 'mm', S, Err));
  Check('chs wall thicker than the radius refused', not BuildPreset('chs', [50, 30], 'mm', S, Err));
  Check('ibeam flanges thicker than the depth refused', not BuildPreset('ibeam', [10, 50, 6, 3, 1], 'mm', S, Err));
  Check('ibeam with an oversized root radius refused', not BuildPreset('ibeam', [200, 100, 10, 6, 60], 'mm', S, Err));
  Check('channel web wider than the flange refused', not BuildPreset('channel', [200, 50, 10, 60, 0], 'mm', S, Err));
  Check('angle thicker than a leg refused', not BuildPreset('angle', [100, 150, 120, 0], 'mm', S, Err));
  Check('default scale for units', Near(DefaultScaleForUnit('mm'), 1) and Near(DefaultScaleForUnit('m'), 0.001) and
    Near(DefaultScaleForUnit('IN'), 1 / 25.4) and Near(DefaultScaleForUnit('furlong'), 1));
  Check('the unit is carried into the sketch', BuildPreset('rect', [1, 2], 'in', S, Err) and (S.LengthUnit = 'in'));
end;

begin
  Passed := 0;
  Failed := 0;
  TestSketchBasics;
  TestGeometryHelpers;
  TestEdits;
  TestHistory;
  TestImportExport('examples' + DirectorySeparator + 'prop' + DirectorySeparator + '200ub25_4.fgeo');
  TestImportExport('examples' + DirectorySeparator + 'prop' + DirectorySeparator + '150x100x12ua.fgeo');
  TestImportExport('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'good' + DirectorySeparator + '002_plate_with_hole.fgeo');
  TestImportExport('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'good' + DirectorySeparator + '001_rectangle.fgeo');
  TestImportRefusals;
  TestSnap;
  TestPresets;
  TestEditorMatchesCli;
  WriteLn;
  WriteLn(Passed, ' / ', Passed + Failed, ' checks passed');
  if Failed = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
