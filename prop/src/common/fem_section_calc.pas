unit fem_section_calc;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_section_types;

type
  TLoopIntegrals = record
    Area, Perimeter: Double;
    Qx, Qy: Double;
    Ixx0, Iyy0, Ixy0: Double;
  end;

function ComputeLoopIntegrals(const Loop: TPolygonLoop): TLoopIntegrals;
function ClipPolygonHalfPlane(const Poly: TPoint2DArray; A, B, C: Double): TPoint2DArray;
function PolygonArea2D(const P: TPoint2DArray): Double;
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
  t, d1, d2: Double;

  function Inside(const Pt: TPoint2D): Boolean; inline;
  begin
    Result := (A * Pt.X + B * Pt.Y + C) >= -1.0E-12;
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
      if not sIn then
      begin
        d1 := A * s.X + B * s.Y + C;
        d2 := A * e.X + B * e.Y + C;
        if Abs(d1 - d2) > 1.0E-14 then
        begin
          t := d1 / (d1 - d2);
          AddPt(Pt2D(s.X + t * (e.X - s.X), s.Y + t * (e.Y - s.Y)));
        end
        else
          AddPt(s);
      end;
      AddPt(e);
    end
    else if sIn then
    begin
      d1 := A * s.X + B * s.Y + C;
      d2 := A * e.X + B * e.Y + C;
      if Abs(d1 - d2) > 1.0E-14 then
      begin
        t := d1 / (d1 - d2);
        AddPt(Pt2D(s.X + t * (e.X - s.X), s.Y + t * (e.Y - s.Y)));
      end
      else
        AddPt(s);
    end;
    s := e;
    sIn := eIn;
  end;
end;

function PointInPolygon(const Pt: TPoint2D; const Poly: TPoint2DArray): Boolean;
var
  i, n, wn: Integer;
  vt1, vt2: TPoint2D;
  cross: Double;
begin
  wn := 0;
  n := Length(Poly);
  for i := 0 to n - 1 do
  begin
    vt1 := Poly[i];
    vt2 := Poly[(i + 1) mod n];
    cross := (vt2.X - vt1.X) * (Pt.Y - vt1.Y) - (Pt.X - vt1.X) * (vt2.Y - vt1.Y);
    if vt1.Y <= Pt.Y then
    begin
      if (vt2.Y > Pt.Y) and (cross > 0) then Inc(wn);
    end
    else
    begin
      if (vt2.Y <= Pt.Y) and (cross < 0) then Dec(wn);
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

// Successive Over-Relaxation (SOR) solver for -Laplacian(Phi) = 2
function SolvePrandtlTorsion(const Faces: TSectionFaceArray;
  xMin, xMax, yMin, yMax: Double): Double;
const
  GridDim = 150;
  MaxIter = 350;
  Omega = 1.82;
var
  Nx, Ny, i, j, iter: Integer;
  hx, hy, wx, wy, w0, phiNew, sumPhi, diff, maxDiff: Double;
  InDomain: array of array of Boolean;
  Phi: array of array of Double;
  pt: TPoint2D;
begin
  Nx := GridDim;
  Ny := Round(GridDim * (yMax - yMin) / Max(xMax - xMin, 1.0E-6));
  if Ny < 50 then Ny := 50;
  if Ny > 300 then Ny := 300;

  hx := (xMax - xMin) / (Nx - 1);
  hy := (yMax - yMin) / (Ny - 1);
  wx := 1.0 / (hx * hx);
  wy := 1.0 / (hy * hy);
  w0 := 2.0 * (wx + wy);

  SetLength(InDomain, Nx, Ny);
  SetLength(Phi, Nx, Ny);

  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
    begin
      pt.X := xMin + i * hx;
      pt.Y := yMin + j * hy;
      InDomain[i, j] := PointInAnyFace(pt, Faces);
      Phi[i, j] := 0.0;
    end;

  for iter := 1 to MaxIter do
  begin
    maxDiff := 0.0;
    for i := 1 to Nx - 2 do
      for j := 1 to Ny - 2 do
        if InDomain[i, j] then
        begin
          phiNew := (2.0 + wx * (Phi[i - 1, j] + Phi[i + 1, j]) +
                           wy * (Phi[i, j - 1] + Phi[i, j + 1])) / w0;
          phiNew := (1.0 - Omega) * Phi[i, j] + Omega * phiNew;
          if phiNew < 0.0 then phiNew := 0.0;
          diff := Abs(phiNew - Phi[i, j]);
          if diff > maxDiff then maxDiff := diff;
          Phi[i, j] := phiNew;
        end;
    if maxDiff < 1.0E-5 then Break;
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
  poly, clipped: TPoint2DArray;
  outerLi, holeLi, subLi: TLoopIntegrals;
  netQx, netQy, netIxx0, netIyy0, netIxy0: Double;
  diff, R, Iavg, twoTheta: Double;
  yLo, yHi, yMid, areaAboveTarget, areaAbove, pnaY: Double;
  xLo, xHi, xMid, areaRightTarget, areaRight, pnaX: Double;
  dummyLoop: TPolygonLoop;
  jNumerical, jThinWalled: Double;
