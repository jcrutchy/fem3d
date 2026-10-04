program run_section_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, fpjson, jsonparser,
  fem_section_types, fem_section_calc, fem_section_io;

var
  Fails, Checks: Integer;

procedure Check(const Name: string; Cond: Boolean; const Detail: string = '');
begin
  Inc(Checks);
  if Cond then
    WriteLn('PASS  ', Name)
  else
  begin
    Inc(Fails);
    WriteLn('FAIL  ', Name, '  -- ', Detail);
  end;
end;

function RelDiff(Actual, Expected: Double): Double;
begin
  if Abs(Expected) < 1.0E-12 then
    Result := Abs(Actual - Expected)
  else
    Result := Abs(Actual - Expected) / Abs(Expected);
end;

// ---- 1. Analytical Shapes Verification ----
procedure TestAnalyticalShapes;
var
  face: TSectionFace;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  b, h, r: Double;
  k: Integer;
begin
  // A. Solid Rectangle: b = 100, h = 200
  b := 100.0; h := 200.0;
  SetLength(face.OuterLoop.Points, 4);
  face.OuterLoop.Points[0] := Pt2D(0, 0);
  face.OuterLoop.Points[1] := Pt2D(b, 0);
  face.OuterLoop.Points[2] := Pt2D(b, h);
  face.OuterLoop.Points[3] := Pt2D(0, h);
  SetLength(face.Holes, 0);
  SetLength(faces, 1); faces[0] := face;

  ComputeSectionProperties(faces, props, True);
  Check('Analytical Rect: Area', RelDiff(props.Area, b * h) < 1.0E-12);
  Check('Analytical Rect: CentroidX', RelDiff(props.CentroidX, b / 2.0) < 1.0E-12);
  Check('Analytical Rect: CentroidY', RelDiff(props.CentroidY, h / 2.0) < 1.0E-12);
  Check('Analytical Rect: Ixx (b*h^3 / 12)', RelDiff(props.Ixx, b * h * h * h / 12.0) < 1.0E-12);
  Check('Analytical Rect: Iyy (h*b^3 / 12)', RelDiff(props.Iyy, h * b * b * b / 12.0) < 1.0E-12);
  Check('Analytical Rect: Sx (b*h^2 / 4)', RelDiff(props.Sx, b * h * h / 4.0) < 1.0E-6);
  Check('Analytical Rect: Sy (h*b^2 / 4)', RelDiff(props.Sy, h * b * b / 4.0) < 1.0E-6);

  // B. Hollow Box: outer 100x200, inner 80x180 (thickness 10)
  SetLength(face.Holes, 1);
  SetLength(face.Holes[0].Points, 4);
  face.Holes[0].IsHole := True;
  face.Holes[0].Points[0] := Pt2D(10, 10);
  face.Holes[0].Points[1] := Pt2D(90, 10);
  face.Holes[0].Points[2] := Pt2D(90, 190);
  face.Holes[0].Points[3] := Pt2D(10, 190);
  faces[0] := face;

  ComputeSectionProperties(faces, props, False);
  Check('Hollow Box: Net Area', RelDiff(props.Area, 100.0*200.0 - 80.0*180.0) < 1.0E-12);
  Check('Hollow Box: Ixx', RelDiff(props.Ixx, (100.0*200.0**3 - 80.0*180.0**3) / 12.0) < 1.0E-12);
end;

// ---- 2. Liberty Steel Database Verification ----
procedure TestCatalogueSections;
var
  face: TSectionFace;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  d, bf, tf, tw: Double;
