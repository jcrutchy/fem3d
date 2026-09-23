program run_patch_test;

// Standalone verification for fem_elements.QuadMembraneStiffness3D and
// QuadBendingStiffnessLocal -- neither is wired into fem_regress yet
// (the elements themselves aren't wired into the model/solver pipeline
// yet either -- see the comments on each function). Checks are all
// derived from first principles rather than compared against another
// tool's output:
//
// Membrane (QuadMembraneStiffness3D):
//   1. Rigid-body translation invariance: translating all 4 nodes by
//      the same vector must produce exactly zero nodal force, for ANY
//      valid strain-based element stiffness matrix, in ANY orientation.
//      This is the single check most likely to catch a bug in the
//      local-basis (ex/ey/ez) or transform (T) construction, which is
//      exactly the new code specific to a 3D (non-axis-aligned) quad.
//   2. Constant-strain patch test: prescribe a linear displacement
//      field (u = strain_x * x, v = 0) at all 4 nodes, compute
//      F = Ke * u, and check the resultant force on each pair of
//      edge nodes against the closed-form consistent nodal force for
//      a uniform traction on a 2-node linear edge (exactly half the
//      edge's total force at each end node -- elementary, not
//      something that needs an external reference).
//
// DKQ bending (QuadBendingStiffnessLocal):
//   3. Zero-curvature ("rigid tilt") invariance: any exactly-flat,
//      exactly-linear w field (uniform w, or w = alpha*x + beta*y) has
//      zero curvature everywhere and so must produce exactly zero
//      nodal force -- analogous to the membrane translation check.
//   4. Constant-curvature patch test: prescribe nodal dof matching an
//      exact constant-curvature field (kappa_xx, kappa_yy, or twist
//      kappa_xy held constant), and check the element's strain energy
//      against the closed-form 0.5*kappa^2*D*Area exactly -- this is
//      THE defining property a conforming thin-plate element must have
//      (and the specific property that separates DKQ from the simpler,
//      non-conforming ACM element on non-rectangular shapes), checked
//      on an axis-aligned case AND on a genuinely distorted quad.
//
// Run with: ./bin/run_patch_test  (exit code 0 = all checks passed)

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

function ApproxZero(V: Double; Tol: Double): Boolean;
begin
  Result := Abs(V) <= Tol;
end;

// Multiply a 12x12 TElemMatrix by a 12-vector (1-based).
function MatVec(const K: TElemMatrix; const u: array of Double): TDoubleArray;
var
  i, j: Integer;
begin
  SetLength(Result, 13);
  for i := 1 to 12 do
  begin
    Result[i] := 0;
    for j := 1 to 12 do
      Result[i] := Result[i] + K[i, j] * u[j];
  end;
end;

procedure CheckRigidTranslation(const CaseName: string; const K: TElemMatrix;
  dx, dy, dz: Double; Tol: Double);
var
  u, F: TDoubleArray;
  i, blk: Integer;
  maxF: Double;
begin
  SetLength(u, 13);
  for blk := 0 to 3 do
  begin
    u[3 * blk + 1] := dx;
    u[3 * blk + 2] := dy;
    u[3 * blk + 3] := dz;
  end;
  F := MatVec(K, u);
  maxF := 0;
  for i := 1 to 12 do
    if Abs(F[i]) > maxF then maxF := Abs(F[i]);
  Check(CaseName + ': rigid translation -> zero force', ApproxZero(maxF, Tol),
    Format('max |F| = %g (tol %g)', [maxF, Tol]));
end;

function PolygonArea(x1, y1, x2, y2, x3, y3, x4, y4: Double): Double;
begin
  // Shoelace formula, general planar quad, nodes in order.
  Result := 0.5 * Abs(
    (x1*y2 - x2*y1) + (x2*y3 - x3*y2) + (x3*y4 - x4*y3) + (x4*y1 - x1*y4));
end;

function Energy(const K: TElemMatrix; const u: TDoubleArray): Double;
var
  Ku: TDoubleArray;
  i: Integer;
  s: Double;
