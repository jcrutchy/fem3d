unit fem_elements;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, fem_plate_shapefuncs, Math, SysUtils;

type
  // TElemMatrix is fem_types.TDenseMatrix under another name for
  // readability at call sites (an "element stiffness matrix" is exactly a
  // dense matrix, sized 6 for a truss, 12 for a beam).
  TElemMatrix = TDenseMatrix;

function NewElemMatrix(N: Integer): TElemMatrix;

// Default drilling-penalty factor for ElementStiffnessFor's shellq4
// dispatch -- see QuadShellStiffnessLocal's DrillFactor parameter for
// what it does and why. Not yet exposed in the model format (no
// per-property override); revisit if a model ever needs to tune it.
const ShellDrillFactor = 1.0E-4;

// 2-node space truss (axial-only bar), 6x6, dof order per node [x,y,z].
function TrussStiffness3D(E, A, x1, y1, z1, x2, y2, z2: Double): TElemMatrix;

// 2-node 3D Euler-Bernoulli beam (no shear deformation), 12x12, dof order
// per node [x,y,z,rx,ry,rz]. Iz resists bending that deflects the beam in
// the local y direction (rotation about local z); Iy resists bending that
// deflects it in local z (rotation about local y); J is the torsion
// constant. RefVec is an optional orientation reference (any vector not
// parallel to the beam axis) used to fix the beam's roll about its own
// axis -- pass a zero vector to use the default heuristic (global Z,
// falling back to global X for near-vertical members).
function BeamStiffness3D(E, G, A, Iy, Iz, J,
  x1, y1, z1, x2, y2, z2: Double; const RefVec: array of Double): TElemMatrix;

