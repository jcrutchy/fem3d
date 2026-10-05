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
// SolveNumericalJ = False skips the grid solve: J is then only the thin-wall
// lower bound (4/3 A^3/P^2), which is far too low for compact or hollow
// sections.  Use it only when J is not needed.
procedure ComputeSectionProperties(const FacesIn: TSectionFaceArray;
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

// Finite-difference solve of the Prandtl stress function problem
//   -Laplacian(Phi) = 2 in the section,  Phi = 0 on the OUTER boundary,
// on a regular grid embedded in the bounding box.  J = 2 * integral(Phi) dA.
//
// SECTIONS WITH HOLES (closed cells).  Phi is NOT zero on a hole boundary: it
// is an unknown constant c_k there, fixed by the circulation condition
// (the shear flow around the hole must equal 2*G*theta*A_hole).  The standard
// way to get that condition is the membrane analogy with a rigid weightless
// LID over each hole: Phi is constant over the lid, the pressure acts on the
// lid too, and J = 2 * (volume under the membrane INCLUDING the lids).  In
// discrete form: all grid nodes inside hole k are tied together into ONE
// unknown c_k, which is solved for along with the section nodes, and the
// lid nodes count toward the integral.  (Pinning Phi = 0 on hole boundaries,
// as the first version did, is only right for solid sections and gave a
// hollow box J about 100x too small.)
//
// BOUNDARY POSITION.  The problem is written as a sum over grid links of
// g*(Phi_a - Phi_b)^2 (a symmetric, positive definite energy).  A link
// between two section nodes has g = 1/h^2.  A link from a section node to a
// node outside the section (value 0) or inside a hole (value c_k) crosses the
// true boundary at a fraction theta of the way along it, found by bisection
// on the polygon, and gets g = 1/(theta*h^2).  That places the boundary where
// it really is instead of at the nearest grid node, which otherwise makes
// every wall about one cell too thick (a 3 mm tube wall came out 15% stiff).
//
// The system is solved with Conjugate Gradient and stopped on the RELATIVE
// RESIDUAL, not on a fixed iteration count.  (The original SOR version
// stopped after 350 sweeps whether or not it had converged, which left
// compact sections 20-35% low.)
function SolvePrandtlTorsion(const Faces: TSectionFaceArray;
  xMin, xMax, yMin, yMax: Double): Double;
const
  GridDim = 150;
  MaxIter = 20000;
  RelTol = 1.0E-10;
  ThetaMin = 0.05;   // keeps links well conditioned when the boundary almost touches a node
var
  Nx, Ny, i, j, k, f, h, m, iter, d, ni, nj, nLinks: Integer;
  nHoles, nFree, nLid, nDof, nVec: Integer;
  hx, hy, wx, wy: Double;
  alpha, beta, rr, rrOld, pAp, bb, total, g, dv: Double;
  pt: TPoint2D;
  HolePolys: array of TPoint2DArray;
  Kind: array of array of Byte;       // 0 = outside section, 1 = section node, 2 = lid node
  HoleOf: array of array of Integer;  // flat hole index for lid nodes
  Idx: array of array of Integer;     // index into the reduced vector
  HoleDof, DofCount: array of Integer;
  LA, LB: array of Integer;           // link endpoints (LB = -1: fixed zero)
  LG: array of Double;                // link weights
  x, Res, Dir, Ap: array of Double;

  procedure AddLink(a, b: Integer; gg: Double);
  begin
    if nLinks >= Length(LA) then
    begin
      SetLength(LA, nLinks * 2 + 1024);
      SetLength(LB, Length(LA));
      SetLength(LG, Length(LA));
    end;
    LA[nLinks] := a; LB[nLinks] := b; LG[nLinks] := gg;
    Inc(nLinks);
  end;

  // Fraction of the way from node (i0,j0) (a section node) to the neighbouring
  // node (i1,j1) at which the section boundary lies.
  function CutFraction(i0, j0, i1, j1: Integer): Double;
  var
    lo, hi, mid: Double;
    it: Integer;
    p: TPoint2D;
  begin
    lo := 0.0; hi := 1.0;
    for it := 1 to 24 do
    begin
      mid := 0.5 * (lo + hi);
      p.X := xMin + (i0 + mid * (i1 - i0)) * hx;
      p.Y := yMin + (j0 + mid * (j1 - j0)) * hy;
      if PointInAnyFace(p, Faces) then lo := mid else hi := mid;
    end;
    Result := 0.5 * (lo + hi);
    if Result < ThetaMin then Result := ThetaMin;
  end;

const
  DI: array[0..3] of Integer = (1, -1, 0, 0);
  DJ: array[0..3] of Integer = (0, 0, 1, -1);

begin
  Nx := GridDim;
  Ny := Round(GridDim * (yMax - yMin) / Max(xMax - xMin, 1.0E-6));
  if Ny < 50 then Ny := 50;
  if Ny > 300 then Ny := 300;

  hx := (xMax - xMin) / (Nx - 1);
  hy := (yMax - yMin) / (Ny - 1);
  wx := 1.0 / (hx * hx);
  wy := 1.0 / (hy * hy);

  // Flat list of hole polygons
  nHoles := 0;
  for f := 0 to High(Faces) do
    Inc(nHoles, Length(Faces[f].Holes));
  SetLength(HolePolys, nHoles);
  SetLength(HoleDof, nHoles);
  k := 0;
  for f := 0 to High(Faces) do
    for h := 0 to High(Faces[f].Holes) do
    begin
      HolePolys[k] := Faces[f].Holes[h].Points;
      HoleDof[k] := -1;
      Inc(k);
    end;

  SetLength(Kind, Nx, Ny);
  SetLength(HoleOf, Nx, Ny);
  SetLength(Idx, Nx, Ny);

  // Pass 1: classify every node
  nFree := 0;
  nLid := 0;
  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
    begin
      Kind[i, j] := 0;
      HoleOf[i, j] := -1;
      Idx[i, j] := -1;
      if (i = 0) or (i = Nx - 1) or (j = 0) or (j = Ny - 1) then Continue;
      pt.X := xMin + i * hx;
      pt.Y := yMin + j * hy;
      if PointInAnyFace(pt, Faces) then
      begin
        Kind[i, j] := 1;
        Inc(nFree);
      end
      else
        for k := 0 to nHoles - 1 do
          if PointInPolygon(pt, HolePolys[k]) then
          begin
            Kind[i, j] := 2;
            HoleOf[i, j] := k;
            Inc(nLid);
            Break;
          end;
    end;

  if nFree = 0 then Exit(0.0);   // section too thin for the grid

  // Pass 2: number the unknowns.  Section nodes first, then one unknown per
  // hole that actually owns at least one grid node (a hole smaller than a
  // grid cell is ignored rather than left as an empty, singular equation).
  m := 0;
  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
      if Kind[i, j] = 1 then
      begin
        Idx[i, j] := m;
        Inc(m);
      end;
  nDof := 0;
  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
      if (Kind[i, j] = 2) and (HoleDof[HoleOf[i, j]] < 0) then
      begin
        HoleDof[HoleOf[i, j]] := nFree + nDof;
        Inc(nDof);
      end;
  nVec := nFree + nDof;
  SetLength(DofCount, nVec);
  for i := 0 to Nx - 1 do
    for j := 0 to Ny - 1 do
      if Kind[i, j] = 2 then
      begin
        Idx[i, j] := HoleDof[HoleOf[i, j]];
        Inc(DofCount[Idx[i, j]]);
      end;

  // Pass 3: build the links
  nLinks := 0;
  for i := 1 to Nx - 2 do
    for j := 1 to Ny - 2 do
      case Kind[i, j] of
        1:
          for d := 0 to 3 do
          begin
            ni := i + DI[d]; nj := j + DJ[d];
            if d < 2 then g := wx else g := wy;
            case Kind[ni, nj] of
              1: if (d = 0) or (d = 2) then AddLink(Idx[i, j], Idx[ni, nj], g);
              2: AddLink(Idx[i, j], Idx[ni, nj], g / CutFraction(i, j, ni, nj));
            else
              AddLink(Idx[i, j], -1, g / CutFraction(i, j, ni, nj));
            end;
          end;
        2:
          for d := 0 to 3 do
          begin
            ni := i + DI[d]; nj := j + DJ[d];
            if d < 2 then g := wx else g := wy;
            case Kind[ni, nj] of
              0: AddLink(Idx[i, j], -1, g);     // wall thinner than a cell: no section node between
              2: if ((d = 0) or (d = 2)) and (Idx[ni, nj] <> Idx[i, j]) then
                   AddLink(Idx[i, j], Idx[ni, nj], g);
            end;
          end;
      end;

  SetLength(x, nVec);
  SetLength(Res, nVec);
  SetLength(Dir, nVec);
  SetLength(Ap, nVec);
  for m := 0 to nVec - 1 do
  begin
    x[m] := 0.0;
    if m < nFree then Res[m] := 2.0 else Res[m] := 2.0 * DofCount[m];
    Dir[m] := Res[m];
    Ap[m] := 0.0;
  end;
  bb := 0.0;
  for m := 0 to nVec - 1 do bb := bb + Res[m] * Res[m];
  rr := bb;

  for iter := 1 to MaxIter do
  begin
    for m := 0 to nVec - 1 do Ap[m] := 0.0;
    for m := 0 to nLinks - 1 do
      if LB[m] >= 0 then
      begin
        dv := LG[m] * (Dir[LA[m]] - Dir[LB[m]]);
        Ap[LA[m]] := Ap[LA[m]] + dv;
        Ap[LB[m]] := Ap[LB[m]] - dv;
      end
      else
        Ap[LA[m]] := Ap[LA[m]] + LG[m] * Dir[LA[m]];

    pAp := 0.0;
    for m := 0 to nVec - 1 do pAp := pAp + Dir[m] * Ap[m];
    if pAp <= 0.0 then Break;       // cannot happen for an SPD operator
    alpha := rr / pAp;

    rrOld := rr;
    rr := 0.0;
    for m := 0 to nVec - 1 do
    begin
      x[m] := x[m] + alpha * Dir[m];
      Res[m] := Res[m] - alpha * Ap[m];
      rr := rr + Res[m] * Res[m];
    end;

    if Sqrt(rr / bb) < RelTol then Break;

    beta := rr / rrOld;
    for m := 0 to nVec - 1 do Dir[m] := Res[m] + beta * Dir[m];
  end;

  // J = 2 * integral of Phi over section AND lids
  total := 0.0;
  for m := 0 to nFree - 1 do total := total + x[m];
  for m := nFree to nVec - 1 do total := total + x[m] * DofCount[m];
  Result := 2.0 * total * hx * hy;
end;

procedure ComputeSectionProperties(const FacesIn: TSectionFaceArray;
  var Props: TSectionProperties; SolveNumericalJ: Boolean);
var
  Faces: TSectionFaceArray;   // private copy: every hole counter-clockwise
  f, h, i, iter: Integer;
  poly, clipped: TPoint2DArray;
  outerLi, holeLi, subLi: TLoopIntegrals;
  netQx, netQy, netIxx0, netIyy0, netIxy0: Double;
  diff, R, Iavg, twoTheta: Double;
  yLo, yHi, yMid, areaAboveTarget, areaAbove, pnaY: Double;
  xLo, xHi, xMid, areaRightTarget, areaRight, pnaX: Double;
  dummyLoop: TPolygonLoop;
  jNumerical, jThinWalled: Double;
  thetaB, cT, sT, du, dv, rad: Double;
begin
  if Length(FacesIn) = 0 then
    raise Exception.Create('Section contains no faces');

  // Hole loops may arrive clockwise (the documented convention) or
  // counter-clockwise.  Every integral below treats a hole as a CCW region
  // that is SUBTRACTED, so take a private copy with every hole reversed to
  // CCW.  The caller's arrays are never modified.
  SetLength(Faces, Length(FacesIn));
  for f := 0 to High(FacesIn) do
  begin
    Faces[f].OuterLoop := FacesIn[f].OuterLoop;
    SetLength(Faces[f].Holes, Length(FacesIn[f].Holes));
    for h := 0 to High(FacesIn[f].Holes) do
    begin
      Faces[f].Holes[h].IsHole := True;
      SetLength(Faces[f].Holes[h].Points, Length(FacesIn[f].Holes[h].Points));
      if PolygonArea2D(FacesIn[f].Holes[h].Points) >= 0.0 then
      begin
        for i := 0 to High(FacesIn[f].Holes[h].Points) do
          Faces[f].Holes[h].Points[i] := FacesIn[f].Holes[h].Points[i];
      end
      else
      begin
        for i := 0 to High(FacesIn[f].Holes[h].Points) do
          Faces[f].Holes[h].Points[i] :=
            FacesIn[f].Holes[h].Points[High(FacesIn[f].Holes[h].Points) - i];
      end;
    end;
  end;

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
      // Hole is now CCW, so its integrals are the signed integrals of the
      // region it encloses.  Q and I about the ORIGIN are signed quantities
      // (they change sign with position), so they must be subtracted as
      // signed values -- never as magnitudes.
      holeLi := ComputeLoopIntegrals(Faces[f].Holes[h]);
      Props.Area := Props.Area - holeLi.Area;
      Props.Perimeter := Props.Perimeter + holeLi.Perimeter;
      netQx := netQx - holeLi.Qx;
      netQy := netQy - holeLi.Qy;
      netIxx0 := netIxx0 - holeLi.Ixx0;
      netIyy0 := netIyy0 - holeLi.Iyy0;
      netIxy0 := netIxy0 - holeLi.Ixy0;
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

  // ---- Beam-line values (principal axes, centroid-based fibre distances) ----
  // Rotate by theta so the local axes are the principal axes closest to the
  // section x/y axes.  Iu(theta) = integral(v^2 dA) for u along theta:
  //   Iu = (Ixx+Iyy)/2 + (Ixx-Iyy)/2 cos2t - Ixy sin2t
  // Local z carries the u axis (Iz = integral(y'^2 dA)), local y the v axis,
  // matching the unrotated mapping Iz = Ixx, Iy = Iyy.
  if Props.Ixy = 0.0 then
    thetaB := 0.0
  else
  begin
    thetaB := 0.5 * ArcTan2(-2.0 * Props.Ixy, Props.Ixx - Props.Iyy);
    if thetaB > 0.25 * Pi then thetaB := thetaB - 0.5 * Pi
    else if thetaB <= -0.25 * Pi then thetaB := thetaB + 0.5 * Pi;
  end;
  cT := Cos(thetaB);
  sT := Sin(thetaB);
  Props.BeamIz := 0.5 * (Props.Ixx + Props.Iyy) + 0.5 * (Props.Ixx - Props.Iyy) * Cos(2.0 * thetaB)
                  - Props.Ixy * Sin(2.0 * thetaB);
  Props.BeamIy := Props.Ixx + Props.Iyy - Props.BeamIz;
  Props.BeamThetaDeg := thetaB * 180.0 / Pi;
  Props.BeamZDirX := cT;   Props.BeamZDirY := sT;      // u axis
  Props.BeamYDirX := -sT;  Props.BeamYDirY := cT;      // v axis
  Props.BeamCy := 0.0;
  Props.BeamCz := 0.0;
  Props.BeamRt := 0.0;
  for f := 0 to High(Faces) do
  begin
    poly := Faces[f].OuterLoop.Points;
    for i := 0 to High(poly) do
    begin
      du := (poly[i].X - Props.CentroidX) * cT + (poly[i].Y - Props.CentroidY) * sT;
      dv := -(poly[i].X - Props.CentroidX) * sT + (poly[i].Y - Props.CentroidY) * cT;
      if Abs(dv) > Props.BeamCy then Props.BeamCy := Abs(dv);
      if Abs(du) > Props.BeamCz then Props.BeamCz := Abs(du);
      rad := Sqrt(du * du + dv * dv);
      if rad > Props.BeamRt then Props.BeamRt := rad;
    end;
  end;

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
  // Thin-walled open profile asymptotic approximation: J_tw = (4/3) * (A^3 / P^2).
  // For a closed (hollow) section this is far below the true value (it is the
  // J of the same tube with a slit cut in it), so it only acts as a floor.
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