begin
  Ku := MatVec(K, u);
  s := 0;
  for i := 1 to 12 do
    s := s + u[i] * Ku[i];
  Result := 0.5 * s;
end;

// Local DKQ dof order per node: [w, w_x, w_y]. Builds a TDoubleArray
// sized for MatVec (13 elements, 1-based use of indices 1..12).
function DkqDofsTilt(x1, y1, x2, y2, x3, y3, x4, y4, alpha, beta: Double): TDoubleArray;
var
  px, py: array[1..4] of Double;
  i: Integer;
begin
  px[1]:=x1; py[1]:=y1; px[2]:=x2; py[2]:=y2;
  px[3]:=x3; py[3]:=y3; px[4]:=x4; py[4]:=y4;
  SetLength(Result, 13);
  for i := 1 to 4 do
  begin
    Result[3*(i-1)+1] := alpha*px[i] + beta*py[i]; // w  (exact plane: zero curvature)
    Result[3*(i-1)+2] := alpha;                     // w_x
    Result[3*(i-1)+3] := beta;                      // w_y
  end;
end;

function DkqDofsKappaXX(x1, y1, x2, y2, x3, y3, x4, y4, c: Double): TDoubleArray;
var
  px, py: array[1..4] of Double;
  i: Integer;
begin
  px[1]:=x1; py[1]:=y1; px[2]:=x2; py[2]:=y2;
  px[3]:=x3; py[3]:=y3; px[4]:=x4; py[4]:=y4;
  SetLength(Result, 13);
  for i := 1 to 4 do
  begin
    Result[3*(i-1)+1] := 0.5*c*px[i]*px[i]; // w = c/2 * x^2 -> kappa_xx = c
    Result[3*(i-1)+2] := c*px[i];            // w_x
    Result[3*(i-1)+3] := 0;                  // w_y
  end;
end;

function DkqDofsKappaYY(x1, y1, x2, y2, x3, y3, x4, y4, c: Double): TDoubleArray;
var
  px, py: array[1..4] of Double;
  i: Integer;
begin
  px[1]:=x1; py[1]:=y1; px[2]:=x2; py[2]:=y2;
  px[3]:=x3; py[3]:=y3; px[4]:=x4; py[4]:=y4;
  SetLength(Result, 13);
  for i := 1 to 4 do
  begin
    Result[3*(i-1)+1] := 0.5*c*py[i]*py[i]; // w = c/2 * y^2 -> kappa_yy = c
    Result[3*(i-1)+2] := 0;
    Result[3*(i-1)+3] := c*py[i];
  end;
end;

function DkqDofsTwist(x1, y1, x2, y2, x3, y3, x4, y4, c: Double): TDoubleArray;
var
  px, py: array[1..4] of Double;
  i: Integer;
begin
  px[1]:=x1; py[1]:=y1; px[2]:=x2; py[2]:=y2;
  px[3]:=x3; py[3]:=y3; px[4]:=x4; py[4]:=y4;
  SetLength(Result, 13);
  for i := 1 to 4 do
  begin
    Result[3*(i-1)+1] := c*px[i]*py[i]; // w = c*x*y -> 2*kappa_xy = 2c
    Result[3*(i-1)+2] := c*py[i];        // w_x = c*y
    Result[3*(i-1)+3] := c*px[i];        // w_y = c*x
  end;
end;

procedure CheckDkqZeroCurvature(const CaseName: string;
  x1, y1, x2, y2, x3, y3, x4, y4, E, Nu, T: Double);
var
  Kb: TElemMatrix;
  u, F: TDoubleArray;
  maxF: Double;

  procedure OneTilt(const Label_: string; alpha, beta: Double);
  var
    ii: Integer;
  begin
    u := DkqDofsTilt(x1, y1, x2, y2, x3, y3, x4, y4, alpha, beta);
    F := MatVec(Kb, u);
    maxF := 0;
    for ii := 1 to 12 do
      if Abs(F[ii]) > maxF then maxF := Abs(F[ii]);
    Check(CaseName + ': DKQ zero-curvature (' + Label_ + ') -> zero force',
      ApproxZero(maxF, (Abs(E) + 1.0) * 1.0E-6),
      Format('max |F| = %g', [maxF]));
  end;

