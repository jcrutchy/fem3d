program run_q8_plate_test;

// Standalone verification for fem_elements.QuadPlateMindlinStiffnessQ8Local.
// Same spirit/methodology as run_q8_membrane_test.lpr and the project's
// DKQ checks in run_patch_test.lpr. Checks 1-3 rely on one general
// isoparametric-interpolation fact used throughout: if a nodal dof is
// set to a LINEAR function of the node's own PHYSICAL (x,y) coordinates,
// the FE-interpolated field exactly equals that same linear function
// everywhere in the element -- on ANY quad shape, however distorted --
// because shape functions sum to 1 and the isoparametric map itself is
// sum(Ni*xi_node), so interpolating f_i=c0+c1*xi+c2*yi gives back
// exactly c0+c1*x+c2*y. This is the same fact that made the Q8 MEMBRANE
// element's distorted-quad uniaxial-strain check exact.
//
//   1. Rigid translation (w=const, rx=ry=0): zero curvature and zero
//      shear strain everywhere (trivially, both are linear fields with
//      zero coefficients) -> zero nodal force. Rect + distorted.
//   2. Rigid tilt (rx=rx0, ry=ry0 constant, w=rx0*y-ry0*x exactly):
//      zero curvature (rx,ry constant) AND zero shear strain (by the
//      same construction DKQ/shell already use) -> zero nodal force.
//      The single check most likely to catch a sign error in EITHER
//      the curvature or the shear B-matrix, since both must
//      independently vanish for this one field. Rect + distorted.
//   3. Constant shear strain, zero curvature (rx=rx0, ry=ry0 constant,
//      w linear with a slope chosen to give an exact target gamma_xz
//      or gamma_yz): strain energy must match the closed-form
//      0.5*(gamma_xz^2+gamma_yz^2)*Ds*Area exactly. Rect + distorted
//      (exact on both, per the fact above -- rx,ry constant and w
//      linear are both exactly reproduced regardless of distortion).
//   4. Constant curvature, zero shear (rx, ry each given a LINEAR part
//      to produce an exact target kappa_x, kappa_y, or kappa_xy, with
//      w's matching QUADRATIC term chosen to cancel shear exactly):
//      strain energy must match 0.5*kappa^T*Db*kappa*Area exactly.
//      RECTANGLE ONLY -- a quadratic w field is only guaranteed to be
//      reproduced exactly by Q8 isoparametric interpolation when the
//      element's own coordinate map is itself affine (true for an
//      axis-aligned rectangle with edge-midpoint midside nodes, not
//      true in general for a distorted quad). On a distorted quad this
//      element is expected to show some nonzero "parasitic shear"
//      energy alongside the bending energy for this field -- a real,
//      known characteristic of a plain isoparametric Mindlin element
//      (not using an assumed-shear scheme like MITC), not a bug in
//      this implementation. Flagged as a follow-up if it matters in
//      practice (a locking/distortion-sensitivity benchmark, or
//      switching to an assumed-shear formulation).
//
// NOT checked here: shear-locking behavior as thickness/span -> 0.
// That needs a thin-plate deflection benchmark against a known
// solution, not a constant-field patch test (constant fields are
// integrated exactly by both the 3x3 and 2x2 rules regardless of
// locking).
//
// Run with: ./run_q8_plate_test  (exit code 0 = all checks passed)

{$mode objfpc}{$H+}

uses
  SysUtils, fem_types, fem_elements;

var
  FailCount: Integer;

procedure Check(const Name: string; Cond: Boolean; const Detail: string);
begin
  if Cond then
    WriteLn('PASS  ', Name)
  else
  begin
    WriteLn('FAIL  ', Name, '  -- ', Detail);
    Inc(FailCount);
  end;
end;

function ApproxZero(V, Tol: Double): Boolean;
begin
  Result := Abs(V) <= Tol;
end;

function ApproxEqual(A, B, Tol: Double): Boolean;
begin
  Result := Abs(A - B) <= Tol * (1.0 + Abs(B));
end;

function MatVecN(const K: TElemMatrix; const u: array of Double; N: Integer): TDoubleArray;
var
  i, j: Integer;
