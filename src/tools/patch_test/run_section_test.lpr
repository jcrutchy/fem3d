program run_section_test;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  fem_geometry_types, fem_geometry_io,
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

// ---- 4. Regression: hole placement, hole winding, caller data, torsion ----

// Hollow rectangle (outer w x h, wall t) with its lower-left corner at (x0,y0).
// HoleCW chooses the winding of the hole loop; the outer loop is always CCW.
function MakeHollowBox(x0, y0, w, h, t: Double; HoleCW: Boolean): TSectionFace;
begin
  SetLength(Result.OuterLoop.Points, 4);
  Result.OuterLoop.Points[0] := Pt2D(x0,     y0);
  Result.OuterLoop.Points[1] := Pt2D(x0 + w, y0);
  Result.OuterLoop.Points[2] := Pt2D(x0 + w, y0 + h);
  Result.OuterLoop.Points[3] := Pt2D(x0,     y0 + h);
  SetLength(Result.Holes, 1);
  SetLength(Result.Holes[0].Points, 4);
  Result.Holes[0].IsHole := True;
  if HoleCW then
  begin
    Result.Holes[0].Points[0] := Pt2D(x0 + t,     y0 + t);
    Result.Holes[0].Points[1] := Pt2D(x0 + t,     y0 + h - t);
    Result.Holes[0].Points[2] := Pt2D(x0 + w - t, y0 + h - t);
    Result.Holes[0].Points[3] := Pt2D(x0 + w - t, y0 + t);
  end
  else
  begin
    Result.Holes[0].Points[0] := Pt2D(x0 + t,     y0 + t);
    Result.Holes[0].Points[1] := Pt2D(x0 + w - t, y0 + t);
    Result.Holes[0].Points[2] := Pt2D(x0 + w - t, y0 + h - t);
    Result.Holes[0].Points[3] := Pt2D(x0 + t,     y0 + h - t);
  end;
end;

function MakeRect(w, h: Double): TSectionFace;
begin
  SetLength(Result.OuterLoop.Points, 4);
  Result.OuterLoop.Points[0] := Pt2D(0, 0);
  Result.OuterLoop.Points[1] := Pt2D(w, 0);
  Result.OuterLoop.Points[2] := Pt2D(w, h);
  Result.OuterLoop.Points[3] := Pt2D(0, h);
  SetLength(Result.Holes, 0);
end;

procedure TestHolePlacementAndWinding;
const
  // typed constants: untyped real constants fold at reduced precision
  W: Double = 100.0; H: Double = 200.0; T: Double = 10.0;
  PosX: array[0..2] of Double = (0.0, -300.0, -50.0);
  PosY: array[0..2] of Double = (0.0, -500.0, -100.0);
var
  p, wind: Integer;
  face: TSectionFace;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  tag, windName: string;
  ixxExp, iyyExp: Double;
begin
  // Exact values for a 100 x 200 box with 10 mm walls
  ixxExp := (W * H * H * H - (W - 2*T) * (H - 2*T) * (H - 2*T) * (H - 2*T)) / 12.0;
  iyyExp := (H * W * W * W - (H - 2*T) * (W - 2*T) * (W - 2*T) * (W - 2*T)) / 12.0;

  for p := 0 to 2 do
    for wind := 0 to 1 do
    begin
      face := MakeHollowBox(PosX[p], PosY[p], W, H, T, wind = 1);
      SetLength(faces, 1); faces[0] := face;
      FillChar(props, SizeOf(props), 0);
      ComputeSectionProperties(faces, props, False);
      if wind = 1 then windName := 'CW' else windName := 'CCW';
      tag := Format('Hollow box @(%g,%g) hole %s', [PosX[p], PosY[p], windName]);
      Check(tag + ': Area', RelDiff(props.Area, 5600.0) < 1.0E-12,
        Format('got %g', [props.Area]));
      Check(tag + ': CentroidX', Abs(props.CentroidX - (PosX[p] + W / 2.0)) < 1.0E-9,
        Format('got %g', [props.CentroidX]));
      Check(tag + ': CentroidY', Abs(props.CentroidY - (PosY[p] + H / 2.0)) < 1.0E-9,
        Format('got %g', [props.CentroidY]));
      Check(tag + ': Ixx', RelDiff(props.Ixx, ixxExp) < 1.0E-9,
        Format('got %g expected %g', [props.Ixx, ixxExp]));
      Check(tag + ': Iyy', RelDiff(props.Iyy, iyyExp) < 1.0E-9,
        Format('got %g expected %g', [props.Iyy, iyyExp]));
      // Plastic moduli: b*h^2/4 minus the void
      Check(tag + ': Sx', RelDiff(props.Sx, 352000.0) < 1.0E-6,
        Format('got %g', [props.Sx]));
      Check(tag + ': Sy', RelDiff(props.Sy, 212000.0) < 1.0E-6,
        Format('got %g', [props.Sy]));
    end;
