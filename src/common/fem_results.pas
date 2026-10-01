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
//   Shells (shellq4, shellq8) are reported in the element's own axes: x along
//   the edge from node 1 to node 2, z the normal from the right-hand rule on
//   nodes 1-2-4 (so counter-clockwise numbering seen from +z), y completing
//   the set. The axes are also reported so results can be resolved globally.
//       Nxx Nyy Nxy   membrane force per unit length (+ = tension)
//       Mxx Myy Mxy   bending moment per unit length; positive Mxx is
//                     "sagging" about the local y axis, i.e. tension on the
//                     bottom (-z) face, as for a beam bending in the x-z plane
//       Qx Qy         transverse shear force per unit length (shellq8 only:
//                     the thin-plate shellq4 does not carry a shear strain)
//   Stress on the top (+z) and bottom (-z) faces, plane stress (sigma_zz = 0):
//       sigma_top = N/t - 6M/t^2     sigma_bot = N/t + 6M/t^2
//   Principal stresses, von Mises and Tresca are computed from each face's
//   (sxx, syy, txy). Transverse shear stress is not included.
//   Values are evaluated at the element centroid and at the four corner
//   nodes, straight from the element's own displacement field -- NOT
//   averaged with neighbouring elements, so expect a jump across element
//   boundaries where the mesh is too coarse to resolve the stress gradient.
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
  fem_types, fem_index, fem_matrix, fem_elements, fem_plate_shapefuncs, SysUtils, Math;

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

type
  // One sampling point of a shell element.
  TShellPoint = record
    Xi, Eta: Double;            // natural coordinates of the point
    Nxx, Nyy, Nxy: Double;      // membrane force / length
    Mxx, Myy, Mxy: Double;      // bending moment / length
    Qx, Qy: Double;             // transverse shear force / length (HasShear only)
    Top, Bot: TPlaneStress;     // stress on the +z / -z faces
  end;

  TShellResult = record
    NodeCount: Integer;         // 4 (shellq4) or 8 (shellq8)
    HasShear: Boolean;          // shellq8 only
    Thickness: Double;
    Frame: TFrame3;             // element axes in global coordinates
    // [0] = centroid; [1..4] = the corner nodes 1..4 (midside nodes of a
    // shellq8 are not sampled separately)
    Points: array[0..4] of TShellPoint;
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

function ShellResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray): TShellResult;

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

function ShellResultFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement;
  const Ue: TDoubleArray): TShellResult;
const
  PtXi:  array[0..4] of Double = (0.0, -1.0,  1.0, 1.0, -1.0);
  PtEta: array[0..4] of Double = (0.0, -1.0, -1.0, 1.0,  1.0);
var
  prop: TProperty;
  mat: TMaterial;
  NN, i, r, c, pt, base: Integer;
  t, cE, Dfac, Gmod, detJ: Double;
  P: array[1..8] of TVec3;
  node: TNode;
  F: TFrame3;
  lx, ly: TQuadCoords;
  Lam: array[0..2, 0..2] of Double;
  ul: array[1..48] of Double;
  um: array[1..16] of Double;
  uw: array[1..24] of Double;
  wd: array[1..12] of Double;
  // Flat row-major B matrices: the builders write rows with a stride equal to
  // the element's own column count (2*NN, 24, 12), so index them the same way.
  Bm: array[0..3 * 16 - 1] of Double;
  Bb: array[0..3 * 24 - 1] of Double;
  Bs: array[0..2 * 24 - 1] of Double;
  Bk: array[0..3 * 12 - 1] of Double;
  Op: TDKQOps;
  sf4: TQuadShapeFuncs;
  sf8: TQuad8ShapeFuncs;
  eps: array[1..3] of Double;
  kap: array[1..3] of Double;
  gam: array[1..2] of Double;
  px, py: array[1..4] of Double;
  sp: TShellPoint;
  sxxT, syyT, txyT, sxxB, syyB, txyB: Double;
  s: Double;