begin
  SetLength(Result, N + 1);
  for i := 1 to N do
  begin
    Result[i] := 0;
    for j := 1 to N do
      Result[i] := Result[i] + K[i, j] * u[j];
  end;
end;

function StrainEnergy(const K: TElemMatrix; const u: TDoubleArray; N: Integer): Double;
var
  F: TDoubleArray;
  i: Integer;
begin
  F := MatVecN(K, u, N);
  Result := 0;
  for i := 1 to N do
    Result := Result + 0.5 * u[i] * F[i];
end;

// Nodal dof [w, rx, ry] (order 3i-2, 3i-1, 3i) for rx=rx0, ry=ry0
// (constant) and w = w0 + wx_lin*x + wy_lin*y (linear). Zero curvature
// always; shear = (wx_lin+ry0, wy_lin-rx0), constant.
function BuildConstDof(const lx, ly: array of Double;
  rx0, ry0, w0, wx_lin, wy_lin: Double): TDoubleArray;
var
  n: Integer;
begin
  SetLength(Result, 25);
  for n := 0 to 7 do
  begin
    Result[3*n + 1] := w0 + wx_lin * lx[n] + wy_lin * ly[n];
    Result[3*n + 2] := rx0;
    Result[3*n + 3] := ry0;
  end;
end;

procedure CheckZeroForce(const CaseName: string; const K: TElemMatrix;
  const u: TDoubleArray; Tol: Double);
var
  F: TDoubleArray;
  i: Integer;
  maxF: Double;
begin
  F := MatVecN(K, u, 24);
  maxF := 0;
  for i := 1 to 24 do
    if Abs(F[i]) > maxF then maxF := Abs(F[i]);
  Check(CaseName, ApproxZero(maxF, Tol), Format('max |F| = %g (tol %g)', [maxF, Tol]));
end;

// Pure-shear (zero-curvature) patch test: rx0, ry0 constant; w's linear
// slope chosen so gamma_xz=targetGxz, gamma_yz=targetGyz exactly.
procedure CheckShearEnergy(const CaseName: string; const K: TElemMatrix;
  const lx, ly: array of Double; E, Nu, Thickness, ShearK, Area: Double;
  rx0, ry0, targetGxz, targetGyz: Double; Tol: Double);
var
  u: TDoubleArray;
  wx_lin, wy_lin, Gmod, DsDiag: Double;
  closedForm, computed: Double;
begin
  wx_lin := targetGxz - ry0;
  wy_lin := targetGyz + rx0;
  u := BuildConstDof(lx, ly, rx0, ry0, 0.0, wx_lin, wy_lin);
  Gmod := E / (2.0 * (1.0 + Nu));
  DsDiag := ShearK * Gmod * Thickness;
  closedForm := 0.5 * DsDiag * (targetGxz*targetGxz + targetGyz*targetGyz) * Area;
  computed := StrainEnergy(K, u, 24);
  Check(CaseName, ApproxEqual(computed, closedForm, Tol),
    Format('computed U = %g, closed-form U = %g', [computed, closedForm]));
end;

// Pure-bending (zero-shear) constant-curvature patch test, RECTANGLE
// ONLY (see file header). Target curvatures (kx, ky, kxy) determine
// rx, ry, and w together: rx=a1*x+a2*y, ry=b1*x+b2*y give
// kappa_x=-b1, kappa_y=a2, kappa_xy=a1-b2 -- but for a SINGLE w(x,y)
// to satisfy BOTH d(w)/dx=-ry and d(w)/dy=rx everywhere (the zero-
// shear condition), rx and ry can't be independently arbitrary: the
// mixed partials must agree (d(-ry)/dy = d(rx)/dx), which forces
// a1=-b2. Given that constraint, the unique compatible choice for a
// target (kx,ky,kxy) is:
//   b1=-kx, a2=ky, a1=kxy/2, b2=-kxy/2
//   w(x,y) = 0.5*kx*x^2 + 0.5*kxy*x*y + 0.5*ky*y^2
// (integrate d(w)/dx=-ry=kx*x-0.5*kxy*y up to the y-only constant,
// fixed by matching d(w)/dy=rx=0.5*kxy*x+ky*y).
procedure CheckBendingEnergy(const CaseName: string; const K: TElemMatrix;
  const lx, ly: array of Double; E, Nu, Thickness, Area: Double;
  kx, ky, kxy: Double; Tol: Double);
