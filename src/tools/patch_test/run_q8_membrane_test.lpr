program run_q8_membrane_test;

// Standalone verification for fem_elements.QuadMembraneStiffnessQ8Local,
// same spirit as run_patch_test.lpr's checks for the Q4 membrane element:
//   1. Rigid-body translation invariance: translating all 8 nodes by the
//      same (dx, dy) must produce exactly zero nodal force.
//   2. Constant-strain patch test, via strain energy: prescribe nodal
//      displacements matching an EXACT constant-strain field (uniaxial,
//      then combined biaxial + shear), compute U = 0.5 * u^T K u, and
//      check it against the closed-form 0.5 * strain^T D strain * Area *
//      Thickness. Run on both an axis-aligned rectangle and a genuinely
//      distorted (non-rectangular, non-parallelogram) quad with curved-
//      looking but still-exact-quadratic-consistent midside placement,
//      to confirm the isoparametric mapping holds up off the easy case.
//
// Run with: ./run_q8_membrane_test  (exit code 0 = all checks passed)

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

function StrainEnergy(const K: TElemMatrix; const u: array of Double; N: Integer): Double;
var
  F: TDoubleArray;
  i: Integer;
begin
  F := MatVecN(K, u, N);
  Result := 0;
  for i := 1 to N do
    Result := Result + 0.5 * u[i] * F[i];
end;

procedure CheckRigidTranslation(const CaseName: string; const K: TElemMatrix;
  dx, dy: Double; Tol: Double);
var
  u: TDoubleArray;
  F: TDoubleArray;
  i, n: Integer;
  maxF: Double;
begin
  SetLength(u, 17);
  for n := 0 to 7 do
  begin
    u[2 * n + 1] := dx;
    u[2 * n + 2] := dy;
  end;
  F := MatVecN(K, u, 16);
  maxF := 0;
  for i := 1 to 16 do
    if Abs(F[i]) > maxF then maxF := Abs(F[i]);
  Check(CaseName + ': rigid translation -> zero force', ApproxZero(maxF, Tol),
    Format('max |F| = %g (tol %g)', [maxF, Tol]));
end;

// Applies nodal dof for the EXACT displacement field
//   u(x,y) = ex*x + 0.5*gxy*y
//   v(x,y) = ey*y + 0.5*gxy*x
// (constant strain: exx=ex, eyy=ey, gxy=gxy everywhere), then checks the
// resulting strain energy against the closed-form 0.5*strain^T*D*strain*
// Area*Thickness.
procedure CheckConstantStrainEnergy(const CaseName: string;
  const K: TElemMatrix; E, Nu, Thickness, Area: Double;
  const lx, ly: array of Double; ex, ey, gxy: Double; Tol: Double);
var
  u: TDoubleArray;
  n: Integer;
  cE, D11, D12, D33: Double;
  strainEnergyDensity, closedForm, computed: Double;
begin
  SetLength(u, 17);
  for n := 0 to 7 do
  begin
    u[2 * n + 1] := ex * lx[n] + 0.5 * gxy * ly[n];
    u[2 * n + 2] := ey * ly[n] + 0.5 * gxy * lx[n];
  end;

  cE := E / (1.0 - Nu * Nu);
  D11 := cE; D12 := cE * Nu; D33 := cE * (1.0 - Nu) / 2.0;
  // 0.5 * [ex ey gxy] * D * [ex ey gxy]^T
  strainEnergyDensity := 0.5 * (D11 * ex * ex + D11 * ey * ey +
    2 * D12 * ex * ey + D33 * gxy * gxy);
  closedForm := strainEnergyDensity * Area * Thickness;

  computed := StrainEnergy(K, u, 16);
  Check(CaseName, ApproxEqual(computed, closedForm, Tol),
    Format('computed U = %g, closed-form U = %g', [computed, closedForm]));
end;

var
  K: TElemMatrix;
  E, Nu, Thickness: Double;
  lxRect, lyRect: array[0..7] of Double;
  lxDist, lyDist: array[0..7] of Double;
  areaRect, areaDist: Double;

