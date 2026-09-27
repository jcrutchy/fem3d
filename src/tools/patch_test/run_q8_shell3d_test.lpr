program run_q8_shell3d_test;

// Standalone verification for fem_elements.QuadShellStiffnessQ8_3D.
// The LOCAL (flat, z=0) combiner is already patch-test verified
// (run_q8_shell_test.lpr). What's new here is the local-to-global
// transform T itself: build the SAME rectangle, but rotated by an
// arbitrary rotation and translated in 3D, and re-run the same
// rigid-body checks (translation, rotation about the element's own
// local x/y, drilling isolation about local z) -- this time deriving
// the local frame from the ACTUAL rotated corner coordinates, the same
// way QuadShellStiffnessQ8_3D does internally, and the same way the
// project's own Shell Case S check does for shellq4
// (run_patch_test.lpr's CheckShellRigidBody), generalized from 4
// nodes/24 dof to 8 nodes/48 dof.
//
// Run with: ./run_q8_shell3d_test  (exit code 0 = all checks passed)

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

function ShellRigidTranslationDofsQ8(dx, dy, dz: Double): TDoubleArray;
var
  blk: Integer;
begin
  SetLength(Result, 49);
  for blk := 0 to 7 do
  begin
    Result[6*blk+1] := dx; Result[6*blk+2] := dy; Result[6*blk+3] := dz;
    Result[6*blk+4] := 0;  Result[6*blk+5] := 0;  Result[6*blk+6] := 0;
  end;
end;

function ShellRigidRotationDofsQ8(const nx, ny, nz: array of Double;
  px, py, pz, ox, oy, oz: Double): TDoubleArray;
var
  blk: Integer;
  rx, ry, rz: Double;
begin
  SetLength(Result, 49);
  for blk := 0 to 7 do
  begin
    rx := nx[blk] - px; ry := ny[blk] - py; rz := nz[blk] - pz;
    Result[6*blk+1] := oy*rz - oz*ry;
    Result[6*blk+2] := oz*rx - ox*rz;
    Result[6*blk+3] := ox*ry - oy*rx;
    Result[6*blk+4] := ox;
    Result[6*blk+5] := oy;
    Result[6*blk+6] := oz;
  end;
end;

function VecNorm3(x, y, z: Double): Double;
begin
  Result := Sqrt(x*x + y*y + z*z);
end;

procedure CheckShellRigidBodyQ8_3D(const CaseName: string; const K: TElemMatrix;
  const nx, ny, nz: array of Double; BendZeroTol: Double);
var
  u, F: TDoubleArray;
  edge1, edge2, ex, ey, ez: array[0..2] of Double;
  norm1, norm2: Double;
  i, blk: Integer;
  maxF, maxOffDiag: Double;

  procedure OneCase(const Label_: string; const uu: TDoubleArray; Tol: Double);
  var
    ii: Integer;
  begin
    F := MatVecN(K, uu, 48);
    maxF := 0;
    for ii := 1 to 48 do
      if Abs(F[ii]) > maxF then maxF := Abs(F[ii]);
    Check(CaseName + ': shell rigid-body (' + Label_ + ') -> zero force',
      ApproxZero(maxF, Tol), Format('max |F| = %g (tol %g)', [maxF, Tol]));
  end;

begin
  u := ShellRigidTranslationDofsQ8(1.0, 0.0, 0.0); OneCase('translate x', u, 1.0E-6*(Abs(K[1,1])+1.0));
  u := ShellRigidTranslationDofsQ8(0.0, 1.0, 0.0); OneCase('translate y', u, 1.0E-6*(Abs(K[1,1])+1.0));
  u := ShellRigidTranslationDofsQ8(0.0, 0.0, 1.0); OneCase('translate z', u, 1.0E-6*(Abs(K[1,1])+1.0));

  // Local frame from CORNER nodes 1 (index 0), 2 (index 1), 4 (index 3)
  // -- same construction QuadShellStiffnessQ8_3D uses internally.
  edge1[0] := nx[1]-nx[0]; edge1[1] := ny[1]-ny[0]; edge1[2] := nz[1]-nz[0];
  edge2[0] := nx[3]-nx[0]; edge2[1] := ny[3]-ny[0]; edge2[2] := nz[3]-nz[0];
  norm1 := VecNorm3(edge1[0], edge1[1], edge1[2]);
  ex[0] := edge1[0]/norm1; ex[1] := edge1[1]/norm1; ex[2] := edge1[2]/norm1;
  ez[0] := edge1[1]*edge2[2] - edge1[2]*edge2[1];
  ez[1] := edge1[2]*edge2[0] - edge1[0]*edge2[2];
  ez[2] := edge1[0]*edge2[1] - edge1[1]*edge2[0];
  norm2 := VecNorm3(ez[0], ez[1], ez[2]);
  ez[0] := ez[0]/norm2; ez[1] := ez[1]/norm2; ez[2] := ez[2]/norm2;
  ey[0] := ez[1]*ex[2] - ez[2]*ex[1];
  ey[1] := ez[2]*ex[0] - ez[0]*ex[2];
  ey[2] := ez[0]*ex[1] - ez[1]*ex[0];

  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], ex[0], ex[1], ex[2]);
  OneCase('rotate about local x through node 1', u, BendZeroTol);
  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], ey[0], ey[1], ey[2]);
  OneCase('rotate about local y through node 1', u, BendZeroTol);

  // Drilling axis: force must be zero on every translation dof, and
  // the moment, projected back onto the LOCAL frame, must be zero
  // about local x/y (local z / drilling is allowed to react).
  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], ez[0], ez[1], ez[2]);
  F := MatVecN(K, u, 48);
  maxOffDiag := 0;
  for blk := 0 to 7 do
  begin
    for i := 1 to 3 do
      if Abs(F[6*blk+i]) > maxOffDiag then maxOffDiag := Abs(F[6*blk+i]);
    if Abs(ex[0]*F[6*blk+4] + ex[1]*F[6*blk+5] + ex[2]*F[6*blk+6]) > maxOffDiag then
      maxOffDiag := Abs(ex[0]*F[6*blk+4] + ex[1]*F[6*blk+5] + ex[2]*F[6*blk+6]);
    if Abs(ey[0]*F[6*blk+4] + ey[1]*F[6*blk+5] + ey[2]*F[6*blk+6]) > maxOffDiag then
      maxOffDiag := Abs(ey[0]*F[6*blk+4] + ey[1]*F[6*blk+5] + ey[2]*F[6*blk+6]);
  end;
  Check(CaseName + ': shell rigid-body (rotate about local z / drilling) -> zero coupling into real dof',
    ApproxZero(maxOffDiag, BendZeroTol),
    Format('max |F| on non-drilling components (local frame) = %g (tol %g)', [maxOffDiag, BendZeroTol]));
