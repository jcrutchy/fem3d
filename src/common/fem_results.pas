unit fem_results;

{$mode objfpc}{$H+}

// Element force / stress recovery -- the "what is happening INSIDE each
// element" half of an analysis, computed after the solver has found the
// nodal displacements. Nothing here assembles or solves anything; every
// routine takes one element's displacement vector (global axes, in the same
// dof order the stiffness matrix uses) and works backwards from it.
//
// SIGN CONVENTIONS (stated once, used everywhere)
//
//   Beam internal forces are the resultants acting on the cross-section's
//   POSITIVE face -- the face whose outward normal points along +x of the
//   member (i.e. toward node 2). Equivalently: the force the part of the
//   member beyond the section exerts on the part before it.
//       N   axial force          (+ = tension)
//       Vy  shear along local y   Vz  shear along local z
//       T   torsion about x
//       My  bending moment about local y     Mz  bending moment about local z
//   Positive-face moments follow the right-hand rule about the axis.
//   Extreme-fibre axial stress at a point (y, z) of the section is
//       sigma = N/A - Mz*y/Iz + My*z/Iy
//   (so a downward load on a horizontal cantilever gives Mz < 0 at the
//   support and tension on the +y, upper, fibre -- the usual physical
//   picture).
//
//   Truss: N = EA/L * (elongation); + = tension.
//
// BEAM AXES: "principal" vs "geometric"
//   A beam section is described here by Iy and Iz taken about the section's
//   own local y and z axes, with no product of inertia Iyz. Those local axes
//   are therefore BOTH the geometric and the principal axes of the section
//   (they coincide whenever Iyz = 0), so the local-axes values below are the
//   principal-axes values. The same resultants are also given resolved on
//   the global X/Y/Z axes.

interface

uses
  fem_types, fem_index, fem_matrix, fem_elements, SysUtils, Math;

type
  TTrussResult = record
    N: Double;          // axial force (+ tension)
    Sigma: Double;      // N / A
  end;

  TBeamStation = record
    S: Double;          // distance from node 1 along the member
    // resultants on the positive face, member-local (principal) axes
    N, Vy, Vz, T, My, Mz: Double;
    // the same resultants resolved on global axes
    GFx, GFy, GFz, GMx, GMy, GMz: Double;
    // stresses (valid only if the owning TBeamResult.HasStress)
    SigAxial: Double;   // N/A
    SigMax, SigMin: Double; // extreme-fibre axial+bending stress, over the four section corners
    Tau: Double;        // torsional shear at the outer fibre, T*Rt/J (0 if Rt not given)
    VonMises, Tresca: Double; // worst corner, combining sigma and tau
  end;

  TBeamResult = record
    Length: Double;
    HasBendingStress: Boolean; // Cy and Cz were given -> SigMax/SigMin include bending
    HasTorsionStress: Boolean; // Rt was given -> Tau included
    Stations: array of TBeamStation;
  end;

  // A single sampled plane-stress state, with everything derived from it.
  TPlaneStress = record
    Sxx, Syy, Txy: Double;
    S1, S2: Double;     // principal stresses (S1 >= S2)
    Angle: Double;      // angle of the S1 direction from local x, radians
    VonMises, Tresca: Double;
  end;

// ---- failure-criterion helpers (shared by every element type) -----------
// Combined axial + shear (beam fibres): sigma_vm = sqrt(s^2 + 3 t^2),
// Tresca = 2*tau_max = sqrt(s^2 + 4 t^2).
function VonMisesSigmaTau(Sigma, Tau: Double): Double;
function TrescaSigmaTau(Sigma, Tau: Double): Double;
// Full plane-stress state (sigma_zz = 0): principal values, von Mises,
// Tresca (largest of |s1|, |s2|, |s1-s2|, because the third principal
// stress is zero).
function PlaneStressState(Sxx, Syy, Txy: Double): TPlaneStress;

// ---- recovery ---------------------------------------------------------------
// Ue = the element's displacement vector in global axes, 1-based, in the
// element's stiffness-matrix dof order (truss: 6 entries; beam: 12).
function TrussResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray): TTrussResult;

function BeamResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray; Divisions: Integer): TBeamResult;

implementation

function VonMisesSigmaTau(Sigma, Tau: Double): Double;
begin
  Result := Sqrt(Sigma * Sigma + 3.0 * Tau * Tau);
end;

function TrescaSigmaTau(Sigma, Tau: Double): Double;
begin
  Result := Sqrt(Sigma * Sigma + 4.0 * Tau * Tau);
end;

function PlaneStressState(Sxx, Syy, Txy: Double): TPlaneStress;
var
  avg, rad: Double;
begin
  Result.Sxx := Sxx; Result.Syy := Syy; Result.Txy := Txy;
  avg := 0.5 * (Sxx + Syy);
  rad := Sqrt(Sqr(0.5 * (Sxx - Syy)) + Txy * Txy);
  Result.S1 := avg + rad;
  Result.S2 := avg - rad;
  Result.Angle := 0.5 * ArcTan2(2.0 * Txy, Sxx - Syy);
  Result.VonMises := Sqrt(Max(0.0, Sxx * Sxx - Sxx * Syy + Syy * Syy + 3.0 * Txy * Txy));
  Result.Tresca := Max(Abs(Result.S1), Max(Abs(Result.S2), Abs(Result.S1 - Result.S2)));
end;

function TrussResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray): TTrussResult;
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2: TNode;
  dx, dy, dz, L, elong: Double;
