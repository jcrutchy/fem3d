program run_q8_shell_test;

// Standalone verification for fem_elements.QuadShellStiffnessQ8Local.
// The membrane and Mindlin-plate blocks are already independently
// patch-test verified (run_q8_membrane_test.lpr, run_q8_plate_test.lpr)
// for their own internal correctness. What's NEW and needs checking
// here is the ASSEMBLY: did the block-to-shell-dof offset wiring land
// right, with no cross-block leakage, and does the drilling penalty
// react only where it should? Same two-part rigid-body check the
// project already uses for shellq4 (run_patch_test.lpr's
// CheckShellRigidBody), generalized from 4 nodes/24 dof to 8 nodes/48
// dof, run on a LOCAL flat (z=0) element -- same "local case first"
// approach the shellq4 tests use before a global/3D-transformed case
// (which needs a QuadShellStiffnessQ8_3D wrapper this project doesn't
// have yet -- see QuadShellStiffnessQ8Local's interface comment).
//
//   1. Rigid translation (any of x/y/z): zero force. Trivial but
//      cheap to check directly rather than assume.
//   2. Rigid rotation about local x or local y (in-plane axes of this
//      flat element): must give exactly zero force -- confirms the
//      membrane block's [u,v] offsets and the plate block's [w,rx,ry]
//      offsets both landed in the right place in the 48x48, with no
//      scrambled indices, since either block's rigid-body invariance
//      (already proven standalone) would show up as nonzero force here
//      if the assembly wiring were wrong.
//   3. Rigid rotation about local z (the drilling axis): must couple
//      into ONLY the rz penalty dof, with exactly zero force on every
//      u/v/w/rx/ry dof -- confirms the drilling penalty was placed at
//      the right offset (7th dof would be a leftover from a botched
//      loop, say) and doesn't leak into the real element response.
//
// Run on both a flat rectangle and a flat (but non-rectangular)
// distorted quad, since the assembly logic itself doesn't depend on
// shape (only the already-separately-verified sub-blocks do).
//
// Run with: ./run_q8_shell_test  (exit code 0 = all checks passed)

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

// 8-node analog of the project's ShellRigidTranslationDofs: [u,v,w,rx,ry,rz]
// per node (48 total), rz=rx=ry=0, [u,v,w]=[dx,dy,dz] at every node.
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

// 8-node analog of ShellRigidRotationDofs: small-angle rigid rotation
// omega=(ox,oy,oz) about pivot (px,py,pz); translation_i = omega x
// (r_i-pivot), rotation_i = omega uniformly at every node.
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

procedure CheckShellRigidBodyQ8(const CaseName: string; const K: TElemMatrix;
  const nx, ny, nz: array of Double; BendZeroTol: Double);
var
  u, F: TDoubleArray;
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

  // Element is flat in the z=0 plane by construction (local formulation
  // called directly with z implicitly 0), so local x/y ARE global x/y
  // and local z IS global z -- no need to derive a local frame the way
  // the project's global/3D shellq4 check does.
  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], 1.0, 0.0, 0.0);
  OneCase('rotate about local x through node 1', u, BendZeroTol);
  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], 0.0, 1.0, 0.0);
  OneCase('rotate about local y through node 1', u, BendZeroTol);

  // Drilling axis: must couple into ONLY the rz penalty dof.
  u := ShellRigidRotationDofsQ8(nx, ny, nz, nx[0], ny[0], nz[0], 0.0, 0.0, 1.0);
  F := MatVecN(K, u, 48);
  maxOffDiag := 0;
  for blk := 0 to 7 do
    for i := 1 to 5 do // u,v,w,rx,ry -- NOT rz (offset 6), which is allowed to react
      if Abs(F[6*blk+i]) > maxOffDiag then maxOffDiag := Abs(F[6*blk+i]);
  Check(CaseName + ': shell rigid-body (rotate about local z / drilling) -> zero coupling into real dof',
    ApproxZero(maxOffDiag, BendZeroTol),
    Format('max |F| on non-drilling dof = %g (tol %g)', [maxOffDiag, BendZeroTol]));
end;

var
  K: TElemMatrix;
  E, Nu, Thickness, ShearK, DrillFactor: Double;
  lxRect, lyRect, zRect: array[0..7] of Double;
  lxDist, lyDist, zDist: array[0..7] of Double;
  i: Integer;

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
  for i := 0 to 7 do zRect[i] := 0.0;

  K := QuadShellStiffnessQ8Local(E, Nu, Thickness, ShearK, DrillFactor,
    lxRect[0], lyRect[0], lxRect[1], lyRect[1], lxRect[2], lyRect[2], lxRect[3], lyRect[3],
    lxRect[4], lyRect[4], lxRect[5], lyRect[5], lxRect[6], lyRect[6], lxRect[7], lyRect[7]);
  CheckShellRigidBodyQ8('Rect', K, lxRect, lyRect, zRect, 1.0E-6);

  lxDist[0] := 0;   lyDist[0] := 0;
  lxDist[1] := 5;   lyDist[1] := 0.6;
  lxDist[2] := 4.2; lyDist[2] := 3.5;
  lxDist[3] := 0.5; lyDist[3] := 2.8;
  lxDist[4] := (lxDist[0]+lxDist[1])/2; lyDist[4] := (lyDist[0]+lyDist[1])/2;
  lxDist[5] := (lxDist[1]+lxDist[2])/2; lyDist[5] := (lyDist[1]+lyDist[2])/2;
  lxDist[6] := (lxDist[2]+lxDist[3])/2; lyDist[6] := (lyDist[2]+lyDist[3])/2;
  lxDist[7] := (lxDist[3]+lxDist[0])/2; lyDist[7] := (lyDist[3]+lyDist[0])/2;
  for i := 0 to 7 do zDist[i] := 0.0;

  K := QuadShellStiffnessQ8Local(E, Nu, Thickness, ShearK, DrillFactor,
    lxDist[0], lyDist[0], lxDist[1], lyDist[1], lxDist[2], lyDist[2], lxDist[3], lyDist[3],
    lxDist[4], lyDist[4], lxDist[5], lyDist[5], lxDist[6], lyDist[6], lxDist[7], lyDist[7]);
  CheckShellRigidBodyQ8('Distorted', K, lxDist, lyDist, zDist, 1.0E-5);

  WriteLn;
  if FailCount = 0 then
    WriteLn('ALL CHECKS PASSED')
  else
  begin
    WriteLn(FailCount, ' CHECK(S) FAILED');
    Halt(1);
  end;
end.
