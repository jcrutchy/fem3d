unit fem_elements;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, Math, SysUtils;

type
  // TElemMatrix is fem_types.TDenseMatrix under another name for
  // readability at call sites (an "element stiffness matrix" is exactly a
  // dense matrix, sized 6 for a truss, 12 for a beam).
  TElemMatrix = TDenseMatrix;

function NewElemMatrix(N: Integer): TElemMatrix;

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

function ElementStiffnessFor(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const el: TElement): TElemMatrix;
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2: TNode;
  G: Double;
  refVec: array[0..2] of Double;
begin
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  if el.ElementType = 'truss' then
    Result := TrussStiffness3D(mat.E, prop.Area, n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z)
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