begin
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  if el.ElementType = 'shellq8' then NN := 8 else NN := 4;
  t := prop.Thickness;

  for i := 1 to NN do
  begin
    node := Model.Nodes[NodeIdx[el.NodeIds[i - 1]]];
    P[i] := Vec3(node.X, node.Y, node.Z);
  end;
  // Exactly the geometry the stiffness was built from.
  QuadLocalGeometry(NN, P,
    'Shell element has a zero-length 1-2 edge (coincident nodes)',
    'Shell element is degenerate (nodes 1, 2, 4 are collinear)',
    F, lx, ly);

  for c := 0 to 2 do
  begin
    Lam[0][c] := F.ex[c]; Lam[1][c] := F.ey[c]; Lam[2][c] := F.ez[c];
  end;

  // global -> element-local dof: each node's translation triple and rotation
  // triple rotate by Lam.
  for i := 1 to NN do
  begin
    base := 6 * (i - 1);
    for r := 0 to 2 do
    begin
      s := 0.0;
      for c := 0 to 2 do s := s + Lam[r][c] * Ue[base + c + 1];
      ul[base + r + 1] := s;
      s := 0.0;
      for c := 0 to 2 do s := s + Lam[r][c] * Ue[base + 3 + c + 1];
      ul[base + 3 + r + 1] := s;
    end;
  end;

  // membrane (u, v) and plate (w, rx, ry) sub-vectors
  for i := 1 to NN do
  begin
    um[2 * (i - 1) + 1] := ul[6 * (i - 1) + 1];
    um[2 * (i - 1) + 2] := ul[6 * (i - 1) + 2];
    uw[3 * (i - 1) + 1] := ul[6 * (i - 1) + 3];
    uw[3 * (i - 1) + 2] := ul[6 * (i - 1) + 4];
    uw[3 * (i - 1) + 3] := ul[6 * (i - 1) + 5];
  end;
  if NN = 4 then
  begin
    // DKQ works in [w, w_x, w_y]: rx = +w_y, ry = -w_x (same remap the
    // stiffness assembly uses).
    for i := 1 to 4 do
    begin
      wd[3 * (i - 1) + 1] := ul[6 * (i - 1) + 3];
      wd[3 * (i - 1) + 2] := -ul[6 * (i - 1) + 5];
      wd[3 * (i - 1) + 3] := ul[6 * (i - 1) + 4];
      px[i] := lx[i]; py[i] := ly[i];
    end;
    DKQOperators(px, py, Op);
  end;

  cE := mat.E / (1.0 - mat.Nu * mat.Nu);
  Dfac := t * t * t / 12.0 * cE;
  Gmod := mat.E / (2.0 * (1.0 + mat.Nu));

  Result.NodeCount := NN;
  Result.HasShear := NN = 8;
  Result.Thickness := t;
  Result.Frame := F;

  for pt := 0 to 4 do
  begin
    FillChar(sp, SizeOf(sp), 0);
    sp.Xi := PtXi[pt]; sp.Eta := PtEta[pt];

    // ---- membrane strain -> force per length ----
    if NN = 4 then
    begin
      sf4 := QuadShapeFuncsAt(sp.Xi, sp.Eta);
      MembraneBAt(4, sf4.dNdXi, sf4.dNdEta, lx, ly, 'Quad shell element', @Bm[0], detJ);
    end
    else
    begin
      sf8 := Quad8ShapeFuncsAt(sp.Xi, sp.Eta);
      MembraneBAt(8, sf8.dNdXi, sf8.dNdEta, lx, ly, 'Q8 quad shell element', @Bm[0], detJ);
    end;
    for r := 1 to 3 do
    begin
      eps[r] := 0.0;
      for c := 1 to 2 * NN do
        eps[r] := eps[r] + Bm[(r - 1) * 2 * NN + c - 1] * um[c];
    end;
    sp.Nxx := t * cE * (eps[1] + mat.Nu * eps[2]);
    sp.Nyy := t * cE * (mat.Nu * eps[1] + eps[2]);
    sp.Nxy := t * cE * (1.0 - mat.Nu) / 2.0 * eps[3];

    // ---- plate curvature -> moment per length (and shear for shellq8) ----
    if NN = 4 then
    begin
      DKQBAt(Op, px, py, sp.Xi, sp.Eta, @Bk[0], detJ);
      for r := 1 to 3 do
      begin
        kap[r] := 0.0;
        for c := 1 to 12 do kap[r] := kap[r] + Bk[(r - 1) * 12 + c - 1] * wd[c];
      end;
    end
    else
    begin
      MindlinBAt(sf8, lx, ly, @Bb[0], @Bs[0], detJ);
      for r := 1 to 3 do
      begin
        kap[r] := 0.0;
        for c := 1 to 24 do kap[r] := kap[r] + Bb[(r - 1) * 24 + c - 1] * uw[c];
      end;
      for r := 1 to 2 do
      begin
        gam[r] := 0.0;
        for c := 1 to 24 do gam[r] := gam[r] + Bs[(r - 1) * 24 + c - 1] * uw[c];
      end;
      sp.Qx := ShellQ8ShearFactor * Gmod * t * gam[1];
      sp.Qy := ShellQ8ShearFactor * Gmod * t * gam[2];
    end;
    sp.Mxx := Dfac * (kap[1] + mat.Nu * kap[2]);
    sp.Myy := Dfac * (mat.Nu * kap[1] + kap[2]);
    sp.Mxy := Dfac * (1.0 - mat.Nu) / 2.0 * kap[3];

    // ---- face stresses (plane stress): sigma = N/t -/+ 6M/t^2 ----
    sxxT := sp.Nxx / t - 6.0 * sp.Mxx / (t * t);
    syyT := sp.Nyy / t - 6.0 * sp.Myy / (t * t);
    txyT := sp.Nxy / t - 6.0 * sp.Mxy / (t * t);
    sxxB := sp.Nxx / t + 6.0 * sp.Mxx / (t * t);
    syyB := sp.Nyy / t + 6.0 * sp.Myy / (t * t);
    txyB := sp.Nxy / t + 6.0 * sp.Mxy / (t * t);
    sp.Top := PlaneStressState(sxxT, syyT, txyT);
    sp.Bot := PlaneStressState(sxxB, syyB, txyB);
    Result.Points[pt] := sp;
  end;
end;

end.