begin
  Kb := QuadBendingStiffnessLocal(E, Nu, T, x1, y1, x2, y2, x3, y3, x4, y4);
  OneTilt('flat, w=0',        0.0, 0.0);
  OneTilt('x-tilt',           0.7, 0.0);
  OneTilt('y-tilt',           0.0, -0.4);
  OneTilt('combined tilt',    0.5, 0.3);
end;

procedure CheckDkqConstantCurvature(const CaseName: string;
  x1, y1, x2, y2, x3, y3, x4, y4, E, Nu, T, c: Double);
var
  Kb: TElemMatrix;
  Area, Dfac, D11, D33: Double;
  u: TDoubleArray;
  Uxx, Uyy, Uxy, expXX, expYY, expXY: Double;
begin
  Kb := QuadBendingStiffnessLocal(E, Nu, T, x1, y1, x2, y2, x3, y3, x4, y4);
  Area := PolygonArea(x1, y1, x2, y2, x3, y3, x4, y4);
  Dfac := (T*T*T / 12.0) * (E / (1.0 - Nu*Nu));
  D11 := Dfac;
  D33 := Dfac * (1.0 - Nu) / 2.0;

  u := DkqDofsKappaXX(x1, y1, x2, y2, x3, y3, x4, y4, c);
  Uxx := Energy(Kb, u);
  expXX := 0.5 * c * c * D11 * Area;
  Check(CaseName + ': DKQ constant-curvature patch test (kappa_xx)',
    ApproxZero(Uxx - expXX, Abs(expXX) * 1.0E-6 + 1.0E-9),
    Format('U_FE=%g, U_exact=%g', [Uxx, expXX]));

  u := DkqDofsKappaYY(x1, y1, x2, y2, x3, y3, x4, y4, c);
  Uyy := Energy(Kb, u);
  expYY := 0.5 * c * c * D11 * Area; // D22 = D11 by isotropy
  Check(CaseName + ': DKQ constant-curvature patch test (kappa_yy)',
    ApproxZero(Uyy - expYY, Abs(expYY) * 1.0E-6 + 1.0E-9),
    Format('U_FE=%g, U_exact=%g', [Uyy, expYY]));

  u := DkqDofsTwist(x1, y1, x2, y2, x3, y3, x4, y4, c);
  Uxy := Energy(Kb, u);
  expXY := 0.5 * (2.0*c) * (2.0*c) * D33 * Area; // curvature_3 = 2*kappa_xy = 2c
  Check(CaseName + ': DKQ constant-curvature patch test (twist kappa_xy)',
    ApproxZero(Uxy - expXY, Abs(expXY) * 1.0E-6 + 1.0E-9),
    Format('U_FE=%g, U_exact=%g', [Uxy, expXY]));
end;

const
  // Case A: unit square, axis-aligned in the global XY plane, E=1,
  // nu=0 -- simplest possible reference case (no Poisson coupling).
  A_L = 1.0; A_W = 1.0; A_E = 1.0; A_Nu = 0.0; A_T = 1.0;

  // Case B: a realistic rectangle, axis-aligned -- used for the
  // constant-strain patch test since sigma_y (Poisson coupling) is
  // nonzero and worth checking.
  B_L = 2.0; B_W = 1.0; B_E = 200.0E9; B_Nu = 0.3; B_T = 0.05;