end;

procedure TestCallerDataUntouched;
var
  face: TSectionFace;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  before: TPoint2DArray;
  k: Integer;
  same: Boolean;
begin
  // A clockwise hole is reversed internally; the caller's loop must not change.
  face := MakeHollowBox(0, 0, 100, 200, 10, True);
  SetLength(faces, 1); faces[0] := face;
  SetLength(before, Length(faces[0].Holes[0].Points));
  for k := 0 to High(before) do before[k] := faces[0].Holes[0].Points[k];
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, False);
  same := True;
  for k := 0 to High(before) do
    if (faces[0].Holes[0].Points[k].X <> before[k].X) or
       (faces[0].Holes[0].Points[k].Y <> before[k].Y) then same := False;
  Check('Caller hole loop is not modified', same);
end;

procedure TestPlasticModulusTranslationInvariance;
const
  OffX: array[0..3] of Double = (0.0, 500.0, 0.0, -300.0);
  OffY: array[0..3] of Double = (0.0, 300.0, -400.0, 0.0);
  D = 304.0; BF = 165.0; TF = 10.2; TW = 6.1;
var
  k: Integer;
  face: TSectionFace;
  faces: TSectionFaceArray;
  props, ref: TSectionProperties;
  ox, oy: Double;
begin
  for k := 0 to 3 do
  begin
    ox := OffX[k]; oy := OffY[k];
    SetLength(face.OuterLoop.Points, 12);
    face.OuterLoop.Points[0]  := Pt2D(ox - BF/2, oy - D/2);
    face.OuterLoop.Points[1]  := Pt2D(ox + BF/2, oy - D/2);
    face.OuterLoop.Points[2]  := Pt2D(ox + BF/2, oy - D/2 + TF);
    face.OuterLoop.Points[3]  := Pt2D(ox + TW/2, oy - D/2 + TF);
    face.OuterLoop.Points[4]  := Pt2D(ox + TW/2, oy + D/2 - TF);
    face.OuterLoop.Points[5]  := Pt2D(ox + BF/2, oy + D/2 - TF);
    face.OuterLoop.Points[6]  := Pt2D(ox + BF/2, oy + D/2);
    face.OuterLoop.Points[7]  := Pt2D(ox - BF/2, oy + D/2);
    face.OuterLoop.Points[8]  := Pt2D(ox - BF/2, oy + D/2 - TF);
    face.OuterLoop.Points[9]  := Pt2D(ox - TW/2, oy + D/2 - TF);
    face.OuterLoop.Points[10] := Pt2D(ox - TW/2, oy - D/2 + TF);
    face.OuterLoop.Points[11] := Pt2D(ox - BF/2, oy - D/2 + TF);
    SetLength(face.Holes, 0);
    SetLength(faces, 1); faces[0] := face;
    FillChar(props, SizeOf(props), 0);
    ComputeSectionProperties(faces, props, False);
    if k = 0 then
      ref := props
    else
    begin
      Check(Format('I-section offset (%g,%g): Ixx unchanged', [ox, oy]),
        RelDiff(props.Ixx, ref.Ixx) < 1.0E-9, Format('got %g', [props.Ixx]));
      Check(Format('I-section offset (%g,%g): Sx unchanged', [ox, oy]),
        RelDiff(props.Sx, ref.Sx) < 1.0E-9, Format('got %g', [props.Sx]));
      Check(Format('I-section offset (%g,%g): Sy unchanged', [ox, oy]),
        RelDiff(props.Sy, ref.Sy) < 1.0E-9, Format('got %g', [props.Sy]));
    end;
  end;