// 4-node bilinear ("Q4") quad, membrane (in-plane) stiffness only,
// LOCAL 2D formulation: takes the 4 corners already projected into the
// element's own flat local (x,y) plane. 8x8, local dof order per node
// [u, v]. Plane-stress constitutive law. See QuadMembraneStiffness3D
// for the 3D wrapper (local basis + global transform) built on this.
function QuadMembraneStiffnessLocal(E, Nu, Thickness: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;

// 4-node bilinear ("Q4") quad, membrane (in-plane) stiffness only -- no
// bending, no drilling dof. 12x12, dof order per node [x,y,z] (same
// translation-only convention as the truss), so it assembles into a
// model exactly like a truss does. Plane-stress constitutive law.
// Nodes must be given in CCW order around the quad (see
// fem_plate_shapefuncs.QuadShapeFuncsAt); the element is assumed flat
// (all 4 nodes coplanar) -- that check belongs to fem_validate, not
// here, same division of responsibility as the rest of this unit
// (validity is fem_validate's job; this unit trusts its inputs).
// Standalone and not yet wired into ElementStiffnessFor/fem_dofmap --
// membrane-only is step 2 of the plate-element build (see fem3d's
// README "Status / next steps"); wiring it into the 2-node-assuming
// dofmap/validate pipeline is step 5, once this stiffness formulation
// itself is patch-test verified.
function QuadMembraneStiffness3D(E, Nu, Thickness: Double;
  x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4: Double): TElemMatrix;

// 4-node DKQ (Discrete Kirchhoff Quadrilateral) thin-plate bending
// stiffness, LOCAL 2D formulation: takes the 4 corners already
// projected into the element's own flat local (x,y) plane (unlike
// QuadMembraneStiffness3D, which takes 3D corners and builds that
// local frame itself) -- see the comment on the function body for why
// this one stops short of doing that.
// 12x12, LOCAL dof order per node: [w, w_x, w_y] where w_x = dw/dx
// and w_y = dw/dy are SLOPES, not yet the rotation-vector dof
// (rx, ry) a flat-shell assembly would need -- reconciling that
// convention with BeamStiffness3D's rx/ry/rz, and combining this with
// QuadMembraneStiffness3D into one local-to-global 24x24 flat-shell
// element, is wiring work (step 5), same as for the membrane element.
// Ported from a from-scratch-legible open-source DKQ implementation
// (github.com/feizhang233/2D-Plate-Project-Backend, mindlin_plate/
// kirchhoff.py, MIT-style small research library) rather than
// transcribed from the original Batoz & Tahar 1982 algebra, because
// every step of that reference's derivation is independently checkable
// by hand (the discrete Kirchhoff constraint it encodes --
// g_s(mid) = 3(w_j-w_i)/(2L) - (g_s(i)+g_s(j))/4,
// g_n(mid) = (g_n(i)+g_n(j))/2 -- was re-derived and confirmed against
// its code below, not just copied); patch-tested independently in
// run_patch_test.lpr the same way as the membrane element.
function QuadBendingStiffnessLocal(E, Nu, Thickness: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;

// Combined flat-shell element: membrane (QuadMembraneStiffnessLocal)
// + DKQ bending (QuadBendingStiffnessLocal), assembled into one local
// 24x24 matrix, dof order per node [u, v, w, rx, ry, rz] -- the SAME
// convention BeamStiffness3D uses (verified against it, not assumed:
// its local stiffness pattern shows rz=+dv/dx, ry=-dw/dx, and the
// general rigid-rotation relation delta_w = rx*y - ry*x gives, by the
// same construction, rx=+dw/dy, ry=-dw/dx -- consistent with beam's
// ry sign, so this shell's rx/ry/rz will assemble correctly at a node
// shared with a beam element).
//
// rz ("drilling") has no stiffness from either sub-element -- neither
// the membrane nor DKQ formulation constrains in-plane corner rotation
// -- so a small artificial diagonal penalty is added, sized as
// DrillFactor times the mean diagonal of the local membrane matrix.
// This is a standard, but frankly approximate, stopgap (the textbook
// alternative is a proper drilling-dof membrane formulation, e.g.
// Allman's triangle/quad -- not implemented here). DrillFactor is
// exposed rather than hardcoded so it can be tuned or the whole
// mechanism swapped out later without touching the rest of the
// element; something in the 1e-4 to 1e-3 range is the usual advice
// (large enough to regularize rz, small enough not to distort the
// real membrane/bending response).
function QuadShellStiffnessLocal(E, Nu, Thickness, DrillFactor: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;

// QuadShellStiffnessLocal wrapped with the same local-basis
// construction as QuadMembraneStiffness3D/QuadBendingStiffnessLocal's
// callers would need, transformed to a global 24x24 (4 nodes x 6 dof
// [x,y,z,rx,ry,rz]). Rotation dof transform the same way translations
// do under a pure change of orthonormal frame (Lam applied per node,
// twice: once for the translation triplet, once for the rotation
// triplet) -- this is what QuadMembraneStiffness3D's 2-local/3-global
// transform generalizes to once w and drilling are both present.
// NOT wired into fem_dofmap/fem_validate/ElementStiffnessFor -- see
// the note on QuadMembraneStiffness3D; this is as far as "step 5"
// (wiring) goes without touching the 2-node-assuming dofmap.
function QuadShellStiffness3D(E, Nu, Thickness, DrillFactor: Double;
  x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4: Double): TElemMatrix;

// Model-aware dispatcher: builds the right element's global stiffness
// matrix given a model and its lookup maps (material/property lookup, G
// from E+nu, refVec handling all in one place). Every solver that needs
// an element's stiffness goes through this rather than re-implementing
// the truss-vs-beam dispatch itself -- linstatic, modal, and linsparse
// all share this.
function ElementStiffnessFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement): TElemMatrix;

implementation

function NewElemMatrix(N: Integer): TElemMatrix;
begin
  Result := NewDenseMatrix(N);
end;

function TrussStiffness3D(E, A, x1, y1, z1, x2, y2, z2: Double): TElemMatrix;
var
  dx, dy, dz, L, cx, cy, cz, k: Double;
  c: array[1..3] of Double;
  i, jc: Integer;
begin
  dx := x2 - x1; dy := y2 - y1; dz := z2 - z1;
  L := Sqrt(dx * dx + dy * dy + dz * dz);
  if L <= 0 then
    raise Exception.Create('Truss element has zero length (coincident nodes)');
  cx := dx / L; cy := dy / L; cz := dz / L;
  c[1] := cx; c[2] := cy; c[3] := cz;
  k := E * A / L;

  Result := NewElemMatrix(6);
  for i := 1 to 3 do
    for jc := 1 to 3 do
    begin
      Result[i][jc]         :=  k * c[i] * c[jc];
      Result[i][jc + 3]     := -k * c[i] * c[jc];
      Result[i + 3][jc]     := -k * c[i] * c[jc];
      Result[i + 3][jc + 3] :=  k * c[i] * c[jc];
    end;
end;

// --- 3D vector helpers (only used here; not worth a whole unit for 3 ops) ---
type TVec3 = array[0..2] of Double;

function VCross(const a, b: TVec3): TVec3;
begin
  Result[0] := a[1] * b[2] - a[2] * b[1];
  Result[1] := a[2] * b[0] - a[0] * b[2];
  Result[2] := a[0] * b[1] - a[1] * b[0];
end;

function VNorm(const a: TVec3): Double;
begin
  Result := Sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
end;

function VNormalize(const a: TVec3): TVec3;
var
  n: Double;
begin
  n := VNorm(a);
  if n <= 0 then
    raise Exception.Create('Cannot normalize a zero-length vector (degenerate beam orientation)');
  Result[0] := a[0] / n; Result[1] := a[1] / n; Result[2] := a[2] / n;
end;

function BeamStiffness3D(E, G, A, Iy, Iz, J,
  x1, y1, z1, x2, y2, z2: Double; const RefVec: array of Double): TElemMatrix;
var
  dx, dy, dz, L: Double;
  ex, ey, ez, vref: TVec3;
  Lam: array[0..2, 0..2] of Double; // rows = ex,ey,ez in global coords
  T: TElemMatrix;  // 12x12 block-diagonal transform (4 copies of Lam)
  Kl: TElemMatrix; // local stiffness
  blk, r, c, i, jc, k: Integer;
  a1, a2, a3: Double;
begin
  dx := x2 - x1; dy := y2 - y1; dz := z2 - z1;
  L := Sqrt(dx * dx + dy * dy + dz * dz);
  if L <= 0 then
    raise Exception.Create('Beam element has zero length (coincident nodes)');
  ex[0] := dx / L; ex[1] := dy / L; ex[2] := dz / L;

  vref[0] := 0; vref[1] := 0; vref[2] := 0;
  if (RefVec[0] = 0) and (RefVec[1] = 0) and (RefVec[2] = 0) then
  begin
    // Default heuristic (same idea used by most frame-analysis packages):
    // use global Z as the orientation reference, unless the member is
    // itself (near-)vertical, in which case that choice is degenerate and
    // global X is used instead.
    if Abs(ex[2]) > 0.999 then
      vref[0] := 1.0
    else
      vref[2] := 1.0;
  end
  else
  begin
    vref[0] := RefVec[0]; vref[1] := RefVec[1]; vref[2] := RefVec[2];
  end;

  ey := VNormalize(VCross(vref, ex));
  ez := VCross(ex, ey); // already unit length: ex, ey orthonormal

  Lam[0][0] := ex[0]; Lam[0][1] := ex[1]; Lam[0][2] := ex[2];
  Lam[1][0] := ey[0]; Lam[1][1] := ey[1]; Lam[1][2] := ey[2];
  Lam[2][0] := ez[0]; Lam[2][1] := ez[1]; Lam[2][2] := ez[2];

  // --- local stiffness (Euler-Bernoulli 3D frame element, standard form) ---
  Kl := NewElemMatrix(12);
  a1 := E * A / L;
  Kl[1][1] := a1; Kl[1][7] := -a1; Kl[7][1] := -a1; Kl[7][7] := a1;

  a2 := G * J / L;
  Kl[4][4] := a2; Kl[4][10] := -a2; Kl[10][4] := -a2; Kl[10][10] := a2;

  // bending about local z (affects v=y-translation, rz=z-rotation): dofs 2,6,8,12
  a3 := E * Iz / (L * L * L);
  Kl[2][2]   := 12 * a3;        Kl[2][6]  := 6 * L * a3;   Kl[2][8]   := -12 * a3;      Kl[2][12] := 6 * L * a3;
  Kl[6][6]   := 4 * L * L * a3; Kl[6][8]  := -6 * L * a3;  Kl[6][12]  := 2 * L * L * a3;
  Kl[8][8]   := 12 * a3;        Kl[8][12] := -6 * L * a3;
  Kl[12][12] := 4 * L * L * a3;

  // bending about local y (affects w=z-translation, ry=y-rotation): dofs 3,5,9,11
  a3 := E * Iy / (L * L * L);
  Kl[3][3]   := 12 * a3;        Kl[3][5]  := -6 * L * a3;  Kl[3][9]   := -12 * a3;      Kl[3][11] := -6 * L * a3;
  Kl[5][5]   := 4 * L * L * a3; Kl[5][9]  := 6 * L * a3;   Kl[5][11]  := 2 * L * L * a3;
  Kl[9][9]   := 12 * a3;        Kl[9][11] := 6 * L * a3;
  Kl[11][11] := 4 * L * L * a3;

  // fill in the symmetric lower triangle
  for i := 1 to 12 do
    for jc := i + 1 to 12 do
      Kl[jc][i] := Kl[i][jc];

  // --- transform: Kglobal = T^T * Kl * T, T block-diagonal with 4 copies of Lam ---
  T := NewElemMatrix(12);
  for blk := 0 to 3 do
    for r := 0 to 2 do
      for c := 0 to 2 do
        T[blk * 3 + r + 1][blk * 3 + c + 1] := Lam[r][c];

  // Result := Kl * T
  Result := NewElemMatrix(12);
  for i := 1 to 12 do
    for jc := 1 to 12 do
      for k := 1 to 12 do
        Result[i][jc] := Result[i][jc] + Kl[i][k] * T[k][jc];

  Kl := Result; // Kl now holds Kl*T (scratch reuse)
  Result := NewElemMatrix(12);
  for i := 1 to 12 do
    for jc := 1 to 12 do
      for k := 1 to 12 do
        Result[i][jc] := Result[i][jc] + T[k][i] * Kl[k][jc]; // T^T[i][k] = T[k][i]
end;

function QuadMembraneStiffnessLocal(E, Nu, Thickness: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;
var
  lx, ly: array[1..4] of Double;
  D: array[1..3, 1..3] of Double;
  gp: TGaussPointArray;
  sf: TQuadShapeFuncs;
  g, i, jc, k: Integer;
  J11, J12, J21, J22, detJ, invJ11, invJ12, invJ21, invJ22: Double;
  dNdx, dNdy: array[1..4] of Double;
  B: array[1..3, 1..8] of Double;
  BtD: array[1..8, 1..3] of Double;
  cE: Double;
begin
  lx[1] := x1; ly[1] := y1;
  lx[2] := x2; ly[2] := y2;
  lx[3] := x3; ly[3] := y3;
  lx[4] := x4; ly[4] := y4;

  cE := E / (1.0 - Nu * Nu);
  D[1,1] := cE;        D[1,2] := cE * Nu;   D[1,3] := 0;
  D[2,1] := cE * Nu;   D[2,2] := cE;        D[2,3] := 0;
  D[3,1] := 0;         D[3,2] := 0;         D[3,3] := cE * (1.0 - Nu) / 2.0;

  Result := NewElemMatrix(8);
  for i := 1 to 8 do
    for jc := 1 to 8 do
      Result[i, jc] := 0;

  // --- 2x2 Gauss integration of B^T * D * B * thickness over the element ---
  gp := QuadGaussPoints2x2;
  for g := 0 to NGaussPlate - 1 do
  begin
    sf := QuadShapeFuncsAt(gp[g].Xi, gp[g].Eta);

    J11 := 0; J12 := 0; J21 := 0; J22 := 0;
    for i := 1 to 4 do
    begin
      J11 := J11 + sf.dNdXi[i]  * lx[i];
      J12 := J12 + sf.dNdXi[i]  * ly[i];
      J21 := J21 + sf.dNdEta[i] * lx[i];
      J22 := J22 + sf.dNdEta[i] * ly[i];
    end;
    detJ := J11 * J22 - J12 * J21;
    if detJ <= 0 then
      raise Exception.Create('Quad membrane element has non-positive Jacobian determinant (inverted or degenerate shape)');
    invJ11 :=  J22 / detJ; invJ12 := -J12 / detJ;
    invJ21 := -J21 / detJ; invJ22 :=  J11 / detJ;

    for i := 1 to 4 do
    begin
      dNdx[i] := invJ11 * sf.dNdXi[i] + invJ12 * sf.dNdEta[i];
      dNdy[i] := invJ21 * sf.dNdXi[i] + invJ22 * sf.dNdEta[i];
    end;

    for i := 1 to 3 do
      for jc := 1 to 8 do
        B[i, jc] := 0;
    for i := 1 to 4 do
    begin
      B[1, 2*i - 1] := dNdx[i];
      B[2, 2*i]     := dNdy[i];
      B[3, 2*i - 1] := dNdy[i];
      B[3, 2*i]     := dNdx[i];
    end;

    // BtD = B^T * D  (8x3)
    for i := 1 to 8 do
      for jc := 1 to 3 do
      begin
        BtD[i, jc] := 0;
        for k := 1 to 3 do
          BtD[i, jc] := BtD[i, jc] + B[k, i] * D[k, jc];
      end;

    // Result += (BtD * B) * thickness * detJ * weight
    for i := 1 to 8 do
      for jc := 1 to 8 do
      begin
        cE := 0; // reused as an accumulator, constitutive value no longer needed here
        for k := 1 to 3 do
          cE := cE + BtD[i, k] * B[k, jc];
        Result[i, jc] := Result[i, jc] + cE * Thickness * detJ * gp[g].Weight;
      end;
  end;
end;

function QuadMembraneStiffness3D(E, Nu, Thickness: Double;
  x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4: Double): TElemMatrix;
var
  ex, ey, ez, edge1, edge2, nrm: TVec3;
  lx, ly: array[1..4] of Double; // node local in-plane coords
  T: array[1..8, 1..12] of Double; // local (u,v)*4 <- global (x,y,z)*4
  KeLocal: array[1..8, 1..8] of Double;
  KeLocalM: TElemMatrix;
  KeT: array[1..8, 1..12] of Double; // scratch: KeLocal * T
  i, jc, k, blk: Integer;
  rel: TVec3;
begin
  // --- local in-plane basis: ex along edge 1->2, ez the element normal
  // from edge1 x edge2 (edge1 = 1->2, edge2 = 1->4 -- using the two
  // edges off node 1, not a diagonal, so a non-planar or badly-wound
  // quad still produces *some* normal rather than a near-zero cross
  // product from near-parallel diagonals), ey completing a right-handed
  // orthonormal set. Same construction style as BeamStiffness3D's Lam.
  edge1[0] := x2 - x1; edge1[1] := y2 - y1; edge1[2] := z2 - z1;
  edge2[0] := x4 - x1; edge2[1] := y4 - y1; edge2[2] := z4 - z1;
  if VNorm(edge1) <= 0 then
    raise Exception.Create('Quad membrane element has a zero-length 1-2 edge (coincident nodes)');
  ex := VNormalize(edge1);
  nrm := VCross(edge1, edge2);
  if VNorm(nrm) <= 0 then
    raise Exception.Create('Quad membrane element is degenerate (nodes 1, 2, 4 are collinear)');
  ez := VNormalize(nrm);
  ey := VCross(ez, ex); // unit length: ez, ex already orthonormal by construction

  // --- project all 4 nodes into the local (x,y) plane ---
  lx[1] := 0; ly[1] := 0; // node 1 is the local origin by construction
  rel[0] := x2 - x1; rel[1] := y2 - y1; rel[2] := z2 - z1;
  lx[2] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[2] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];
  rel[0] := x3 - x1; rel[1] := y3 - y1; rel[2] := z3 - z1;
  lx[3] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[3] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];
  rel[0] := x4 - x1; rel[1] := y4 - y1; rel[2] := z4 - z1;
  lx[4] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[4] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];

  KeLocalM := QuadMembraneStiffnessLocal(E, Nu, Thickness,
    lx[1], ly[1], lx[2], ly[2], lx[3], ly[3], lx[4], ly[4]);
  for i := 1 to 8 do
    for jc := 1 to 8 do
      KeLocal[i, jc] := KeLocalM[i, jc];

  // --- transform: T maps global (x,y,z)*4 -> local (u,v)*4 ---
  for i := 1 to 8 do
    for jc := 1 to 12 do
      T[i, jc] := 0;
  for blk := 0 to 3 do
  begin
    T[2*blk + 1, 3*blk + 1] := ex[0]; T[2*blk + 1, 3*blk + 2] := ex[1]; T[2*blk + 1, 3*blk + 3] := ex[2];
    T[2*blk + 2, 3*blk + 1] := ey[0]; T[2*blk + 2, 3*blk + 2] := ey[1]; T[2*blk + 2, 3*blk + 3] := ey[2];
  end;

  // KeT = KeLocal * T  (8x12)
  for i := 1 to 8 do
    for jc := 1 to 12 do
    begin
      KeT[i, jc] := 0;
      for k := 1 to 8 do
        KeT[i, jc] := KeT[i, jc] + KeLocal[i, k] * T[k, jc];
    end;

  // Result = T^T * KeT  (12x12)
  Result := NewElemMatrix(12);
  for i := 1 to 12 do
    for jc := 1 to 12 do
    begin
      Result[i, jc] := 0;
      for k := 1 to 8 do
        Result[i, jc] := Result[i, jc] + T[k, i] * KeT[k, jc]; // T^T[i,k] = T[k,i]
    end;