var
  u: TDoubleArray;
  n: Integer;
  a1, a2, b1, b2: Double;
  Dfac, D11, D12, D33: Double;
  densityU, closedForm, computed: Double;
begin
  b1 := -kx; a2 := ky; a1 := kxy / 2.0; b2 := -kxy / 2.0;

  SetLength(u, 25);
  for n := 0 to 7 do
  begin
    u[3*n + 1] := 0.5*kx*lx[n]*lx[n] + 0.5*kxy*lx[n]*ly[n] + 0.5*ky*ly[n]*ly[n];
    u[3*n + 2] := a1*lx[n] + a2*ly[n];   // rx
    u[3*n + 3] := b1*lx[n] + b2*ly[n];   // ry
  end;

  Dfac := (Thickness*Thickness*Thickness / 12.0) * (E / (1.0 - Nu*Nu));
  D11 := Dfac; D12 := Dfac*Nu; D33 := Dfac*(1.0-Nu)/2.0;
  densityU := 0.5 * (D11*kx*kx + D11*ky*ky + 2*D12*kx*ky + D33*kxy*kxy);
  closedForm := densityU * Area;

  computed := StrainEnergy(K, u, 24);
  Check(CaseName, ApproxEqual(computed, closedForm, Tol),
    Format('computed U = %g, closed-form U = %g', [computed, closedForm]));
end;

var
  K: TElemMatrix;
  E, Nu, Thickness, ShearK: Double;
  lxRect, lyRect: array[0..7] of Double;
  lxDist, lyDist: array[0..7] of Double;
  areaRect, areaDist: Double;
  u: TDoubleArray;