begin
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  dx := n2.X - n1.X; dy := n2.Y - n1.Y; dz := n2.Z - n1.Z;
  L := Sqrt(dx * dx + dy * dy + dz * dz);
  if L <= 0 then
    raise Exception.Create('Truss element has zero length (coincident nodes)');
  // elongation = relative displacement of node 2 w.r.t. node 1, projected on the member axis
  elong := ((Ue[4] - Ue[1]) * dx + (Ue[5] - Ue[2]) * dy + (Ue[6] - Ue[3]) * dz) / L;
  Result.N := mat.E * prop.Area / L * elong;
  Result.Sigma := Result.N / prop.Area;
end;

function BeamResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray; Divisions: Integer): TBeamResult;
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2: TNode;
  G, L: Double;
  refVec: array[0..2] of Double;
  F: TFrame3;
  Lam: array[0..2, 0..2] of Double;
  Kl: TElemMatrix;
  ul, fe: array[1..12] of Double;
  b, k, c, r, st: Integer;
  s, y, z, tau: Double;
  stn: TBeamStation;
  sigC, vm, tr: Double;
begin
  if Divisions < 1 then Divisions := 1;
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  G := mat.E / (2.0 * (1.0 + mat.Nu));
  if el.HasRefVec then
  begin
    refVec[0] := el.RefVec[0]; refVec[1] := el.RefVec[1]; refVec[2] := el.RefVec[2];
  end
  else
  begin
    refVec[0] := 0; refVec[1] := 0; refVec[2] := 0;
  end;

  // Same frame and local stiffness the solver assembled with.
  F := BeamFrame(n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z, refVec, L);
  Kl := BeamLocalStiffness(mat.E, G, prop.Area, prop.Iy, prop.Iz, prop.J, L);
  for c := 0 to 2 do
  begin
    Lam[0][c] := F.ex[c]; Lam[1][c] := F.ey[c]; Lam[2][c] := F.ez[c];
  end;

  // global -> local displacements: each 3-dof block (4 of them) rotates by Lam
  for b := 0 to 3 do
    for r := 0 to 2 do
    begin
      ul[3 * b + r + 1] := 0.0;
      for c := 0 to 2 do
        ul[3 * b + r + 1] := ul[3 * b + r + 1] + Lam[r][c] * Ue[3 * b + c + 1];
    end;

  // local end forces fe = Kl * ul (force the nodes exert on the element)
  for r := 1 to 12 do
  begin
    fe[r] := 0.0;
    for c := 1 to 12 do
      fe[r] := fe[r] + Kl[r][c] * ul[c];
  end;

  Result.Length := L;
  Result.HasBendingStress := (prop.Cy > 0) and (prop.Cz > 0);
  Result.HasTorsionStress := prop.Rt > 0;
  SetLength(Result.Stations, Divisions + 1);

  // Only nodal loads exist in this model, so between the nodes the shear,
  // axial force and torque are constant and the moments vary linearly:
  // the resultants at any station follow from node 1's end force alone
  // (free body of the piece from node 1 to the section; see unit header).
  for st := 0 to Divisions do
  begin
    s := L * st / Divisions;
    stn.S := s;
    stn.N  := -fe[1];
    stn.Vy := -fe[2];
    stn.Vz := -fe[3];
    stn.T  := -fe[4];
    stn.My := -(fe[5] + s * fe[3]);
    stn.Mz := -(fe[6] - s * fe[2]);

    // resolve on global axes: global = Lam^T * local
    stn.GFx := stn.N * F.ex[0] + stn.Vy * F.ey[0] + stn.Vz * F.ez[0];
    stn.GFy := stn.N * F.ex[1] + stn.Vy * F.ey[1] + stn.Vz * F.ez[1];
    stn.GFz := stn.N * F.ex[2] + stn.Vy * F.ey[2] + stn.Vz * F.ez[2];
    stn.GMx := stn.T * F.ex[0] + stn.My * F.ey[0] + stn.Mz * F.ez[0];
    stn.GMy := stn.T * F.ex[1] + stn.My * F.ey[1] + stn.Mz * F.ez[1];
    stn.GMz := stn.T * F.ex[2] + stn.My * F.ey[2] + stn.Mz * F.ez[2];
    // (moments map the same way: T about ex, My about ey, Mz about ez)

    // ---- stresses ----
    stn.SigAxial := stn.N / prop.Area;
    if prop.Rt > 0 then
      tau := stn.T * prop.Rt / prop.J
    else
      tau := 0.0;
    stn.Tau := tau;

    stn.SigMax := stn.SigAxial;
    stn.SigMin := stn.SigAxial;
    stn.VonMises := 0.0;
    stn.Tresca := 0.0;
    if Result.HasBendingStress then
    begin
      // the four section corners (+-Cy, +-Cz)
      for k := 0 to 3 do
      begin
        if (k and 1) = 0 then y := prop.Cy else y := -prop.Cy;
        if (k and 2) = 0 then z := prop.Cz else z := -prop.Cz;
        sigC := stn.N / prop.Area - stn.Mz * y / prop.Iz + stn.My * z / prop.Iy;
        if k = 0 then
        begin
          stn.SigMax := sigC; stn.SigMin := sigC;
        end
        else
        begin
          if sigC > stn.SigMax then stn.SigMax := sigC;
          if sigC < stn.SigMin then stn.SigMin := sigC;
        end;
        vm := VonMisesSigmaTau(sigC, tau);
        tr := TrescaSigmaTau(sigC, tau);
        if vm > stn.VonMises then stn.VonMises := vm;
        if tr > stn.Tresca then stn.Tresca := tr;
      end;
    end
    else
    begin
      stn.VonMises := VonMisesSigmaTau(stn.SigAxial, tau);
      stn.Tresca := TrescaSigmaTau(stn.SigAxial, tau);
    end;
    Result.Stations[st] := stn;
  end;
end;

end.