end;

function QuadBendingStiffnessLocal(E, Nu, Thickness: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;
var
  px, py: array[1..4] of Double;
  // Edge midpoint discrete-Kirchhoff operators: Op[eg][1,col] and
  // Op[eg][2,col] give the physical-x and physical-y components of the
  // constrained gradient(w) at edge eg's midpoint, as linear functions
  // of the 12 local corner dof.
  Op: array[1..4, 1..2, 1..12] of Double;
  edgeStart, edgeEnd: array[1..4] of Integer;
  eg, i, nodeIdx, col, g: Integer;
  ex, tangent, normal: array[0..1] of Double;
  edgeLen: Double;
  sf4: TQuadShapeFuncs;
  sf8: TQuad8ShapeFuncs;
  gp: TGaussPointArray;
  J11, J12, J21, J22, detJ, invJ11, invJ12, invJ21, invJ22: Double;
  NatGradWx, NatGradWy: array[1..12, 1..2] of Double; // [.,1]=d/dxi [.,2]=d/deta
  PhysWx_x, PhysWx_y, PhysWy_x, PhysWy_y: array[1..12] of Double;
  B: array[1..3, 1..12] of Double;
  Dfac: Double;
  D: array[1..3, 1..3] of Double;
  BtD: array[1..12, 1..3] of Double;
  acc: Double;
  jc, k: Integer;
begin
  px[1] := x1; py[1] := y1;
  px[2] := x2; py[2] := y2;
  px[3] := x3; py[3] := y3;
  px[4] := x4; py[4] := y4;

  // --- build the 4 discrete-Kirchhoff edge operators (geometry-only,
  // independent of the Gauss point) ---
  edgeStart[1] := 1; edgeEnd[1] := 2;
  edgeStart[2] := 2; edgeEnd[2] := 3;
  edgeStart[3] := 3; edgeEnd[3] := 4;
  edgeStart[4] := 4; edgeEnd[4] := 1;

  for eg := 1 to 4 do
  begin
    ex[0] := px[edgeEnd[eg]] - px[edgeStart[eg]];
    ex[1] := py[edgeEnd[eg]] - py[edgeStart[eg]];
    edgeLen := Sqrt(ex[0]*ex[0] + ex[1]*ex[1]);
    if edgeLen <= 0 then
      raise Exception.Create('DKQ plate element has a zero-length edge (coincident nodes)');
    tangent[0] := ex[0] / edgeLen; tangent[1] := ex[1] / edgeLen;
    normal[0] := -tangent[1];      normal[1] := tangent[0];

    for i := 1 to 2 do
      for col := 1 to 12 do
        Op[eg, i, col] := 0;

    // g_s(mid) = 3(w_end-w_start)/(2L) - (g_s(start)+g_s(end))/4
    // g_n(mid) = (g_n(start)+g_n(end))/2
    // grad(w)(mid) = tangent*g_s(mid) + normal*g_n(mid)
    Op[eg, 1, 3*(edgeStart[eg]-1)+1] := Op[eg, 1, 3*(edgeStart[eg]-1)+1] - 1.5*tangent[0]/edgeLen;
    Op[eg, 2, 3*(edgeStart[eg]-1)+1] := Op[eg, 2, 3*(edgeStart[eg]-1)+1] - 1.5*tangent[1]/edgeLen;
    Op[eg, 1, 3*(edgeEnd[eg]-1)+1]   := Op[eg, 1, 3*(edgeEnd[eg]-1)+1]   + 1.5*tangent[0]/edgeLen;
    Op[eg, 2, 3*(edgeEnd[eg]-1)+1]   := Op[eg, 2, 3*(edgeEnd[eg]-1)+1]   + 1.5*tangent[1]/edgeLen;

    for i := 1 to 2 do
    begin
      if i = 1 then nodeIdx := edgeStart[eg] else nodeIdx := edgeEnd[eg];
      // theta_x-like dof (w_x, local column offset +2)
      Op[eg, 1, 3*(nodeIdx-1)+2] := Op[eg, 1, 3*(nodeIdx-1)+2]
        - 0.25*tangent[0]*tangent[0] + 0.5*normal[0]*normal[0];
      Op[eg, 2, 3*(nodeIdx-1)+2] := Op[eg, 2, 3*(nodeIdx-1)+2]
        - 0.25*tangent[1]*tangent[0] + 0.5*normal[1]*normal[0];
      // theta_y-like dof (w_y, local column offset +3)
      Op[eg, 1, 3*(nodeIdx-1)+3] := Op[eg, 1, 3*(nodeIdx-1)+3]
        - 0.25*tangent[0]*tangent[1] + 0.5*normal[0]*normal[1];
      Op[eg, 2, 3*(nodeIdx-1)+3] := Op[eg, 2, 3*(nodeIdx-1)+3]
        - 0.25*tangent[1]*tangent[1] + 0.5*normal[1]*normal[1];
    end;
  end;

  Dfac := (Thickness*Thickness*Thickness / 12.0) * (E / (1.0 - Nu*Nu));
  D[1,1] := Dfac;       D[1,2] := Dfac*Nu;    D[1,3] := 0;
  D[2,1] := Dfac*Nu;    D[2,2] := Dfac;       D[2,3] := 0;
  D[3,1] := 0;          D[3,2] := 0;          D[3,3] := Dfac*(1.0-Nu)/2.0;

  Result := NewElemMatrix(12);
  for i := 1 to 12 do
    for jc := 1 to 12 do
      Result[i, jc] := 0;

  gp := QuadGaussPoints2x2;
  for g := 0 to NGaussPlate - 1 do
  begin
    sf4 := QuadShapeFuncsAt(gp[g].Xi, gp[g].Eta);
    sf8 := Quad8ShapeFuncsAt(gp[g].Xi, gp[g].Eta);

    J11 := 0; J12 := 0; J21 := 0; J22 := 0;
    for i := 1 to 4 do
    begin
      J11 := J11 + sf4.dNdXi[i]  * px[i];
      J12 := J12 + sf4.dNdXi[i]  * py[i];
      J21 := J21 + sf4.dNdEta[i] * px[i];
      J22 := J22 + sf4.dNdEta[i] * py[i];
    end;
    detJ := J11*J22 - J12*J21;
    if detJ <= 0 then
      raise Exception.Create('DKQ plate element has non-positive Jacobian determinant (inverted or degenerate shape)');
    invJ11 :=  J22/detJ; invJ12 := -J12/detJ;
    invJ21 := -J21/detJ; invJ22 :=  J11/detJ;

    for col := 1 to 12 do
    begin
      NatGradWx[col, 1] := 0; NatGradWx[col, 2] := 0;
      NatGradWy[col, 1] := 0; NatGradWy[col, 2] := 0;
    end;

    // corner contribution: w_x field directly carries node i's w_x dof
    // (weighted by the Q8 corner shape function), likewise w_y.
    for i := 1 to 4 do
    begin
      col := 3*(i-1) + 2; // w_x dof of node i
      NatGradWx[col, 1] := NatGradWx[col, 1] + sf8.dNdXi[i];
      NatGradWx[col, 2] := NatGradWx[col, 2] + sf8.dNdEta[i];
      col := 3*(i-1) + 3; // w_y dof of node i
      NatGradWy[col, 1] := NatGradWy[col, 1] + sf8.dNdXi[i];
      NatGradWy[col, 2] := NatGradWy[col, 2] + sf8.dNdEta[i];
    end;

    // midpoint contribution: each edge's constrained gradient(w),
    // weighted by that midpoint's Q8 shape function.
    for eg := 1 to 4 do
      for col := 1 to 12 do
      begin
        NatGradWx[col, 1] := NatGradWx[col, 1] + sf8.dNdXi[4+eg]  * Op[eg, 1, col];
        NatGradWx[col, 2] := NatGradWx[col, 2] + sf8.dNdEta[4+eg] * Op[eg, 1, col];
        NatGradWy[col, 1] := NatGradWy[col, 1] + sf8.dNdXi[4+eg]  * Op[eg, 2, col];
        NatGradWy[col, 2] := NatGradWy[col, 2] + sf8.dNdEta[4+eg] * Op[eg, 2, col];
      end;

    for col := 1 to 12 do
    begin
      PhysWx_x[col] := invJ11*NatGradWx[col,1] + invJ12*NatGradWx[col,2]; // d(w,x)/dx
      PhysWx_y[col] := invJ21*NatGradWx[col,1] + invJ22*NatGradWx[col,2]; // d(w,x)/dy
      PhysWy_x[col] := invJ11*NatGradWy[col,1] + invJ12*NatGradWy[col,2]; // d(w,y)/dx
      PhysWy_y[col] := invJ21*NatGradWy[col,1] + invJ22*NatGradWy[col,2]; // d(w,y)/dy
    end;

    for col := 1 to 12 do
    begin
      B[1, col] := PhysWx_x[col];                  // kappa_xx = d(w,x)/dx
      B[2, col] := PhysWy_y[col];                   // kappa_yy = d(w,y)/dy
      B[3, col] := PhysWx_y[col] + PhysWy_x[col];   // 2*kappa_xy
    end;

    // BtD = B^T * D  (12x3)
    for i := 1 to 12 do
      for jc := 1 to 3 do
      begin
        BtD[i, jc] := 0;
        for k := 1 to 3 do
          BtD[i, jc] := BtD[i, jc] + B[k, i] * D[k, jc];
      end;

    // Result += (BtD * B) * detJ * weight
    for i := 1 to 12 do
      for jc := 1 to 12 do
      begin
        acc := 0;
        for k := 1 to 3 do
          acc := acc + BtD[i, k] * B[k, jc];
        Result[i, jc] := Result[i, jc] + acc * detJ * gp[g].Weight;
      end;
  end;
end;

function QuadShellStiffnessLocal(E, Nu, Thickness, DrillFactor: Double;
  x1, y1, x2, y2, x3, y3, x4, y4: Double): TElemMatrix;
const
  // Sign/permutation remap from DKQ's local bending dof [w,w_x,w_y]
  // (indices 1,2,3 within each node's 3-block of Kb) to the shell's
  // [w,rx,ry] (indices 1,2,3 here, landing at shell offsets 3,4,5):
  // rx=+w_y (source index 3, sign +1), ry=-w_x (source index 2, sign -1).
  // Derived from beam's verified ry=-dw/dx and the general
  // rigid-rotation relation rx=+dw/dy -- see this function's interface
  // comment for the derivation.
  KbSrcOffset: array[1..3] of Integer = (1, 3, 2);
  KbSign: array[1..3] of Double = (1.0, 1.0, -1.0);
var
  Km: TElemMatrix; // 8x8, local dof [u,v]*4
  Kb: TElemMatrix; // 12x12, local dof [w,w_x,w_y]*4
  i, jc, nodeA, nodeB, p, q, srcRow, srcCol, destRow, destCol: Integer;
  diagSum, kDrill: Double;
begin
  Km := QuadMembraneStiffnessLocal(E, Nu, Thickness, x1, y1, x2, y2, x3, y3, x4, y4);
  Kb := QuadBendingStiffnessLocal(E, Nu, Thickness, x1, y1, x2, y2, x3, y3, x4, y4);

  Result := NewElemMatrix(24);
  for i := 1 to 24 do
    for jc := 1 to 24 do
      Result[i, jc] := 0;

  // --- membrane block: node dof [u,v] (Km offsets 1,2) -> shell
  // offsets [1,2] (u,v), no sign change. ---
  for nodeA := 0 to 3 do
    for nodeB := 0 to 3 do
      for p := 1 to 2 do
        for q := 1 to 2 do
        begin
          srcRow := 2*nodeA + p;
          srcCol := 2*nodeB + q;
          destRow := 6*nodeA + p;
          destCol := 6*nodeB + q;
          Result[destRow, destCol] := Km[srcRow, srcCol];
        end;

  // --- bending block: node dof [w,w_x,w_y] (Kb offsets 1,2,3) -> shell
  // offsets [3,4,5] (w,rx,ry) via the KbSrcOffset/KbSign remap above. ---
  for nodeA := 0 to 3 do
    for nodeB := 0 to 3 do
      for p := 1 to 3 do
        for q := 1 to 3 do
        begin
          srcRow := 3*nodeA + KbSrcOffset[p];
          srcCol := 3*nodeB + KbSrcOffset[q];
          destRow := 6*nodeA + 2 + p;
          destCol := 6*nodeB + 2 + q;
          Result[destRow, destCol] := KbSign[p] * KbSign[q] * Kb[srcRow, srcCol];
        end;

  // --- drilling (rz, shell offset 6): neither sub-element constrains
  // in-plane corner rotation, so add a small artificial diagonal
  // penalty per node, sized off the membrane matrix's own stiffness
  // scale (see this function's interface comment). ---
  diagSum := 0;
  for i := 1 to 8 do
    diagSum := diagSum + Km[i, i];
  kDrill := DrillFactor * (diagSum / 8.0);
  for nodeA := 0 to 3 do
    Result[6*nodeA + 6, 6*nodeA + 6] := kDrill;
end;

function QuadShellStiffness3D(E, Nu, Thickness, DrillFactor: Double;
  x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4: Double): TElemMatrix;
var
  ex, ey, ez, edge1, edge2, nrm, rel: TVec3;
  lx, ly: array[1..4] of Double;
  KeLocal: TElemMatrix; // 24x24
  T: array[1..24, 1..24] of Double;
  KeT: array[1..24, 1..24] of Double;
  i, jc, k, blk: Integer;
begin
  // Same local-basis construction as QuadMembraneStiffness3D (see its
  // comments); duplicated rather than shared because it's five short
  // lines and pulling it into its own function would need TVec3
  // exposed beyond this unit for no real benefit yet.
  edge1[0] := x2 - x1; edge1[1] := y2 - y1; edge1[2] := z2 - z1;
  edge2[0] := x4 - x1; edge2[1] := y4 - y1; edge2[2] := z4 - z1;
  if VNorm(edge1) <= 0 then
    raise Exception.Create('Quad shell element has a zero-length 1-2 edge (coincident nodes)');
  ex := VNormalize(edge1);
  nrm := VCross(edge1, edge2);
  if VNorm(nrm) <= 0 then
    raise Exception.Create('Quad shell element is degenerate (nodes 1, 2, 4 are collinear)');
  ez := VNormalize(nrm);
  ey := VCross(ez, ex);

  lx[1] := 0; ly[1] := 0;
  rel[0] := x2 - x1; rel[1] := y2 - y1; rel[2] := z2 - z1;
  lx[2] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[2] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];
  rel[0] := x3 - x1; rel[1] := y3 - y1; rel[2] := z3 - z1;
  lx[3] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[3] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];
  rel[0] := x4 - x1; rel[1] := y4 - y1; rel[2] := z4 - z1;
  lx[4] := rel[0]*ex[0]+rel[1]*ex[1]+rel[2]*ex[2];
  ly[4] := rel[0]*ey[0]+rel[1]*ey[1]+rel[2]*ey[2];

  KeLocal := QuadShellStiffnessLocal(E, Nu, Thickness, DrillFactor,
    lx[1], ly[1], lx[2], ly[2], lx[3], ly[3], lx[4], ly[4]);

  // T: global (x,y,z,rx,ry,rz)*4 -> local (u,v,w,rx,ry,rz)*4. Rotation
  // dof transform by the same Lam as translations do (a proper vector
  // under a pure orthonormal-frame rotation) -- each node's 6x6 block
  // is block-diagonal [[Lam,0],[0,Lam]].
  for i := 1 to 24 do
    for jc := 1 to 24 do
      T[i, jc] := 0;
  for blk := 0 to 3 do
  begin
    T[6*blk+1, 6*blk+1] := ex[0]; T[6*blk+1, 6*blk+2] := ex[1]; T[6*blk+1, 6*blk+3] := ex[2];
    T[6*blk+2, 6*blk+1] := ey[0]; T[6*blk+2, 6*blk+2] := ey[1]; T[6*blk+2, 6*blk+3] := ey[2];
    T[6*blk+3, 6*blk+1] := ez[0]; T[6*blk+3, 6*blk+2] := ez[1]; T[6*blk+3, 6*blk+3] := ez[2];
    T[6*blk+4, 6*blk+4] := ex[0]; T[6*blk+4, 6*blk+5] := ex[1]; T[6*blk+4, 6*blk+6] := ex[2];
    T[6*blk+5, 6*blk+4] := ey[0]; T[6*blk+5, 6*blk+5] := ey[1]; T[6*blk+5, 6*blk+6] := ey[2];
    T[6*blk+6, 6*blk+4] := ez[0]; T[6*blk+6, 6*blk+5] := ez[1]; T[6*blk+6, 6*blk+6] := ez[2];
  end;

  // KeT = KeLocal * T
  for i := 1 to 24 do
    for jc := 1 to 24 do
    begin
      KeT[i, jc] := 0;
      for k := 1 to 24 do
        KeT[i, jc] := KeT[i, jc] + KeLocal[i, k] * T[k, jc];
    end;

  // Result = T^T * KeT
  Result := NewElemMatrix(24);
  for i := 1 to 24 do
    for jc := 1 to 24 do
    begin
      Result[i, jc] := 0;
      for k := 1 to 24 do
        Result[i, jc] := Result[i, jc] + T[k, i] * KeT[k, jc];
    end;