begin
  if Length(Faces) = 0 then
    raise Exception.Create('Section contains no faces');

  Props.Area := 0.0;
  Props.Perimeter := 0.0;
  netQx := 0.0; netQy := 0.0;
  netIxx0 := 0.0; netIyy0 := 0.0; netIxy0 := 0.0;

  Props.BBoxXMin :=  1.0E300; Props.BBoxXMax := -1.0E300;
  Props.BBoxYMin :=  1.0E300; Props.BBoxYMax := -1.0E300;

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
      holeLi.Area := Abs(holeLi.Area);
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

  Props.CentroidX := netQy / Props.Area;
  Props.CentroidY := netQx / Props.Area;

  Props.Ixx := netIxx0 - Props.Area * Sqr(Props.CentroidY);
  Props.Iyy := netIyy0 - Props.Area * Sqr(Props.CentroidX);
  Props.Ixy := netIxy0 - Props.Area * Props.CentroidX * Props.CentroidY;

  // Clean numerical zero noise on symmetric cross-sections
  if Abs(Props.Ixy) < 1.0E-11 * Max(Props.Ixx, Props.Iyy) then
    Props.Ixy := 0.0;

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

  Props.rx := Sqrt(Props.Ixx / Props.Area);
  Props.ry := Sqrt(Props.Iyy / Props.Area);
  Props.r1 := Sqrt(Props.I1 / Props.Area);
  Props.r2 := Sqrt(Props.I2 / Props.Area);

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

  // Exact Plastic Section Modulus Sx = Qx(above PNA) - Qx(below PNA)
  areaAboveTarget := 0.5 * Props.Area;
  yLo := Props.BBoxYMin; yHi := Props.BBoxYMax;
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
    if areaAbove > areaAboveTarget then yLo := yMid else yHi := yMid;
  end;
  pnaY := 0.5 * (yLo + yHi);

  Props.Sx := 0.0;
  for f := 0 to High(Faces) do
  begin
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 0.0, 1.0, -pnaY);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sx := Props.Sx + (subLi.Qx - subLi.Area * pnaY);
    end;
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, 0.0, -1.0, pnaY);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sx := Props.Sx + (subLi.Area * pnaY - subLi.Qx);
    end;
    for h := 0 to High(Faces[f].Holes) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 0.0, 1.0, -pnaY);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sx := Props.Sx - (subLi.Qx - subLi.Area * pnaY);
      end;
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 0.0, -1.0, pnaY);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sx := Props.Sx - (subLi.Area * pnaY - subLi.Qx);
      end;
    end;
  end;

  // Exact Plastic Section Modulus Sy = Qy(right of PNA) - Qy(left of PNA)
  areaRightTarget := 0.5 * Props.Area;
  xLo := Props.BBoxXMin; xHi := Props.BBoxXMax;
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
    if areaRight > areaRightTarget then xLo := xMid else xHi := xMid;
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
      Props.Sy := Props.Sy + (subLi.Qy - subLi.Area * pnaX);
    end;
    clipped := ClipPolygonHalfPlane(Faces[f].OuterLoop.Points, -1.0, 0.0, pnaX);
    if Length(clipped) >= 3 then
    begin
      dummyLoop.Points := clipped;
      subLi := ComputeLoopIntegrals(dummyLoop);
      Props.Sy := Props.Sy + (subLi.Area * pnaX - subLi.Qy);
    end;
    for h := 0 to High(Faces[f].Holes) do
    begin
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, 1.0, 0.0, -pnaX);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sy := Props.Sy - (subLi.Qy - subLi.Area * pnaX);
      end;
      clipped := ClipPolygonHalfPlane(Faces[f].Holes[h].Points, -1.0, 0.0, pnaX);
      if Length(clipped) >= 3 then
      begin
        dummyLoop.Points := clipped;
        subLi := ComputeLoopIntegrals(dummyLoop);
        Props.Sy := Props.Sy - (subLi.Area * pnaX - subLi.Qy);
      end;
    end;
  end;

  Props.Ip := Props.Ixx + Props.Iyy;

  // St. Venant Torsion J
  // Thin-walled open profile asymptotic approximation: J_tw = (4/3) * (A^3 / P^2)
  if Props.Perimeter > 1.0E-6 then
    jThinWalled := (4.0 / 3.0) * (Power(Props.Area, 3.0) / Sqr(Props.Perimeter))
  else
    jThinWalled := 0.0;
  Props.JThinWalled := jThinWalled;

  if SolveNumericalJ then
  begin
    jNumerical := SolvePrandtlTorsion(Faces, Props.BBoxXMin, Props.BBoxXMax, Props.BBoxYMin, Props.BBoxYMax);
    // Take the maximum of grid solve and thin-walled asymptotic lower bound
    Props.J := Max(jNumerical, jThinWalled);
  end
  else
    Props.J := jThinWalled;
end;

end.
