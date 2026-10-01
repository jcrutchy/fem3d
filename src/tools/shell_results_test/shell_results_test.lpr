program shell_results_test;

// Shell stress recovery (shellq4 and shellq8) at an ARBITRARY 3D orientation,
// with no solver involved:
//
//   * a known linear membrane field  (u = a1 x + a2 y, v = b1 x + b2 y) and a
//     known constant-curvature plate field (w = c1 x^2/2 + c2 y^2/2 + c3 x y)
//     are imposed analytically in the element's own plane, on a mildly
//     distorted quad;
//   * the nodal values are rotated into global axes by a deliberately
//     non-axis-aligned frame and handed to ShellResultFor;
//   * every sampled quantity (centroid and the four corner nodes: N, M, Q,
//     top/bottom face stresses, principal stresses, von Mises, Tresca) is
//     compared with the closed-form answer.
//
// That exercises exactly the parts of the recovery that the solver-based
// regression cases (025-031, all axis-aligned) cannot: the global->local rotation
// of translations AND rotations, the DKQ [w,w_x,w_y] remap, and the face-stress
// formulas on a non-rectangular element. Exit code 0 = all passed.

{$mode objfpc}{$H+}

uses
  SysUtils, Math, fem_types, fem_index, fem_matrix, fem_results;

var
  Fails, Checks: Integer;

procedure Near(const Name: string; Actual, Expected: Double; Tol: Double = 1E-9);
begin
  Inc(Checks);
  if Abs(Actual - Expected) > Tol * (1.0 + Abs(Expected)) then
  begin
    Inc(Fails);
    WriteLn('FAIL  ', Name, '  expected ', Expected:0:10, ' got ', Actual:0:10);
  end;
end;

const
  E = 2.0E11; Nu = 0.3; T = 0.05;
  // imposed local fields
  a1 = 0.0012; a2 = 0.0007; b1 = -0.0004; b2 = 0.0009;
  c1 = 0.0011; c2 = -0.0006; c3 = 0.0005;

procedure TestShell(const ElemType: string);
var
  NN, i, k, c, pt: Integer;
  Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap;
  lx, ly: array[1..8] of Double;
  ex, ey, ez, O: TVec3;
  Lam: array[0..2, 0..2] of Double;
  ul: array[1..6] of Double;
  Ue: TDoubleArray;
  R: TShellResult;
  cE, Dfac, exx, eyy, gxy, kx, ky, kxy: Double;
  eNxx, eNyy, eNxy, eMxx, eMyy, eMxy: Double;
  wantT, wantB: TPlaneStress;
  lab, loc: string;