end;

function ElementStiffnessFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement): TElemMatrix;
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2, n3, n4: TNode;
  G: Double;
  refVec: array[0..2] of Double;
begin
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  if el.ElementType = 'truss' then
    Result := TrussStiffness3D(mat.E, prop.Area, n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z)
  else if el.ElementType = 'shellq4' then
  begin
    n3 := Model.Nodes[NodeIdx[el.NodeIds[2]]];
    n4 := Model.Nodes[NodeIdx[el.NodeIds[3]]];
    Result := QuadShellStiffness3D(mat.E, mat.Nu, prop.Thickness, ShellDrillFactor,
      n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z, n3.X, n3.Y, n3.Z, n4.X, n4.Y, n4.Z);
  end
  else // 'beam' -- fem_validate guarantees no other type reaches here
  begin
    G := mat.E / (2.0 * (1.0 + mat.Nu));
    if el.HasRefVec then
    begin
      refVec[0] := el.RefVec[0]; refVec[1] := el.RefVec[1]; refVec[2] := el.RefVec[2];
    end
    else
    begin
      refVec[0] := 0; refVec[1] := 0; refVec[2] := 0;
    end;
    Result := BeamStiffness3D(mat.E, G, prop.Area, prop.Iy, prop.Iz, prop.J,
      n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z, refVec);
  end;
end;

end.