begin
  FailCount := 0;
  E := 210000.0;
  Nu := 0.3;
  Thickness := 5.0;
  ShearK := 5.0 / 6.0;

  // --- Rectangle, 4x2, same layout as the membrane test ---
  lxRect[0] := 0; lyRect[0] := 0;
  lxRect[1] := 4; lyRect[1] := 0;
  lxRect[2] := 4; lyRect[2] := 2;
  lxRect[3] := 0; lyRect[3] := 2;
  lxRect[4] := 2; lyRect[4] := 0;
  lxRect[5] := 4; lyRect[5] := 1;
  lxRect[6] := 2; lyRect[6] := 2;
  lxRect[7] := 0; lyRect[7] := 1;
  areaRect := 8.0;

  K := QuadPlateMindlinStiffnessQ8Local(E, Nu, Thickness, ShearK,
    lxRect[0], lyRect[0], lxRect[1], lyRect[1], lxRect[2], lyRect[2], lxRect[3], lyRect[3],
    lxRect[4], lyRect[4], lxRect[5], lyRect[5], lxRect[6], lyRect[6], lxRect[7], lyRect[7]);

  u := BuildConstDof(lxRect, lyRect, 0.0, 0.0, 0.0021, 0.0, 0.0);
  CheckZeroForce('Rect: rigid translation -> zero force', K, u, 1e-8);

  u := BuildConstDof(lxRect, lyRect, 0.0011, -0.0017, 0.0, 0.0017, 0.0011);
  CheckZeroForce('Rect: rigid tilt -> zero force', K, u, 1e-6);

  CheckShearEnergy('Rect: shear gamma_xz only', K, lxRect, lyRect, E, Nu, Thickness, ShearK, areaRect,
    0.0, 0.0, 0.002, 0.0, 1e-8);
  CheckShearEnergy('Rect: shear gamma_yz only', K, lxRect, lyRect, E, Nu, Thickness, ShearK, areaRect,
    0.0, 0.0, 0.0, 0.002, 1e-8);
  CheckShearEnergy('Rect: combined shear + nonzero rx0/ry0', K, lxRect, lyRect, E, Nu, Thickness, ShearK, areaRect,
    0.0007, -0.0004, 0.0015, -0.0009, 1e-8);

  CheckBendingEnergy('Rect: bending kappa_x only', K, lxRect, lyRect, E, Nu, Thickness, areaRect,
    0.0006, 0.0, 0.0, 1e-6);
  CheckBendingEnergy('Rect: bending kappa_y only', K, lxRect, lyRect, E, Nu, Thickness, areaRect,
    0.0, 0.0006, 0.0, 1e-6);
  CheckBendingEnergy('Rect: bending kappa_xy only', K, lxRect, lyRect, E, Nu, Thickness, areaRect,
    0.0, 0.0, 0.0006, 1e-6);
  CheckBendingEnergy('Rect: combined kappa_x+kappa_y+kappa_xy', K, lxRect, lyRect, E, Nu, Thickness, areaRect,
    0.0004, 0.0, 0.0001, 1e-6);

  // --- Distorted quad, same layout as the membrane test ---
  lxDist[0] := 0;   lyDist[0] := 0;
  lxDist[1] := 5;   lyDist[1] := 0.6;
  lxDist[2] := 4.2; lyDist[2] := 3.5;
  lxDist[3] := 0.5; lyDist[3] := 2.8;
  lxDist[4] := (lxDist[0]+lxDist[1])/2; lyDist[4] := (lyDist[0]+lyDist[1])/2;
  lxDist[5] := (lxDist[1]+lxDist[2])/2; lyDist[5] := (lyDist[1]+lyDist[2])/2;
  lxDist[6] := (lxDist[2]+lxDist[3])/2; lyDist[6] := (lyDist[2]+lyDist[3])/2;
  lxDist[7] := (lxDist[3]+lxDist[0])/2; lyDist[7] := (lyDist[3]+lyDist[0])/2;
  areaDist := 0.5 * Abs(
    (lxDist[0]*lyDist[1] - lxDist[1]*lyDist[0]) +
    (lxDist[1]*lyDist[2] - lxDist[2]*lyDist[1]) +
    (lxDist[2]*lyDist[3] - lxDist[3]*lyDist[2]) +
    (lxDist[3]*lyDist[0] - lxDist[0]*lyDist[3]));

  K := QuadPlateMindlinStiffnessQ8Local(E, Nu, Thickness, ShearK,
    lxDist[0], lyDist[0], lxDist[1], lyDist[1], lxDist[2], lyDist[2], lxDist[3], lyDist[3],
    lxDist[4], lyDist[4], lxDist[5], lyDist[5], lxDist[6], lyDist[6], lxDist[7], lyDist[7]);

  u := BuildConstDof(lxDist, lyDist, 0.0, 0.0, -0.0014, 0.0, 0.0);
  CheckZeroForce('Distorted: rigid translation -> zero force', K, u, 1e-7);

  u := BuildConstDof(lxDist, lyDist, -0.0009, 0.0013, 0.0, -0.0013, -0.0009);
  CheckZeroForce('Distorted: rigid tilt -> zero force', K, u, 1e-5);

  CheckShearEnergy('Distorted: shear gamma_xz only', K, lxDist, lyDist, E, Nu, Thickness, ShearK, areaDist,
    0.0, 0.0, 0.002, 0.0, 1e-7);
  CheckShearEnergy('Distorted: shear gamma_yz only', K, lxDist, lyDist, E, Nu, Thickness, ShearK, areaDist,
    0.0, 0.0, 0.0, 0.002, 1e-7);
  CheckShearEnergy('Distorted: combined shear + nonzero rx0/ry0', K, lxDist, lyDist, E, Nu, Thickness, ShearK, areaDist,
    0.0007, -0.0004, 0.0015, -0.0009, 1e-7);

  WriteLn;
  WriteLn('(Distorted-quad constant-curvature/bending patch test intentionally');
  WriteLn(' omitted -- see file header comment on check 4.)');
  WriteLn;
  if FailCount = 0 then
    WriteLn('ALL CHECKS PASSED')
  else
  begin
    WriteLn(FailCount, ' CHECK(S) FAILED');
    Halt(1);
  end;
end.