begin
  // Example 1: 310 UB 40.4
  // Tabulated: d=304.0, bf=165.0, tf=10.2, tw=6.1, Ag=5210, Ix=86.4e6, Iy=7.65e6, rx=129, ry=38.3, Sx=633e3, Sy=142e3
  d := 304.0; bf := 165.0; tf := 10.2; tw := 6.1;
  SetLength(face.OuterLoop.Points, 12);
  // Symmetric I-section contour
  face.OuterLoop.Points[0]  := Pt2D(-bf/2, -d/2);
  face.OuterLoop.Points[1]  := Pt2D( bf/2, -d/2);
  face.OuterLoop.Points[2]  := Pt2D( bf/2, -d/2 + tf);
  face.OuterLoop.Points[3]  := Pt2D( tw/2, -d/2 + tf);
  face.OuterLoop.Points[4]  := Pt2D( tw/2,  d/2 - tf);
  face.OuterLoop.Points[5]  := Pt2D( bf/2,  d/2 - tf);
  face.OuterLoop.Points[6]  := Pt2D( bf/2,  d/2);
  face.OuterLoop.Points[7]  := Pt2D(-bf/2,  d/2);
  face.OuterLoop.Points[8]  := Pt2D(-bf/2,  d/2 - tf);
  face.OuterLoop.Points[9]  := Pt2D(-tw/2,  d/2 - tf);
  face.OuterLoop.Points[10] := Pt2D(-tw/2, -d/2 + tf);
  face.OuterLoop.Points[11] := Pt2D(-bf/2, -d/2 + tf);
  SetLength(face.Holes, 0);
  SetLength(faces, 1); faces[0] := face;

  ComputeSectionProperties(faces, props, False);
  // (Small difference is expected due to root fillets in rolled sections: ~2-3%)
  Check('310 UB 40.4: Area vs Catalogue (5210 mm2)', RelDiff(props.Area, 5210.0) < 0.035,
    Format('got %g', [props.Area]));
  Check('310 UB 40.4: Ix vs Catalogue (86.4e6 mm4)', RelDiff(props.Ixx, 86.4E6) < 0.035,
    Format('got %g', [props.Ixx]));
  Check('310 UB 40.4: Iy vs Catalogue (7.65e6 mm4)', RelDiff(props.Iyy, 7.65E6) < 0.035,
    Format('got %g', [props.Iyy]));
  Check('310 UB 40.4: rx vs Catalogue (129 mm)', RelDiff(props.rx, 129.0) < 0.015,
    Format('got %g', [props.rx]));
  Check('310 UB 40.4: ry vs Catalogue (38.3 mm)', RelDiff(props.ry, 38.3) < 0.015,
    Format('got %g', [props.ry]));
  Check('310 UB 40.4: Sx vs Catalogue (633e3 mm3)', RelDiff(props.Sx, 633.0E3) < 0.04,
    Format('got %g', [props.Sx]));
  Check('310 UB 40.4: Sy vs Catalogue (142e3 mm3)', RelDiff(props.Sy, 142.0E3) < 0.04,
    Format('got %g', [props.Sy]));
end;

// ---- 3. Negative / Borked / Extreme Cases ----
procedure TestBorkedCases;
var
  face: TSectionFace;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  gotEx: Boolean;
begin
  // A. Zero Area: Collinear points (a line)
  SetLength(face.OuterLoop.Points, 3);
  face.OuterLoop.Points[0] := Pt2D(0, 0);
  face.OuterLoop.Points[1] := Pt2D(10, 10);
  face.OuterLoop.Points[2] := Pt2D(20, 20);
  SetLength(face.Holes, 0);
  SetLength(faces, 1); faces[0] := face;

  gotEx := False;
  try
    ComputeSectionProperties(faces, props, False);
  except
    on E: Exception do gotEx := True;
  end;
  Check('Borked: Collinear zero area raises exception', gotEx);

  // B. Negative Net Area: Hole larger than outer boundary
  SetLength(face.OuterLoop.Points, 4);
  face.OuterLoop.Points[0] := Pt2D(0, 0);
  face.OuterLoop.Points[1] := Pt2D(10, 0);
  face.OuterLoop.Points[2] := Pt2D(10, 10);
  face.OuterLoop.Points[3] := Pt2D(0, 10); // Area = 100

  SetLength(face.Holes, 1);
  SetLength(face.Holes[0].Points, 4);
  face.Holes[0].IsHole := True;
  face.Holes[0].Points[0] := Pt2D(-5, -5);
  face.Holes[0].Points[1] := Pt2D(20, -5);
  face.Holes[0].Points[2] := Pt2D(20, 20);
  face.Holes[0].Points[3] := Pt2D(-5, 20); // Hole Area = 625 > 100
  faces[0] := face;

  gotEx := False;
  try
    ComputeSectionProperties(faces, props, False);
  except
    on E: Exception do gotEx := True;
  end;
  Check('Borked: Hole larger than outer boundary raises exception', gotEx);

  // C. Extreme aspect ratio ribbon: 5000 mm x 0.1 mm
  SetLength(face.OuterLoop.Points, 4);
  face.OuterLoop.Points[0] := Pt2D(0, 0);
  face.OuterLoop.Points[1] := Pt2D(5000.0, 0);
  face.OuterLoop.Points[2] := Pt2D(5000.0, 0.1);
  face.OuterLoop.Points[3] := Pt2D(0, 0.1);
  SetLength(face.Holes, 0);
  faces[0] := face;

  ComputeSectionProperties(faces, props, False);
  Check('Extreme: High aspect ratio (50000:1) Area', RelDiff(props.Area, 500.0) < 1.0E-10);
  Check('Extreme: High aspect ratio (50000:1) Iyy', RelDiff(props.Iyy, 0.1 * 5000.0**3 / 12.0) < 1.0E-10);
end;

begin
  Fails := 0; Checks := 0;
  WriteLn('=== 1. ANALYTICAL SHAPES ===');
  TestAnalyticalShapes;
  WriteLn;
  WriteLn('=== 2. CATALOGUE VALIDATION (310 UB 40.4) ===');
  TestCatalogueSections;
  WriteLn;
  WriteLn('=== 3. BORKED & EXTREME BOUNDARY CASES ===');
  TestBorkedCases;
  WriteLn;
  if Fails = 0 then
    WriteLn(Format('ALL %d CHECKS PASSED', [Checks]))
  else
  begin
    WriteLn(Format('%d OF %d CHECKS FAILED', [Fails, Checks]));
    Halt(1);
  end;
end.