end;

procedure TestTorsionConstant;
var
  faces: TSectionFaceArray;
  props: TSectionProperties;
  k, n: Integer;
  r: Double;
begin
  SetLength(faces, 1);

  // Square a x a: J = 0.140577 a^4 (Saint-Venant series solution)
  faces[0] := MakeRect(100.0, 100.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Torsion J: square 100x100 vs 0.140577 a^4 (0.5%)',
    RelDiff(props.J, 0.140577 * 1.0E8) < 0.005, Format('got %g', [props.J]));

  // Rectangle 200 x 100 (b/t = 2): J = 0.2287 b t^3
  faces[0] := MakeRect(200.0, 100.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Torsion J: rectangle 200x100 vs 0.2287 b t^3 (0.5%)',
    RelDiff(props.J, 0.2287 * 200.0 * 1.0E6) < 0.005, Format('got %g', [props.J]));

  // Thin ribbon 200 x 4: J = (b t^3 / 3) (1 - 0.63 t/b)
  faces[0] := MakeRect(200.0, 4.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Torsion J: ribbon 200x4 vs (b t^3/3)(1-0.63 t/b) (1%)',
    RelDiff(props.J, 200.0 * 64.0 / 3.0 * (1.0 - 0.63 * 4.0 / 200.0)) < 0.01,
    Format('got %g', [props.J]));

  // Solid circle r = 50 as a 720-gon: J = pi r^4 / 2.  Curved boundary, so
  // this exercises the fractional boundary placement (a plain staircase
  // classification is about 1.8% high here; measured now: 0.01%).
  n := 720; r := 50.0;
  SetLength(faces[0].OuterLoop.Points, n);
  for k := 0 to n - 1 do
    faces[0].OuterLoop.Points[k] := Pt2D(r * Cos(2.0 * Pi * k / n), r * Sin(2.0 * Pi * k / n));
  SetLength(faces[0].Holes, 0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Torsion J: circle r=50 vs pi r^4/2 (0.5%)',
    RelDiff(props.J, Pi * r * r * r * r / 2.0) < 0.005, Format('got %g', [props.J]));
end;

// Circular tube Ro/Ri as an n-gon pair; HoleCW selects the hole winding.
function MakeTube(ro, ri: Double; n: Integer; HoleCW: Boolean; cx, cy: Double): TSectionFace;
var
  k: Integer;
  a: Double;
begin
  SetLength(Result.OuterLoop.Points, n);
  for k := 0 to n - 1 do
  begin
    a := 2.0 * Pi * k / n;
    Result.OuterLoop.Points[k] := Pt2D(cx + ro * Cos(a), cy + ro * Sin(a));
  end;
  SetLength(Result.Holes, 1);
  Result.Holes[0].IsHole := True;
  SetLength(Result.Holes[0].Points, n);
  for k := 0 to n - 1 do
  begin
    if HoleCW then a := -2.0 * Pi * k / n else a := 2.0 * Pi * k / n;
    Result.Holes[0].Points[k] := Pt2D(cx + ri * Cos(a), cy + ri * Sin(a));
  end;
end;

// Rectangle w x h split into two cells by a central web; all walls t thick.
function MakeTwoCell(w, h, t: Double): TSectionFace;
var
  hw: Double;
  procedure SetHole(idx: Integer; x0, y0, x1, y1: Double);
  begin
    Result.Holes[idx].IsHole := True;
    SetLength(Result.Holes[idx].Points, 4);
    Result.Holes[idx].Points[0] := Pt2D(x0, y0);
    Result.Holes[idx].Points[1] := Pt2D(x1, y0);
    Result.Holes[idx].Points[2] := Pt2D(x1, y1);
    Result.Holes[idx].Points[3] := Pt2D(x0, y1);
  end;
