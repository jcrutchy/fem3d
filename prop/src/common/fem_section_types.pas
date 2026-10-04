unit fem_section_types;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TPoint2D = record
    X, Y: Double;
  end;
  TPoint2DArray = array of TPoint2D;

  // A 2D planar polygon loop: outer boundary (CCW) or internal hole (CW).
  TPolygonLoop = record
    IsHole: Boolean;
    Points: TPoint2DArray; // Closed sequence: Points[High] wraps to Points[0]
  end;
  TPolygonLoopArray = array of TPolygonLoop;

  // A section face composed of an outer boundary and zero or more inner holes
  TSectionFace = record
    OuterLoop: TPolygonLoop;
    Holes: TPolygonLoopArray;
  end;
  TSectionFaceArray = array of TSectionFace;

  TSectionProperties = record
    Name: string;
    LengthUnit: string;

    // Geometric
    Area: Double;
    Perimeter: Double;
    CentroidX, CentroidY: Double;
    GlobalCentroidX, GlobalCentroidY, GlobalCentroidZ: Double;
    BBoxXMin, BBoxXMax, BBoxYMin, BBoxYMax: Double;
    CxPos, CxNeg, CyPos, CyNeg: Double;

    // Second moments of area about centroidal axes
    Ixx, Iyy, Ixy: Double;
    I1, I2: Double;              // Principal moments (I1 >= I2)
    ThetaPrincipalRad: Double;   // Radians
    ThetaPrincipalDeg: Double;   // Degrees

    // Radii of gyration
    rx, ry, r1, r2: Double;

    // Section moduli
    ZxPos, ZxNeg, Zx: Double;
    ZyPos, ZyNeg, Zy: Double;
    Sx, Sy: Double;              // Plastic section moduli

    // Torsion
    J: Double;                   // St. Venant torsion constant
    Ip: Double;                  // Polar moment (Ixx + Iyy)
    JThinWalled: Double;         // Analytical thin-walled open estimate
  end;

function Pt2D(X, Y: Double): TPoint2D;

implementation