var
  KA, KB, KC: TElemMatrix;
  strainX, sigmaX, sigmaY, cE: Double;
  uB: TDoubleArray;
  FB: TDoubleArray;
  Fx23, Fx14, Fy12, Fy43: Double;
  expFxEdge, expFyEdge: Double;
  // Case C: same rectangle as B, but rotated by an arbitrary rotation
  // and translated off the origin -- exercises the local-basis/transform
  // logic that an axis-aligned case can't (there ex=global X trivially).
  Rot: array[0..2, 0..2] of Double;
  Rz: array[0..2, 0..2] of Double;
  Rx: array[0..2, 0..2] of Double;
  Cx, Cy, Cz: Double;
  Bnodes: array[1..4, 0..2] of Double;
  Cnodes: array[1..4, 0..2] of Double;
  th1, th2: Double;
  i, j, k: Integer;
  uC: TDoubleArray;
  FC: TDoubleArray;
  dirX: array[0..2] of Double; // global direction that was local +x in case B
  FxAlongDirC_23, FxAlongDirC_14: Double;
begin
  FailCount := 0;

  // --- Case A ---
  KA := QuadMembraneStiffness3D(A_E, A_Nu, A_T,
    0, 0, 0,  A_L, 0, 0,  A_L, A_W, 0,  0, A_W, 0);
  CheckRigidTranslation('Case A (unit square)', KA, 1.0, 0.0, 0.0, 1.0E-9);
  CheckRigidTranslation('Case A (unit square)', KA, 0.0, 1.0, 0.0, 1.0E-9);
  CheckRigidTranslation('Case A (unit square)', KA, 0.3, -0.7, 0.0, 1.0E-9);

  strainX := 0.001;

  // --- Case B: axis-aligned rectangle, nu=0.3, x-extension patch test ---
  KB := QuadMembraneStiffness3D(B_E, B_Nu, B_T,
    0, 0, 0,  B_L, 0, 0,  B_L, B_W, 0,  0, B_W, 0);
  CheckRigidTranslation('Case B (rectangle)', KB, 1.0, 0.0, 0.0, 1.0E-3);
  CheckRigidTranslation('Case B (rectangle)', KB, 0.0, 1.0, 0.0, 1.0E-3);
  CheckRigidTranslation('Case B (rectangle)', KB, -0.4, 0.9, 0.0, 1.0E-3);

  cE := B_E / (1.0 - B_Nu * B_Nu);
  sigmaX := cE * strainX;
  sigmaY := cE * B_Nu * strainX;

  SetLength(uB, 13);
  for i := 1 to 12 do uB[i] := 0;
  // node order: 1,2,3,4 ; dof order per node x,y,z ; u = strainX * x, v = 0
  uB[1]  := strainX * 0;    // node1 x
  uB[4]  := strainX * B_L;  // node2 x
  uB[7]  := strainX * B_L;  // node3 x
  uB[10] := strainX * 0;    // node4 x
  // all y,z entries already 0

  FB := MatVec(KB, uB);

  // Edge 2-3 (x=L): expected total F_x = +sigmaX * W * t, split evenly
  // between the two edge nodes (linear shape functions on a 2-node edge).
  Fx23 := FB[4] + FB[7];
  expFxEdge := sigmaX * B_W * B_T;
  Check('Case B: F_x resultant on loaded edge (2-3)',
    ApproxZero(Fx23 - expFxEdge, Abs(expFxEdge) * 1.0E-9 + 1.0),
    Format('got %g, expected %g', [Fx23, expFxEdge]));

  // Edge 1-4 (x=0): expected total F_x = -sigmaX * W * t.
  Fx14 := FB[1] + FB[10];
  Check('Case B: F_x resultant on fixed edge (1-4)',
    ApproxZero(Fx14 - (-expFxEdge), Abs(expFxEdge) * 1.0E-9 + 1.0),
    Format('got %g, expected %g', [Fx14, -expFxEdge]));

  // Edge 1-2 (y=0): expected total F_y = -sigmaY * L * t (reaction
  // holding the Poisson-contraction-prevented edge at v=0).
  Fy12 := FB[2] + FB[5];
  expFyEdge := sigmaY * B_L * B_T;
  Check('Case B: F_y resultant on y=0 edge (1-2)',
    ApproxZero(Fy12 - (-expFyEdge), Abs(expFyEdge) * 1.0E-9 + 1.0),
    Format('got %g, expected %g', [Fy12, -expFyEdge]));

  // Edge 4-3 (y=W): expected total F_y = +sigmaY * L * t.
  Fy43 := FB[11] + FB[8];
  Check('Case B: F_y resultant on y=W edge (4-3)',
    ApproxZero(Fy43 - expFyEdge, Abs(expFyEdge) * 1.0E-9 + 1.0),
    Format('got %g, expected %g', [Fy43, expFyEdge]));

  // F_z should be exactly zero everywhere (planar in-plane problem).
  Check('Case B: F_z is zero at every node',
    ApproxZero(FB[3], 1.0E-6) and ApproxZero(FB[6], 1.0E-6) and
    ApproxZero(FB[9], 1.0E-6) and ApproxZero(FB[12], 1.0E-6),
    Format('F_z = [%g, %g, %g, %g]', [FB[3], FB[6], FB[9], FB[12]]));

  // --- Case C: same rectangle as B, but arbitrarily rotated + translated
  // in 3D, to specifically exercise QuadMembraneStiffness3D's local-basis
  // and transform logic (case A/B are both trivially axis-aligned, so
  // ex/ey/ez there could be wrong in a way that only shows up off-axis).
  Bnodes[1, 0] := 0;     Bnodes[1, 1] := 0;     Bnodes[1, 2] := 0;
  Bnodes[2, 0] := B_L;   Bnodes[2, 1] := 0;     Bnodes[2, 2] := 0;
  Bnodes[3, 0] := B_L;   Bnodes[3, 1] := B_W;   Bnodes[3, 2] := 0;
  Bnodes[4, 0] := 0;     Bnodes[4, 1] := B_W;   Bnodes[4, 2] := 0;

  // Rotation: 37 deg about Z, then 22 deg about the (rotated) X axis --
  // arbitrary, just not axis-aligned and not a multiple of 90 deg.
  th1 := 37.0 * Pi / 180.0;
  th2 := 22.0 * Pi / 180.0;
  begin
    // Rz(th1) then Rx(th2), composed: Rot = Rx(th2) * Rz(th1)
    Rz[0,0] := Cos(th1); Rz[0,1] := -Sin(th1); Rz[0,2] := 0;
    Rz[1,0] := Sin(th1); Rz[1,1] :=  Cos(th1); Rz[1,2] := 0;
    Rz[2,0] := 0;        Rz[2,1] := 0;         Rz[2,2] := 1;
    Rx[0,0] := 1; Rx[0,1] := 0;         Rx[0,2] := 0;
    Rx[1,0] := 0; Rx[1,1] := Cos(th2);  Rx[1,2] := -Sin(th2);
    Rx[2,0] := 0; Rx[2,1] := Sin(th2);  Rx[2,2] :=  Cos(th2);
    for i := 0 to 2 do
      for j := 0 to 2 do
      begin
        Rot[i, j] := 0;
        for k := 0 to 2 do
          Rot[i, j] := Rot[i, j] + Rx[i, k] * Rz[k, j];
      end;
  end;
  Cx := 5.0; Cy := -3.0; Cz := 2.0; // arbitrary translation

  for i := 1 to 4 do
    for j := 0 to 2 do
    begin
      Cnodes[i, j] := Cx * Ord(j = 0) + Cy * Ord(j = 1) + Cz * Ord(j = 2);
      for k := 0 to 2 do
        Cnodes[i, j] := Cnodes[i, j] + Rot[j, k] * Bnodes[i, k];
    end;

  KC := QuadMembraneStiffness3D(B_E, B_Nu, B_T,
    Cnodes[1,0], Cnodes[1,1], Cnodes[1,2],
    Cnodes[2,0], Cnodes[2,1], Cnodes[2,2],
    Cnodes[3,0], Cnodes[3,1], Cnodes[3,2],
    Cnodes[4,0], Cnodes[4,1], Cnodes[4,2]);

  CheckRigidTranslation('Case C (rotated rectangle)', KC, 1.0, 0.0, 0.0, 1.0E-3);
  CheckRigidTranslation('Case C (rotated rectangle)', KC, 0.0, 0.0, 1.0, 1.0E-3);
  CheckRigidTranslation('Case C (rotated rectangle)', KC, 0.6, -0.2, 0.8, 1.0E-3);

  // Same x-extension field as case B, but expressed in the rotated
  // frame: u_global = Rot * [strainX * x_local, 0, 0].
  dirX[0] := Rot[0,0]; dirX[1] := Rot[1,0]; dirX[2] := Rot[2,0]; // global dir of local +x

  SetLength(uC, 13);
  for i := 1 to 4 do
    for j := 0 to 2 do
    begin
      k := 3 * (i - 1) + j + 1;
      uC[k] := strainX * Bnodes[i, 0] * Rot[j, 0];
    end;

  FC := MatVec(KC, uC);

  // Resultant force on the "loaded edge" (nodes 2,3), projected onto the
  // global direction that corresponds to local +x, should still equal
  // sigmaX * W * t -- same physics, just expressed in a different global
  // orientation. This is the check that would fail if ex/ey/ez or T were
  // built incorrectly for a non-axis-aligned element.
  // Node i's global force vector occupies FC[3*(i-1)+1 .. 3*(i-1)+3].
  FxAlongDirC_23 := dirX[0] * (FC[4] + FC[7]) + dirX[1] * (FC[5] + FC[8]) + dirX[2] * (FC[6] + FC[9]);
  FxAlongDirC_14 := dirX[0] * (FC[1] + FC[10]) + dirX[1] * (FC[2] + FC[11]) + dirX[2] * (FC[3] + FC[12]);
  Check('Case C: rotated-frame F resultant along local +x, loaded edge',
    ApproxZero(FxAlongDirC_23 - expFxEdge, Abs(expFxEdge) * 1.0E-6 + 1.0),
    Format('got %g, expected %g', [FxAlongDirC_23, expFxEdge]));
  Check('Case C: rotated-frame F resultant along local +x, fixed edge',
    ApproxZero(FxAlongDirC_14 - (-expFxEdge), Abs(expFxEdge) * 1.0E-6 + 1.0),
    Format('got %g, expected %g', [FxAlongDirC_14, -expFxEdge]));

  // --- DKQ plate-bending checks ---
  // Case P: unit square, E=1, nu=0 -- simplest reference case.
  CheckDkqZeroCurvature('DKQ Case P (unit square)', 0,0, 1,0, 1,1, 0,1, 1.0, 0.0, 1.0);
  CheckDkqConstantCurvature('DKQ Case P (unit square)', 0,0, 1,0, 1,1, 0,1, 1.0, 0.0, 1.0, 0.01);

  // Case Q: realistic rectangle, nu=0.3.
  CheckDkqZeroCurvature('DKQ Case Q (rectangle)', 0,0, B_L,0, B_L,B_W, 0,B_W, B_E, B_Nu, B_T);
  CheckDkqConstantCurvature('DKQ Case Q (rectangle)', 0,0, B_L,0, B_L,B_W, 0,B_W, B_E, B_Nu, B_T, 0.01);

  // Case R: a genuinely distorted, non-rectangular quad -- the case
  // DKQ exists to handle correctly (unlike the simpler ACM rectangular
  // element). Passing the constant-curvature patch test here, exactly,
  // is the specific property that justified choosing DKQ over ACM.
  CheckDkqZeroCurvature('DKQ Case R (distorted quad)',
    0,0,  2,0,  2.3,1.4,  0.2,1.1,  B_E, B_Nu, B_T);
  CheckDkqConstantCurvature('DKQ Case R (distorted quad)',
    0,0,  2,0,  2.3,1.4,  0.2,1.1,  B_E, B_Nu, B_T, 0.01);

  WriteLn;
  if FailCount = 0 then
  begin
    WriteLn('All patch-test checks passed.');
    Halt(0);
  end
  else
  begin
    WriteLn(FailCount, ' check(s) FAILED.');
    Halt(1);
  end;
end.