begin
  hw := w / 2.0;
  Result := MakeRect(w, h);
  SetLength(Result.Holes, 2);
  SetHole(0, t, t, hw - t / 2.0, h - t);
  SetHole(1, hw + t / 2.0, t, w - t, h - t);
end;

procedure TestClosedSectionTorsion;
var
  faces: TSectionFaceArray;
  props, ref: TSectionProperties;
  jExact, bredt: Double;
begin
  SetLength(faces, 1);

  // Circular tubes: J = pi/2 (Ro^4 - Ri^4), exact.  The first version of the
  // solver pinned Phi = 0 on hole boundaries and was ~100x too small.
  jExact := Pi / 2.0 * (Power(50.0, 4) - Power(40.0, 4));
  faces[0] := MakeTube(50.0, 40.0, 720, False, 0.0, 0.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: tube Ro50 Ri40, hole CCW (0.5%)',
    RelDiff(props.J, jExact) < 0.005, Format('got %g expected %g', [props.J, jExact]));
  ref := props;

  faces[0] := MakeTube(50.0, 40.0, 720, True, 0.0, 0.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: tube Ro50 Ri40, hole CW (same as CCW)',
    RelDiff(props.J, ref.J) < 1.0E-9, Format('got %g vs %g', [props.J, ref.J]));

  faces[0] := MakeTube(50.0, 40.0, 720, True, 300.0, -200.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: tube moved to (300,-200) (same J)',
    RelDiff(props.J, ref.J) < 1.0E-6, Format('got %g vs %g', [props.J, ref.J]));

  // Thin wall: 3 mm wall on a 50 mm radius is only a few grid cells thick
  jExact := Pi / 2.0 * (Power(50.0, 4) - Power(47.0, 4));
  faces[0] := MakeTube(50.0, 47.0, 720, False, 0.0, 0.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: thin tube Ro50 Ri47 (1%)',
    RelDiff(props.J, jExact) < 0.01, Format('got %g expected %g', [props.J, jExact]));

  // Hollow rectangle 100 x 200, t = 10.  Bredt (centre-line) is a lower bound
  // of 2.0886e7; the grid-converged answer is 2.165e7 (+3.6% from wall
  // thickness effects Bredt ignores).
  bredt := 4.0 * Sqr(90.0 * 190.0) / ((2.0 * 90.0 + 2.0 * 190.0) / 10.0);
  faces[0] := MakeHollowBox(0.0, 0.0, 100.0, 200.0, 10.0, False);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: hollow box 100x200x10 above Bredt lower bound',
    props.J > bredt, Format('got %g, Bredt %g', [props.J, bredt]));
  Check('Closed J: hollow box 100x200x10 vs converged 2.165e7 (1%)',
    RelDiff(props.J, 2.165E7) < 0.01, Format('got %g', [props.J]));
  ref := props;

  faces[0] := MakeHollowBox(-300.0, -500.0, 100.0, 200.0, 10.0, True);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: hollow box moved, hole CW (same J)',
    RelDiff(props.J, ref.J) < 1.0E-6, Format('got %g vs %g', [props.J, ref.J]));

  // Two cells (two independent lids).  For two identical cells the shared web
  // carries no net shear flow, so thin-wall theory gives J = 8 Ac^2 t / (2a+b)
  // with cell centre-line a = 95, b = 90.  Thick walls put the real value
  // about 4% above that.
  faces[0] := MakeTwoCell(200.0, 100.0, 10.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  bredt := 8.0 * Sqr(95.0 * 90.0) * 10.0 / (2.0 * 95.0 + 90.0);
  Check('Closed J: two-cell box above thin-wall value',
    props.J > bredt, Format('got %g, thin-wall %g', [props.J, bredt]));
  Check('Closed J: two-cell box within 6% of thin-wall value',
    RelDiff(props.J, bredt) < 0.06, Format('got %g, thin-wall %g', [props.J, bredt]));

  // A hole much smaller than a grid cell owns no grid node; it must be
  // ignored cleanly (no singular system, no NaN) and J stays that of the solid.
  faces[0] := MakeRect(100.0, 100.0);
  SetLength(faces[0].Holes, 1);
  faces[0].Holes[0].IsHole := True;
  SetLength(faces[0].Holes[0].Points, 4);
  faces[0].Holes[0].Points[0] := Pt2D(50.0, 50.0);
  faces[0].Holes[0].Points[1] := Pt2D(50.0, 50.2);
  faces[0].Holes[0].Points[2] := Pt2D(50.2, 50.2);
  faces[0].Holes[0].Points[3] := Pt2D(50.2, 50.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, True);
  Check('Closed J: sub-cell hole ignored, J finite and ~ solid square (1%)',
    (not IsNan(props.J)) and (RelDiff(props.J, 0.140577 * 1.0E8) < 0.01),
    Format('got %g', [props.J]));
end;

// ---- 7. Curved edges read from FEM3DGEO text ----

const
  GeoHdr = 'FEM3DGEO 1.0'#10'UNITS length=mm'#10'COORDSYS CARTESIAN'#10;

// Parse FEM3DGEO text and compute the section properties (J skipped).
function PropsFromGeo(const Txt: string; out Props: TSectionProperties; out Err: string): Boolean;
var
  ss: TStringStream;
  geo: TFEMGeometryModel;
  faces: TSectionFaceArray;
begin
  Result := False;
  FillChar(Props, SizeOf(Props), 0);
  ss := TStringStream.Create(Txt);
  try
    if not LoadFGeo(ss, geo, Err) then Exit;
  finally
    ss.Free;
  end;
  if not BuildSectionFaces(geo, faces, Err) then Exit;
  ComputeSectionProperties(faces, Props, False);
  Result := True;
end;

procedure CheckGeo(const Name, Txt: string; ExpArea, ExpCx, ExpCy, Tol: Double);
var
  p: TSectionProperties;
  err: string;
begin
  if not PropsFromGeo(Txt, p, err) then
  begin
    Check(Name, False, 'could not build section: ' + err);
    Exit;
  end;
  Check(Name + ': Area', RelDiff(p.Area, ExpArea) < Tol, Format('got %g expected %g', [p.Area, ExpArea]));
  Check(Name + ': CentroidX', Abs(p.CentroidX - ExpCx) < Tol * 100.0, Format('got %g expected %g', [p.CentroidX, ExpCx]));
  Check(Name + ': CentroidY', Abs(p.CentroidY - ExpCy) < Tol * 100.0, Format('got %g expected %g', [p.CentroidY, ExpCy]));
end;

procedure TestCurvedEdges;
const
  Tol = 2.0E-4;   // a 1-degree polygon leaves a full circle's area 0.005% low
var
  centroid: Double;
  plate: string;
begin
  centroid := 4.0 * 50.0 / (3.0 * Pi);

  // The edge covers only t = 0..0.5 of a half-circle ARC3 curve: a quarter
  // disc.  (Ignoring t0/t1 and drawing the whole curve gave +24% area.)
  CheckGeo('Arc edge using t0..t1 = 0..0.5 (quarter disc r=50)', GeoHdr +
    'VERTEX 1 0 0 0'#10'VERTEX 2 50 0 0'#10'VERTEX 3 0 50 0'#10 +
    'CURVE 1 LINE 0 0 0 50 0 0'#10'CURVE 2 ARC3 50 0 0 0 50 0 -50 0 0'#10'CURVE 3 LINE 0 50 0 0 -50 0'#10 +
    'EDGE 1 1 2 1 0 1 +1'#10'EDGE 2 2 3 2 0 0.5 +1'#10'EDGE 3 3 1 3 0 1 +1'#10 +
    'LOOP 1 EDGE 1 +1 EDGE 2 +1 EDGE 3 +1'#10'SURFACE 1 PLANE 0 0 0 0 0 1'#10'FACE 1 1 OUTER 1'#10,
    Pi * 2500.0 / 4.0, centroid, centroid, Tol);

  // Half disc whose arc EDGE runs against the curve direction (its start
  // vertex is the curve's end) and is used with sense -1 in the loop.
  CheckGeo('Arc edge stored against curve direction (half disc r=50)', GeoHdr +
    'VERTEX 1 -50 0 0'#10'VERTEX 2 50 0 0'#10 +
    'CURVE 1 LINE -50 0 0 100 0 0'#10'CURVE 2 ARC3 50 0 0 0 50 0 -50 0 0'#10 +
    'EDGE 1 1 2 1 0 1 +1'#10'EDGE 2 1 2 2 0 1 -1'#10 +
    'LOOP 1 EDGE 1 +1 EDGE 2 -1'#10'SURFACE 1 PLANE 0 0 0 0 0 1'#10'FACE 1 1 OUTER 1'#10,
    Pi * 2500.0 / 2.0, 0.0, centroid, Tol);

  // Same half disc, arc edge stored with the curve direction
  CheckGeo('Arc edge stored with curve direction (half disc r=50)', GeoHdr +
    'VERTEX 1 50 0 0'#10'VERTEX 2 -50 0 0'#10 +
    'CURVE 1 LINE 50 0 0 -100 0 0'#10'CURVE 2 ARC3 50 0 0 0 50 0 -50 0 0'#10 +
    'EDGE 1 1 2 2 0 1 +1'#10'EDGE 2 2 1 1 0 1 +1'#10 +
    'LOOP 1 EDGE 1 +1 EDGE 2 +1'#10'SURFACE 1 PLANE 0 0 0 0 0 1'#10'FACE 1 1 OUTER 1'#10,
    Pi * 2500.0 / 2.0, 0.0, centroid, Tol);

  // CIRCLE curves: a circular hole in a plate (this used to be rejected with
  // "Failed to convert inner loop"), for both circle normal directions.
  plate := GeoHdr +
    'VERTEX 1 0 0 0'#10'VERTEX 2 40 0 0'#10'VERTEX 3 40 20 0'#10'VERTEX 4 0 20 0'#10'VERTEX 5 24 10 0'#10 +
    'CURVE 1 LINE 0 0 0 40 0 0'#10'CURVE 2 LINE 40 0 0 0 20 0'#10'CURVE 3 LINE 40 20 0 -40 0 0'#10 +
    'CURVE 4 LINE 0 20 0 0 -20 0'#10'CURVE 5 CIRCLE 20 10 0 0 0 %s 4'#10 +
    'EDGE 1 1 2 1 0 1 +1'#10'EDGE 2 2 3 2 0 1 +1'#10'EDGE 3 3 4 3 0 1 +1'#10'EDGE 4 4 1 4 0 1 +1'#10 +
    'EDGE 5 5 5 5 0 6.283185307179586 +1'#10 +
    'LOOP 1 EDGE 1 +1 EDGE 2 +1 EDGE 3 +1 EDGE 4 +1'#10'LOOP 2 EDGE 5 +1'#10 +
    'SURFACE 1 PLANE 0 0 0 0 0 1'#10'FACE 1 1 OUTER 1 INNER 2'#10;
  CheckGeo('CIRCLE hole in plate, normal +Z', Format(plate, ['1']), 800.0 - Pi * 16.0, 20.0, 10.0, Tol);
  CheckGeo('CIRCLE hole in plate, normal -Z', Format(plate, ['-1']), 800.0 - Pi * 16.0, 20.0, 10.0, Tol);

  // A single self-closing CIRCLE edge as the OUTER loop
  CheckGeo('Solid CIRCLE outer loop (r=30 at 100,40)', GeoHdr +
    'VERTEX 1 130 40 0'#10'CURVE 1 CIRCLE 100 40 0 0 0 1 30'#10 +
    'EDGE 1 1 1 1 0 6.283185307179586 +1'#10'LOOP 1 EDGE 1 +1'#10 +
    'SURFACE 1 PLANE 0 0 0 0 0 1'#10'FACE 1 1 OUTER 1'#10,
    Pi * 900.0, 100.0, 40.0, Tol);
end;

// ---- 8. Values written to the .fem beam PROPERTIES line ----

// L-section 100 x 150 x 12, lower-left corner at (ox, oy)
function MakeAngle(ox, oy: Double): TSectionFace;
begin
  SetLength(Result.OuterLoop.Points, 6);
  Result.OuterLoop.Points[0] := Pt2D(ox,         oy);
  Result.OuterLoop.Points[1] := Pt2D(ox + 100.0, oy);
  Result.OuterLoop.Points[2] := Pt2D(ox + 100.0, oy + 12.0);
  Result.OuterLoop.Points[3] := Pt2D(ox + 12.0,  oy + 12.0);
  Result.OuterLoop.Points[4] := Pt2D(ox + 12.0,  oy + 150.0);
  Result.OuterLoop.Points[5] := Pt2D(ox,         oy + 150.0);
  SetLength(Result.Holes, 0);
end;

procedure TestBeamLineValues;
const
  OffX: array[0..1] of Double = (0.0, -50.0);
  OffY: array[0..1] of Double = (0.0, -75.0);
var
  faces: TSectionFaceArray;
  props: TSectionProperties;
  k, i: Integer;
  ixPr, iyPr, ixyPr, c, sn, du, dv, cyMax, czMax, rtMax: Double;
  pts: TPoint2DArray;
  tag: string;
begin
  SetLength(faces, 1);

  // Symmetric section (60 wide x 200 deep): nothing is rotated; Iy = Iyy,
  // Iz = Ixx.  Local y runs along the section's y (depth) direction, so Cy is
  // the half depth and Cz the half width.  Rt is the corner radius.
  faces[0] := MakeRect(60.0, 200.0);
  FillChar(props, SizeOf(props), 0);
  ComputeSectionProperties(faces, props, False);
  Check('Beam line, symmetric: no rotation', Abs(props.BeamThetaDeg) < 1.0E-9);
  Check('Beam line, symmetric: Iy = Iyy', RelDiff(props.BeamIy, props.Iyy) < 1.0E-12);
  Check('Beam line, symmetric: Iz = Ixx', RelDiff(props.BeamIz, props.Ixx) < 1.0E-12);
  Check('Beam line, symmetric: Cy = half depth', RelDiff(props.BeamCy, 100.0) < 1.0E-12,
    Format('got %g', [props.BeamCy]));
  Check('Beam line, symmetric: Cz = half width', RelDiff(props.BeamCz, 30.0) < 1.0E-12,
    Format('got %g', [props.BeamCz]));
  Check('Beam line, symmetric: Rt = corner radius',
    RelDiff(props.BeamRt, Sqrt(30.0 * 30.0 + 100.0 * 100.0)) < 1.0E-12,
    Format('got %g', [props.BeamRt]));

  // Unsymmetric angle section (Ixy <> 0), at two positions: the beam values
  // are principal-axes values and must not depend on where the section sits.
  for k := 0 to 1 do
  begin
    tag := Format('Beam line, angle at (%g,%g)', [OffX[k], OffY[k]]);
    faces[0] := MakeAngle(OffX[k], OffY[k]);
    FillChar(props, SizeOf(props), 0);
    ComputeSectionProperties(faces, props, False);

    Check(tag + ': Iy + Iz = Ixx + Iyy',
      RelDiff(props.BeamIy + props.BeamIz, props.Ixx + props.Iyy) < 1.0E-12);
    Check(tag + ': {Iy,Iz} = {I1,I2}',
      (RelDiff(Max(props.BeamIy, props.BeamIz), props.I1) < 1.0E-9) and
      (RelDiff(Min(props.BeamIy, props.BeamIz), props.I2) < 1.0E-9),
      Format('Iy=%g Iz=%g I1=%g I2=%g', [props.BeamIy, props.BeamIz, props.I1, props.I2]));
    Check(tag + ': axes within 45 deg of x/y', Abs(props.BeamThetaDeg) <= 45.0 + 1.0E-9,
      Format('theta=%g', [props.BeamThetaDeg]));

    // Independent check: transform the section's own second moments to the
    // reported direction; the product of inertia there must vanish and the
    // two principal values must match Iy / Iz.
    c := Cos(props.BeamThetaDeg * Pi / 180.0);
    sn := Sin(props.BeamThetaDeg * Pi / 180.0);
    ixPr := props.Ixx * c * c + props.Iyy * sn * sn - 2.0 * props.Ixy * sn * c;
    iyPr := props.Ixx * sn * sn + props.Iyy * c * c + 2.0 * props.Ixy * sn * c;
    ixyPr := (props.Ixx - props.Iyy) * sn * c + props.Ixy * (c * c - sn * sn);
    Check(tag + ': zero product of inertia about the beam axes',
      Abs(ixyPr) < 1.0E-9 * props.Ixx, Format('Ixy'' = %g', [ixyPr]));
    Check(tag + ': Iz = I about the z axis',
      RelDiff(props.BeamIz, ixPr) < 1.0E-9, Format('got %g expected %g', [props.BeamIz, ixPr]));
    Check(tag + ': Iy = I about the y axis',
      RelDiff(props.BeamIy, iyPr) < 1.0E-9, Format('got %g expected %g', [props.BeamIy, iyPr]));

    // Fibre distances by brute force over the outline, in the beam axes
    pts := faces[0].OuterLoop.Points;
    cyMax := 0.0; czMax := 0.0; rtMax := 0.0;
    for i := 0 to High(pts) do
    begin
      du := (pts[i].X - props.CentroidX) * c + (pts[i].Y - props.CentroidY) * sn;
      dv := -(pts[i].X - props.CentroidX) * sn + (pts[i].Y - props.CentroidY) * c;
      cyMax := Max(cyMax, Abs(dv));
      czMax := Max(czMax, Abs(du));
      rtMax := Max(rtMax, Sqrt(du * du + dv * dv));
    end;
    Check(tag + ': Cy is the largest |distance| on either side',
      RelDiff(props.BeamCy, cyMax) < 1.0E-9, Format('got %g expected %g', [props.BeamCy, cyMax]));
    Check(tag + ': Cz is the largest |distance| on either side',
      RelDiff(props.BeamCz, czMax) < 1.0E-9, Format('got %g expected %g', [props.BeamCz, czMax]));
    Check(tag + ': Rt is the largest distance from the centroid',
      RelDiff(props.BeamRt, rtMax) < 1.0E-9, Format('got %g expected %g', [props.BeamRt, rtMax]));
  end;
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
  WriteLn('=== 4. REGRESSION: HOLES (POSITION, WINDING), SX/SY INVARIANCE ===');
  TestHolePlacementAndWinding;
  TestCallerDataUntouched;
  TestPlasticModulusTranslationInvariance;
  WriteLn;
  WriteLn('=== 5. TORSION CONSTANT J (CONVERGED SOLVE) ===');
  TestTorsionConstant;
  WriteLn;
  WriteLn('=== 6. TORSION CONSTANT J: CLOSED (HOLLOW) SECTIONS ===');
  TestClosedSectionTorsion;
  WriteLn;
  WriteLn('=== 7. CURVED EDGES (ARC3 sub-range and direction, CIRCLE) ===');
  TestCurvedEdges;
  WriteLn;
  WriteLn('=== 8. BEAM PROPERTY LINE (PRINCIPAL AXES, FIBRE DISTANCES) ===');
  TestBeamLineValues;
  WriteLn;
  if Fails = 0 then
    WriteLn(Format('ALL %d CHECKS PASSED', [Checks]))
  else
  begin
    WriteLn(Format('%d OF %d CHECKS FAILED', [Fails, Checks]));
    Halt(1);
  end;
end.