begin
  if ElemType = 'shellq8' then NN := 8 else NN := 4;

  // distorted quad in its own plane; node 2 on the local x axis and node 4 at
  // positive local y, so the frame the element builds is exactly (ex, ey, ez).
  lx[1] := 0.0;  ly[1] := 0.0;
  lx[2] := 2.0;  ly[2] := 0.0;
  lx[3] := 2.2;  ly[3] := 1.1;
  lx[4] := 0.1;  ly[4] := 0.9;
  lx[5] := (lx[1] + lx[2]) / 2; ly[5] := (ly[1] + ly[2]) / 2;
  lx[6] := (lx[2] + lx[3]) / 2; ly[6] := (ly[2] + ly[3]) / 2;
  lx[7] := (lx[3] + lx[4]) / 2; ly[7] := (ly[3] + ly[4]) / 2;
  lx[8] := (lx[4] + lx[1]) / 2; ly[8] := (ly[4] + ly[1]) / 2;

  ex := VNormalize(Vec3(0.6, -0.3, 0.74));
  ey := VNormalize(VCross(Vec3(0.2, 0.9, -0.1), ex));
  ez := VCross(ex, ey);
  ey := VCross(ez, ex);
  O := Vec3(3.0, -2.0, 5.0);
  for c := 0 to 2 do
  begin
    Lam[0][c] := ex[c]; Lam[1][c] := ey[c]; Lam[2][c] := ez[c];
  end;

  SetLength(Model.Nodes, NN);
  SetLength(Model.Materials, 1);
  SetLength(Model.Properties, 1);
  SetLength(Model.Elements, 1);
  for i := 1 to NN do
  begin
    Model.Nodes[i - 1].Id := i;
    Model.Nodes[i - 1].X := O[0] + lx[i] * ex[0] + ly[i] * ey[0];
    Model.Nodes[i - 1].Y := O[1] + lx[i] * ex[1] + ly[i] * ey[1];
    Model.Nodes[i - 1].Z := O[2] + lx[i] * ex[2] + ly[i] * ey[2];
  end;
  Model.Materials[0].Id := 1; Model.Materials[0].E := E; Model.Materials[0].Nu := Nu;
  Model.Properties[0].Id := 1; Model.Properties[0].ElementType := ElemType;
  Model.Properties[0].MaterialId := 1; Model.Properties[0].Thickness := T;
  Model.Elements[0].Id := 1; Model.Elements[0].ElementType := ElemType;
  Model.Elements[0].PropertyId := 1;
  SetLength(Model.Elements[0].NodeIds, NN);
  for i := 1 to NN do Model.Elements[0].NodeIds[i - 1] := i;
  NodeIdx := IndexNodes(Model); MatIdx := IndexMaterials(Model); PropIdx := IndexProperties(Model);

  // impose the local field at every node, rotate into global axes
  SetLength(Ue, 6 * NN + 1);
  Ue[0] := 0.0;
  for i := 1 to NN do
  begin
    ul[1] := a1 * lx[i] + a2 * ly[i];
    ul[2] := b1 * lx[i] + b2 * ly[i];
    ul[3] := c1 * lx[i] * lx[i] / 2 + c2 * ly[i] * ly[i] / 2 + c3 * lx[i] * ly[i];
    ul[4] := c2 * ly[i] + c3 * lx[i];          // rx = +dw/dy
    ul[5] := -(c1 * lx[i] + c3 * ly[i]);       // ry = -dw/dx
    ul[6] := 0.0;                              // drilling: no stress contribution
    for c := 0 to 2 do
    begin
      Ue[6 * (i - 1) + c + 1] := 0.0;
      Ue[6 * (i - 1) + 3 + c + 1] := 0.0;
      for k := 0 to 2 do
      begin
        Ue[6 * (i - 1) + c + 1] := Ue[6 * (i - 1) + c + 1] + Lam[k][c] * ul[k + 1];
        Ue[6 * (i - 1) + 3 + c + 1] := Ue[6 * (i - 1) + 3 + c + 1] + Lam[k][c] * ul[3 + k + 1];
      end;
    end;
  end;

  R := ShellResultFor(Model, NodeIdx, MatIdx, PropIdx, Model.Elements[0], Ue);

  // closed form
  cE := E / (1 - Nu * Nu);
  Dfac := T * T * T / 12 * cE;
  exx := a1; eyy := b2; gxy := a2 + b1;
  kx := c1; ky := c2; kxy := 2 * c3;
  eNxx := T * cE * (exx + Nu * eyy);  eNyy := T * cE * (Nu * exx + eyy);  eNxy := T * cE * (1 - Nu) / 2 * gxy;
  eMxx := Dfac * (kx + Nu * ky);      eMyy := Dfac * (Nu * kx + ky);      eMxy := Dfac * (1 - Nu) / 2 * kxy;
  wantT := PlaneStressState(eNxx / T - 6 * eMxx / (T * T), eNyy / T - 6 * eMyy / (T * T), eNxy / T - 6 * eMxy / (T * T));
  wantB := PlaneStressState(eNxx / T + 6 * eMxx / (T * T), eNyy / T + 6 * eMyy / (T * T), eNxy / T + 6 * eMxy / (T * T));

  lab := ElemType + ': ';
  Near(lab + 'frame ex', VDot(R.Frame.ex, ex), 1.0, 1E-12);
  Near(lab + 'frame ey', VDot(R.Frame.ey, ey), 1.0, 1E-12);
  Near(lab + 'frame ez', VDot(R.Frame.ez, ez), 1.0, 1E-12);
  Near(lab + 'thickness', R.Thickness, T, 1E-15);
  for pt := 0 to 4 do
  begin
    if pt = 0 then loc := 'centre' else loc := Format('node %d', [pt]);
    with R.Points[pt] do
    begin
      Near(lab + 'Nxx ' + loc, Nxx, eNxx);
      Near(lab + 'Nyy ' + loc, Nyy, eNyy);
      Near(lab + 'Nxy ' + loc, Nxy, eNxy);
      Near(lab + 'Mxx ' + loc, Mxx, eMxx);
      Near(lab + 'Myy ' + loc, Myy, eMyy);
      Near(lab + 'Mxy ' + loc, Mxy, eMxy);
      if R.HasShear then
      begin
        Near(lab + 'Qx (zero for a constant-curvature field) ' + loc, Qx, 0.0, 1E-6);
        Near(lab + 'Qy (zero for a constant-curvature field) ' + loc, Qy, 0.0, 1E-6);
      end;
      Near(lab + 'top sxx ' + loc, Top.Sxx, wantT.Sxx);
      Near(lab + 'top syy ' + loc, Top.Syy, wantT.Syy);
      Near(lab + 'top txy ' + loc, Top.Txy, wantT.Txy);
      Near(lab + 'top S1 ' + loc, Top.S1, wantT.S1);
      Near(lab + 'top S2 ' + loc, Top.S2, wantT.S2);
      Near(lab + 'top von Mises ' + loc, Top.VonMises, wantT.VonMises);
      Near(lab + 'top Tresca ' + loc, Top.Tresca, wantT.Tresca);
      Near(lab + 'bottom sxx ' + loc, Bot.Sxx, wantB.Sxx);
      Near(lab + 'bottom syy ' + loc, Bot.Syy, wantB.Syy);
      Near(lab + 'bottom txy ' + loc, Bot.Txy, wantB.Txy);
      Near(lab + 'bottom S1 ' + loc, Bot.S1, wantB.S1);
      Near(lab + 'bottom S2 ' + loc, Bot.S2, wantB.S2);
      Near(lab + 'bottom von Mises ' + loc, Bot.VonMises, wantB.VonMises);
      Near(lab + 'bottom Tresca ' + loc, Bot.Tresca, wantB.Tresca);
    end;
  end;
end;

begin
  Fails := 0; Checks := 0;
  TestShell('shellq4');
  TestShell('shellq8');
  WriteLn;
  if Fails = 0 then
  begin
    WriteLn('ALL ', Checks, ' CHECKS PASSED');
    Halt(0);
  end
  else
  begin
    WriteLn(Fails, ' of ', Checks, ' CHECKS FAILED');
    Halt(1);
  end;
end.