begin
  FailCount := 0;
  E := 210000.0; // MPa, arbitrary steel-ish value
  Nu := 0.3;
  Thickness := 5.0;

  // --- Case A: axis-aligned 4x2 rectangle, corners CCW from (0,0),
  //     midside nodes at exact edge midpoints. ---
  lxRect[0] := 0; lyRect[0] := 0;   // node 1
  lxRect[1] := 4; lyRect[1] := 0;   // node 2
  lxRect[2] := 4; lyRect[2] := 2;   // node 3
  lxRect[3] := 0; lyRect[3] := 2;   // node 4
  lxRect[4] := 2; lyRect[4] := 0;   // node 5 (mid 1-2)
  lxRect[5] := 4; lyRect[5] := 1;   // node 6 (mid 2-3)
  lxRect[6] := 2; lyRect[6] := 2;   // node 7 (mid 3-4)
  lxRect[7] := 0; lyRect[7] := 1;   // node 8 (mid 4-1)
  areaRect := 4.0 * 2.0;

  K := QuadMembraneStiffnessQ8Local(E, Nu, Thickness,
    lxRect[0], lyRect[0], lxRect[1], lyRect[1], lxRect[2], lyRect[2], lxRect[3], lyRect[3],
    lxRect[4], lyRect[4], lxRect[5], lyRect[5], lxRect[6], lyRect[6], lxRect[7], lyRect[7]);

  CheckRigidTranslation('Rect', K, 0.0013, -0.0027, 1e-8);
  CheckConstantStrainEnergy('Rect: uniaxial ex', K, E, Nu, Thickness, areaRect,
    lxRect, lyRect, 0.001, 0.0, 0.0, 1e-9);
  CheckConstantStrainEnergy('Rect: uniaxial ey', K, E, Nu, Thickness, areaRect,
    lxRect, lyRect, 0.0, 0.001, 0.0, 1e-9);
  CheckConstantStrainEnergy('Rect: pure shear', K, E, Nu, Thickness, areaRect,
    lxRect, lyRect, 0.0, 0.0, 0.001, 1e-9);
  CheckConstantStrainEnergy('Rect: combined ex+ey+gxy', K, E, Nu, Thickness, areaRect,
    lxRect, lyRect, 0.0008, -0.0004, 0.0006, 1e-9);

  // --- Case B: genuinely distorted (non-rectangular, non-parallelogram)
  //     quad, midside nodes at exact edge midpoints of the DISTORTED
  //     edges (required for the element to stay isoparametrically
  //     consistent -- a midside node NOT at the true edge midpoint
  //     changes the element's shape, not just its regularity). ---
  lxDist[0] := 0;   lyDist[0] := 0;     // node 1
  lxDist[1] := 5;   lyDist[1] := 0.6;   // node 2
  lxDist[2] := 4.2; lyDist[2] := 3.5;   // node 3
  lxDist[3] := 0.5; lyDist[3] := 2.8;   // node 4
  lxDist[4] := (lxDist[0]+lxDist[1])/2; lyDist[4] := (lyDist[0]+lyDist[1])/2; // mid 1-2
  lxDist[5] := (lxDist[1]+lxDist[2])/2; lyDist[5] := (lyDist[1]+lyDist[2])/2; // mid 2-3
  lxDist[6] := (lxDist[2]+lxDist[3])/2; lyDist[6] := (lyDist[2]+lyDist[3])/2; // mid 3-4
  lxDist[7] := (lxDist[3]+lxDist[0])/2; lyDist[7] := (lyDist[3]+lyDist[0])/2; // mid 4-1
  areaDist := 0.5 * Abs(
    (lxDist[0]*lyDist[1] - lxDist[1]*lyDist[0]) +
    (lxDist[1]*lyDist[2] - lxDist[2]*lyDist[1]) +
    (lxDist[2]*lyDist[3] - lxDist[3]*lyDist[2]) +
    (lxDist[3]*lyDist[0] - lxDist[0]*lyDist[3]));

  K := QuadMembraneStiffnessQ8Local(E, Nu, Thickness,
    lxDist[0], lyDist[0], lxDist[1], lyDist[1], lxDist[2], lyDist[2], lxDist[3], lyDist[3],
    lxDist[4], lyDist[4], lxDist[5], lyDist[5], lxDist[6], lyDist[6], lxDist[7], lyDist[7]);

  CheckRigidTranslation('Distorted', K, -0.0021, 0.0016, 1e-8);
  CheckConstantStrainEnergy('Distorted: uniaxial ex', K, E, Nu, Thickness, areaDist,
    lxDist, lyDist, 0.001, 0.0, 0.0, 1e-8);
  CheckConstantStrainEnergy('Distorted: uniaxial ey', K, E, Nu, Thickness, areaDist,
    lxDist, lyDist, 0.0, 0.001, 0.0, 1e-8);
  CheckConstantStrainEnergy('Distorted: pure shear', K, E, Nu, Thickness, areaDist,
    lxDist, lyDist, 0.0, 0.0, 0.001, 1e-8);
  CheckConstantStrainEnergy('Distorted: combined ex+ey+gxy', K, E, Nu, Thickness, areaDist,
    lxDist, lyDist, 0.0008, -0.0004, 0.0006, 1e-8);

  WriteLn;
  if FailCount = 0 then
    WriteLn('ALL CHECKS PASSED')
  else
  begin
    WriteLn(FailCount, ' CHECK(S) FAILED');
    Halt(1);
  end;
end.