function Pt2D(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

end.

3. Computational Engine: femsection/src/common/fem_section_calc.pas

unit fem_section_calc;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_section_types;

type
  TLoopIntegrals = record
    Area: Double;
    Perimeter: Double;
    Qx, Qy: Double;
    Ixx0, Iyy0, Ixy0: Double;
  end;

// Calculates contour integrals along a single closed 2D loop using Green's Theorem
function ComputeLoopIntegrals(const Loop: TPolygonLoop): TLoopIntegrals;

// Clips a polygon with a half-plane (Ax + By + C >= 0) via Sutherland-Hodgman
function ClipPolygonHalfPlane(const Poly: TPoint2DArray; A, B, C: Double): TPoint2DArray;

// Area of an arbitrary 2D polygon (positive for CCW, negative for CW)
function PolygonArea2D(const P: TPoint2DArray): Double;

// Computes complete properties for one or more planar section faces
procedure ComputeSectionProperties(const Faces: TSectionFaceArray;
  var Props: TSectionProperties; SolveNumericalJ: Boolean = True);

implementation

function PtDist(const P1, P2: TPoint2D): Double; inline;
begin
  Result := Sqrt(Sqr(P2.X - P1.X) + Sqr(P2.Y - P1.Y));
end;

function PolygonArea2D(const P: TPoint2DArray): Double;
var
  i, n: Integer;
  a: Double;
begin
  n := Length(P);
  if n < 3 then Exit(0.0);
  a := 0.0;
  for i := 0 to n - 1 do
    a := a + (P[i].X * P[(i + 1) mod n].Y - P[(i + 1) mod n].X * P[i].Y);
  Result := 0.5 * a;
end;

function ComputeLoopIntegrals(const Loop: TPolygonLoop): TLoopIntegrals;
var
  i, j, n: Integer;
  x1, y1, x2, y2, cross: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  n := Length(Loop.Points);
  if n < 3 then Exit;

  for i := 0 to n - 1 do
  begin
    j := (i + 1) mod n;
    x1 := Loop.Points[i].X; y1 := Loop.Points[i].Y;
    x2 := Loop.Points[j].X; y2 := Loop.Points[j].Y;
    cross := x1 * y2 - x2 * y1;

    Result.Area := Result.Area + cross;
    Result.Perimeter := Result.Perimeter + PtDist(Loop.Points[i], Loop.Points[j]);
    Result.Qx := Result.Qx + cross * (y1 + y2);
    Result.Qy := Result.Qy + cross * (x1 + x2);
    Result.Ixx0 := Result.Ixx0 + cross * (y1 * y1 + y1 * y2 + y2 * y2);
    Result.Iyy0 := Result.Iyy0 + cross * (x1 * x1 + x1 * x2 + x2 * x2);
    Result.Ixy0 := Result.Ixy0 + cross * (x1 * y2 + 2.0 * x1 * y1 + 2.0 * x2 * y2 + x2 * y1);
  end;

  Result.Area := 0.5 * Result.Area;
  Result.Qx   := Result.Qx / 6.0;
  Result.Qy   := Result.Qy / 6.0;
  Result.Ixx0 := Result.Ixx0 / 12.0;
  Result.Iyy0 := Result.Iyy0 / 12.0;
  Result.Ixy0 := Result.Ixy0 / 24.0;
end;

function ClipPolygonHalfPlane(const Poly: TPoint2DArray; A, B, C: Double): TPoint2DArray;
var
  i, n: Integer;
  s, e: TPoint2D;
  sIn, eIn: Boolean;
  t: Double;

  function Inside(const Pt: TPoint2D): Boolean; inline;
  begin
    Result := (A * Pt.X + B * Pt.Y + C) >= -1.0E-12;
  end;

  function Intersection(const P1, P2: TPoint2D): TPoint2D;
  var d1, d2: Double;
  begin
    d1 := A * P1.X + B * P1.Y + C;
    d2 := A * P2.X + B * P2.Y + C;
    if Abs(d1 - d2) < 1.0E-14 then Exit(P1);
    t := d1 / (d1 - d2);
    Result.X := P1.X + t * (P2.X - P1.X);
    Result.Y := P1.Y + t * (P2.Y - P1.Y);
  end;

  procedure AddPt(const Pt: TPoint2D);
  var len: Integer;
  begin
    len := Length(Result);
    SetLength(Result, len + 1);
    Result[len] := Pt;
  end;

begin
  SetLength(Result, 0);
  n := Length(Poly);
  if n < 3 then Exit;

  s := Poly[n - 1];
  sIn := Inside(s);
  for i := 0 to n - 1 do
  begin
    e := Poly[i];
    eIn := Inside(e);
    if eIn then
    begin
      if not sIn then AddPt(Intersection(s, e));
      AddPt(e);
    end
    else if sIn then
      AddPt(Intersection(s, e));
    s := e;
    sIn := eIn;
  end;
end;

// Point-in-polygon test via winding number
function PointInPolygon(const Pt: TPoint2D; const Poly: TPoint2DArray): Boolean;
var
  i, n, wn: Integer;
  vt1, vt2: TPoint2D;
begin
  wn := 0;
  n := Length(Poly);
  for i := 0 to n - 1 do
  begin
    vt1 := Poly[i];
    vt2 := Poly[(i + 1) mod n];
    if vt1.Y <= Pt.Y then
    begin
      if (vt2.Y > Pt.Y) and ((vt2.X - vt1.X) * (Pt.Y - vt1.Y) - (Pt.X - vt1.X) * (vt2.Y - vt1.Y) > 0) then
        Inc(wn);
    end
    else
    begin
      if (vt2.Y <= Pt.Y) and ((vt2.X - vt1.X) * (Pt.Y - vt1.Y) - (Pt.X - vt1.X) * (vt2.Y - vt1.Y) < 0) then
        Dec(wn);
    end;
  end;
  Result := (wn <> 0);
end;

function PointInFace(const Pt: TPoint2D; const Face: TSectionFace): Boolean;
var
  k: Integer;
begin
  if not PointInPolygon(Pt, Face.OuterLoop.Points) then Exit(False);
  for k := 0 to High(Face.Holes) do
    if PointInPolygon(Pt, Face.Holes[k].Points) then Exit(False);
  Result := True;
end;

function PointInAnyFace(const Pt: TPoint2D; const Faces: TSectionFaceArray): Boolean;
var
  f: Integer;
begin
  for f := 0 to High(Faces) do
    if PointInFace(Pt, Faces[f]) then Exit(True);
  Result := False;
end;

// Numerically solves the Poisson PDE \nabla^2 \phi = -2 on an embedded grid for St. Venant torsion
function SolvePrandtlTorsion(const Faces: TSectionFaceArray;
  xMin, xMax, yMin, yMax: Double): Double;
const
  GridDim = 120;
var
  Nx, Ny, i, j, iter: Integer;
  hx, hy, hx2, hy2, denom: Double;
  InDomain: array of array of Boolean;
  Phi, R, P, Ap: array of array of Double;
  alpha, beta, rz, rzOld, pAp, sumPhi: Double;
  pt: TPoint2D;
begin
  Nx := GridDim;
  Ny := Round(GridDim * (yMax - yMin) / Max(xMax - xMin, 1.0E-6));
  if Ny < 20 then Ny := 20;
  if Ny > 250 then Ny := 250;

  hx := (xMax - xMin) / (Nx - 1);
  hy := (yMax - yMin) / (Ny - 1);
  hx2 := hx * hx;
  hy2 := hy * hy;
  denom := 2.0 / hx2 + 2.0 / hy2;

  SetLength(InDomain, Nx, Ny);
  SetLength(Phi, Nx, Ny);
  SetLength(R, Nx, Ny);
  SetLength(P, Nx, Ny);
  SetLength(Ap, Nx, Ny);

  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
    begin
      pt.X := xMin + i * hx;
      pt.Y := yMin + j * hy;
      InDomain[i, j] := PointInAnyFace(pt, Faces);
      Phi[i, j] := 0.0;
      if InDomain[i, j] and (i > 0) and (i < Nx - 1) and (j > 0) and (j < Ny - 1)
         and InDomain[i - 1, j] and InDomain[i + 1, j]
         and InDomain[i, j - 1] and InDomain[i, j + 1] then
        R[i, j] := 2.0
      else
        R[i, j] := 0.0;
      P[i, j] := R[i, j];
    end;

  rz := 0.0;
  for i := 1 to Nx - 2 do
    for j := 1 to Ny - 2 do
      rz := rz + R[i, j] * R[i, j];

  if rz <= 1.0E-20 then Exit(0.0);

  // Preconditioned Conjugate Gradient (Jacobi/Diagonal) solve
  for iter := 1 to 500 do
  begin
    pAp := 0.0;
    for i := 1 to Nx - 2 do
      for j := 1 to Ny - 2 do
        if InDomain[i, j] and InDomain[i - 1, j] and InDomain[i + 1, j]
           and InDomain[i, j - 1] and InDomain[i, j + 1] then
        begin
          Ap[i, j] := (2.0 * P[i, j] - P[i - 1, j] - P[i + 1, j]) / hx2 +
                      (2.0 * P[i, j] - P[i, j - 1] - P[i, j + 1]) / hy2;
          pAp := pAp + P[i, j] * Ap[i, j];
        end
        else
          Ap[i, j] := 0.0;

    if Abs(pAp) < 1.0E-30 then Break;
    alpha := rz / pAp;

    rzOld := rz;
    rz := 0.0;
    for i := 1 to Nx - 2 do
      for j := 1 to Ny - 2 do
        if InDomain[i, j] then
        begin
          Phi[i, j] := Phi[i, j] + alpha * P[i, j];
          R[i, j] := R[i, j] - alpha * Ap[i, j];
          rz := rz + R[i, j] * R[i, j];
        end;

    if Sqrt(rz) < 1.0E-6 then Break;
    beta := rz / rzOld;
    for i := 1 to Nx - 2 do
      for j := 1 to Ny - 2 do
        P[i, j] := R[i, j] + beta * P[i, j];
  end;

  sumPhi := 0.0;
  for i := 1 to Nx - 2 do
    for j := 1 to Ny - 2 do
      if InDomain[i, j] then
        sumPhi := sumPhi + Phi[i, j];

  Result := 2.0 * sumPhi * hx * hy;
end;

procedure ComputeSectionProperties(const Faces: TSectionFaceArray;
  var Props: TSectionProperties; SolveNumericalJ: Boolean);
var
  f, h, i, iter: Integer;
  poly: TPoint2DArray;
  outerLi, holeLi: TLoopIntegrals;
  netQx, netQy, netIxx0, netIyy0, netIxy0: Double;
  diff, R, Iavg, twoTheta: Double;
  yLo, yHi, yMid, areaAboveTarget, areaAbove, pnaY: Double;
  xLo, xHi, xMid, areaRightTarget, areaRight, pnaX: Double;
  clipped: TPoint2DArray;
  dummyLoop: TPolygonLoop;
  subLi: TLoopIntegrals;
begin
  if Length(Faces) = 0 then
    raise Exception.Create('Section contains no faces');

  Props.Area := 0.0;
  Props.Perimeter := 0.0;
  netQx := 0.0; netQy := 0.0;
  netIxx0 := 0.0; netIyy0 := 0.0; netIxy0 := 0.0;

  Props.BBoxXMin :=  1.0E300; Props.BBoxXMax := -1.0E300;
  Props.BBoxYMin :=  1.0E300; Props.BBoxYMax := -1.0E300;

  // 1. Accumulate Area, Perimeter, Q, I_origin across all faces and holes
  for f := 0 to High(Faces) do
  begin
    poly := Faces[f].OuterLoop.Points;
    if Length(poly) < 3 then
      raise Exception.CreateFmt('Face %d outer loop has fewer than 3 vertices', [f + 1]);

    outerLi := ComputeLoopIntegrals(Faces[f].OuterLoop);
    if outerLi.Area <= 0.0 then
      raise Exception.CreateFmt('Face %d outer loop has non-positive area (%g) -- verify CCW vertex ordering',
        [f + 1, outerLi.Area]);

    Props.Area := Props.Area + outerLi.Area;
    Props.Perimeter := Props.Perimeter + outerLi.Perimeter;
    netQx := netQx + outerLi.Qx;
    netQy := netQy + outerLi.Qy;
    netIxx0 := netIxx0 + outerLi.Ixx0;
    netIyy0 := netIyy0 + outerLi.Iyy0;
    netIxy0 := netIxy0 + outerLi.Ixy0;

    for i := 0 to High(poly) do
    begin
      if poly[i].X < Props.BBoxXMin then Props.BBoxXMin := poly[i].X;
      if poly[i].X > Props.BBoxXMax then Props.BBoxXMax := poly[i].X;
      if poly[i].Y < Props.BBoxYMin then Props.BBoxYMin := poly[i].Y;
      if poly[i].Y > Props.BBoxYMax then Props.BBoxYMax := poly[i].Y;
    end;

    for h := 0 to High(Faces[f].Holes) do
    begin
      holeLi := ComputeLoopIntegrals(Faces[f].Holes[h]);
      holeLi.Area := Abs(holeLi.Area); // subtract magnitude
      Props.Area := Props.Area - holeLi.Area;
      Props.Perimeter := Props.Perimeter + holeLi.Perimeter;
      netQx := netQx - Abs(holeLi.Qx);
      netQy := netQy - Abs(holeLi.Qy);
      netIxx0 := netIxx0 - Abs(holeLi.Ixx0);
      netIyy0 := netIyy0 - Abs(holeLi.Iyy0);
      netIxy0 := netIxy0 - Abs(holeLi.Ixy0);
    end;
  end;

  if Props.Area <= 1.0E-14 then
    raise Exception.CreateFmt('Total section area is degenerate or negative: %g', [Props.Area]);

  // 2. Centroid & parallel axis transfer
  Props.CentroidX := netQy / Props.Area;
  Props.CentroidY := netQx / Props.Area;

  Props.Ixx := netIxx0 - Props.Area * Sqr(Props.CentroidY);
  Props.Iyy := netIyy0 - Props.Area * Sqr(Props.CentroidX);
  Props.Ixy := netIxy0 - Props.Area * Props.CentroidX * Props.CentroidY;

  // Clean numerical zero noise on symmetric cross-sections
  if Abs(Props.Ixy) < 1.0E-11 * Max(Props.Ixx, Props.Iyy) then
    Props.Ixy := 0.0;

  // 3. Principal moments & angle
  diff := Props.Ixx - Props.Iyy;
  R := Sqrt(0.25 * diff * diff + Props.Ixy * Props.Ixy);
  Iavg := 0.5 * (Props.Ixx + Props.Iyy);
  Props.I1 := Iavg + R;
  Props.I2 := Iavg - R;

  if Abs(Props.Ixy) < 1.0E-14 then
  begin
    if Props.Ixx >= Props.Iyy then
      Props.ThetaPrincipalRad := 0.0
    else
      Props.ThetaPrincipalRad := 0.5 * Pi;
  end
  else
  begin
    twoTheta := ArcTan2(-2.0 * Props.Ixy, diff);
    Props.ThetaPrincipalRad := 0.5 * twoTheta;
  end;
  Props.ThetaPrincipalDeg := Props.ThetaPrincipalRad * 180.0 / Pi;

  // 4. Radii of gyration
  Props.rx := Sqrt(Props.Ixx / Props.Area);
  Props.ry := Sqrt(Props.Iyy / Props.Area);
  Props.r1 := Sqrt(Props.I1 / Props.Area);
  Props.r2 := Sqrt(Props.I2 / Props.Area);

  // 5. Extreme fibre distances & elastic moduli
  Props.CxPos := Props.BBoxXMax - Props.CentroidX;
  Props.CxNeg := Props.CentroidX - Props.BBoxXMin;
  Props.CyPos := Props.BBoxYMax - Props.CentroidY;
  Props.CyNeg := Props.CentroidY - Props.BBoxYMin;

  if Props.CyPos > 1.0E-14 then Props.ZxPos := Props.Ixx / Props.CyPos else Props.ZxPos := 0.0;
  if Props.CyNeg > 1.0E-14 then Props.ZxNeg := Props.Ixx / Props.CyNeg else Props.ZxNeg := 0.0;
  Props.Zx := Min(Props.ZxPos, Props.ZxNeg);

  if Props.CxPos > 1.0E-14 then Props.ZyPos := Props.Iyy / Props.CxPos else Props.ZyPos := 0.0;
  if Props.CxNeg > 1.0E-14 then Props.ZyNeg := Props.Iyy / Props.CxNeg else Props.ZyNeg := 0.0;
  Props.Zy := Min(Props.ZyPos, Props.ZyNeg);

  // 6. Plastic section moduli (Sx, Sy) via bisection PNA solve
  areaAboveTarget := 0.5 * Props.Area;
  yLo := Props.BBoxYMin;
  yHi := Props.BBoxYMax;
  for iter := 1 to 60 do
  begin
    yMid := 0.5 * (yLo + yHi);
    areaAbove := 0.0;
    for f := 0 to High(Faces) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 0.0, 1.0, -yMid);
      areaAbove := areaAbove + Abs(PolygonArea2D(clipped));
      for h := 0 to High(Faces[f].Holes) do
      begin
        clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 0.0, 1.0, -yMid);
        areaAbove := areaAbove - Abs(PolygonArea2D(clipped));
      end;
    end;
    if areaAbove > areaAboveTarget then
      yLo := yMid
    else
      yHi := yMid;
  end;
  pnaY := 0.5 * (yLo + yHi);

  // Integrate distance from PNA: Sx = \iint |y - pnaY| dA
  Props.Sx := 0.0;
  for f := 0 to High(Faces) do
  begin
    // Portion above PNA
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 0.0, 1.0, -pnaY);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sx := Props.Sx + (Abs(subLi.Qx) - Abs(subLi.Area) * pnaY);
    end;
    // Portion below PNA
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 0.0, -1.0, pnaY);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sx := Props.Sx + (Abs(subLi.Area) * pnaY - Abs(subLi.Qx));
    end;
    // Deduct holes
    for h := 0 to High(Faces[f].Holes) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 0.0, 1.0, -pnaY);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sx := Props.Sx - (Abs(subLi.Qx) - Abs(subLi.Area) * pnaY);
      end;
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 0.0, -1.0, pnaY);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sx := Props.Sx - (Abs(subLi.Area) * pnaY - Abs(subLi.Qx));
      end;
    end;
  end;

  // Sy via vertical PNA solve (x = pnaX)
  areaRightTarget := 0.5 * Props.Area;
  xLo := Props.BBoxXMin;
  xHi := Props.BBoxXMax;
  for iter := 1 to 60 do
  begin
    xMid := 0.5 * (xLo + xHi);
    areaRight := 0.0;
    for f := 0 to High(Faces) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 1.0, 0.0, -xMid);
      areaRight := areaRight + Abs(PolygonArea2D(clipped));
      for h := 0 to High(Faces[f].Holes) do
      begin
        clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 1.0, 0.0, -xMid);
        areaRight := areaRight - Abs(PolygonArea2D(clipped));
      end;
    end;
    if areaRight > areaRightTarget then
      xLo := xMid
    else
      xHi := xMid;
  end;
  pnaX := 0.5 * (xLo + xHi);

  Props.Sy := 0.0;
  for f := 0 to High(Faces) do
  begin
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 1.0, 0.0, -pnaX);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sy := Props.Sy + (Abs(subLi.Qy) - Abs(subLi.Area) * pnaX);
    end;
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, -1.0, 0.0, pnaX);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sy := Props.Sy + (Abs(subLi.Area) * pnaX - Abs(subLi.Qy));
    end;
    for h := 0 to High(Faces[f].Holes) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 1.0, 0.0, -pnaX);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sy := Props.Sy - (Abs(subLi.Qy) - Abs(subLi.Area) * pnaX);
      end;
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, -1.0, 0.0, pnaX);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sy := Props.Sy - (Abs(subLi.Area) * pnaX - Abs(subLi.Qy));
      end;
    end;
  end;

  // 7. Torsion properties
  Props.Ip := Props.Ixx + Props.Iyy;
  if SolveNumericalJ then
    Props.J := SolvePrandtlTorsion(Faces, Props.BBoxXMin, Props.BBoxXMax, Props.BBoxYMin, Props.BBoxYMax)
  else
    Props.J := Props.Ip;
end;

end.