end;

var
  K: TElemMatrix;
  E, Nu, Thickness, ShearK, DrillFactor: Double;
  lxRect, lyRect: array[0..7] of Double;
  gx, gy, gz: array[0..7] of Double;
  R: array[0..2, 0..2] of Double; // fixed rotation matrix (30 deg about axis (1,1,1)/sqrt(3))
  tx, ty, tz: Double;
  i: Integer;
  c, s, t, ux, uy, uz, n: Double;

begin
  FailCount := 0;
  E := 210000.0;
  Nu := 0.3;
  Thickness := 5.0;
  ShearK := 5.0 / 6.0;
  DrillFactor := 1.0E-3;

  lxRect[0] := 0; lyRect[0] := 0;
  lxRect[1] := 4; lyRect[1] := 0;
  lxRect[2] := 4; lyRect[2] := 2;
  lxRect[3] := 0; lyRect[3] := 2;
  lxRect[4] := 2; lyRect[4] := 0;
  lxRect[5] := 4; lyRect[5] := 1;
  lxRect[6] := 2; lyRect[6] := 2;
  lxRect[7] := 0; lyRect[7] := 1;

  // Rodrigues' rotation formula: 40 degrees about axis (1,1,1)/sqrt(3).
  n := Sqrt(3.0);
  ux := 1.0/n; uy := 1.0/n; uz := 1.0/n;
  c := Cos(40.0 * Pi / 180.0);
  s := Sin(40.0 * Pi / 180.0);
  t := 1.0 - c;
  R[0,0] := t*ux*ux + c;      R[0,1] := t*ux*uy - s*uz;   R[0,2] := t*ux*uz + s*uy;
  R[1,0] := t*ux*uy + s*uz;   R[1,1] := t*uy*uy + c;      R[1,2] := t*uy*uz - s*ux;
  R[2,0] := t*ux*uz - s*uy;   R[2,1] := t*uy*uz + s*ux;   R[2,2] := t*uz*uz + c;

  tx := 3.5; ty := -2.1; tz := 7.3; // arbitrary translation

  for i := 0 to 7 do
  begin
    // local (lx,ly,0) -> rotated+translated global (gx,gy,gz)
    gx[i] := R[0,0]*lxRect[i] + R[0,1]*lyRect[i] + tx;
    gy[i] := R[1,0]*lxRect[i] + R[1,1]*lyRect[i] + ty;
    gz[i] := R[2,0]*lxRect[i] + R[2,1]*lyRect[i] + tz;
  end;

  K := QuadShellStiffnessQ8_3D(E, Nu, Thickness, ShearK, DrillFactor,
    gx[0],gy[0],gz[0], gx[1],gy[1],gz[1], gx[2],gy[2],gz[2], gx[3],gy[3],gz[3],
    gx[4],gy[4],gz[4], gx[5],gy[5],gz[5], gx[6],gy[6],gz[6], gx[7],gy[7],gz[7]);

  CheckShellRigidBodyQ8_3D('Rotated+translated rect (global)', K, gx, gy, gz, 1.0E-3);

  WriteLn;
  if FailCount = 0 then
    WriteLn('ALL CHECKS PASSED')
  else
  begin
    WriteLn(FailCount, ' CHECK(S) FAILED');
    Halt(1);
  end;
end.
