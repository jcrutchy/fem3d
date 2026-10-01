unit fem_matrix;

{$mode objfpc}{$H+}

// Shared small-matrix / vector utilities for the FEM suite.
//
// Everything that used to be hand-rolled inline in fem_elements (3D vector
// helpers, local-frame construction, T^T*K*T transforms, 2x2 Jacobian
// inverses, B^T*D*B accumulation) lives here once, so there is exactly one
// place to read, test and optimise.
//
// Conventions (same as the rest of the suite):
//   * TDenseMatrix is 1-based: a matrix of Rows x Cols is allocated
//     (Rows+1) x (Cols+1) and row/column 0 is unused.
//   * Nothing here knows about elements, materials or models.
//
// Performance notes:
//   * The big win is structural, not instruction-level: element
//     transformation matrices are block-diagonal (a 3x3 direction-cosine
//     block repeated per node/dof triple), so TransformBlockDiag applies the
//     blocks directly instead of multiplying dense 48x48 matrices
//     (~16x fewer flops for a Q8 shell).
//   * The remaining dense inner loops go through two tiny kernels
//     (RowAxpy, RowDot). RowAxpy is the only routine with optional x86-64
//     SSE2 assembly (Linux + Win64); everything else is plain Pascal and
//     identical on every platform. Build with -dFEM_USE_ASM to enable it.
//     Its SSE2 version does the same mul-then-add per element as the
//     Pascal loop (no FMA, no reassociation), so results are bit-identical
//     either way (matrix_test verifies this). It is OFF by default: on this
//     code it speeds the 48x48 shell transform ~20% but a whole Q8 element
//     only ~0-5% (the time is in the Gauss-point loops, not the transform),
//     and the Win64 entry path could not be exercised where it was written.

// Optional SSE2 kernel: opt-in with -dFEM_USE_ASM (x86-64 Linux or Win64
// only; anywhere else the define is ignored and the Pascal loop is used).
// Off by default -- measured gain on whole-element stiffness is ~0-5%, see
// the header notes.
{$IF defined(FEM_USE_ASM) and defined(CPUX86_64) and (defined(LINUX) or defined(WIN64))}
  {$DEFINE FEM_ASM}
{$ENDIF}

interface

uses
  fem_types, SysUtils;

type
  TVec3 = array[0..2] of Double;

  // Right-handed orthonormal local frame; rows of the direction-cosine
  // matrix Lam (local = Lam * global).
  TFrame3 = record
    ex, ey, ez: TVec3;
  end;

// ---------------------------------------------------------------------------
// 3D vectors
// ---------------------------------------------------------------------------
function Vec3(x, y, z: Double): TVec3;
function VSub(const a, b: TVec3): TVec3;
function VDot(const a, b: TVec3): Double;
function VCross(const a, b: TVec3): TVec3;
function VNorm(const a: TVec3): Double;
// Raises Exception('Cannot normalize a zero-length vector ...') on |a| = 0.
function VNormalize(const a: TVec3): TVec3;

// ---------------------------------------------------------------------------
// Local frames
// ---------------------------------------------------------------------------

// Frame for a flat quad from three non-collinear corners: ex along p1->p2,
// ez the normal of (p1->p2) x (p1->p4), ey = ez x ex. The two messages are
// raised verbatim (as Exception) for a zero-length 1-2 edge and for
// collinear corners respectively, so each element type keeps its own
// wording.
function QuadFrame(const p1, p2, p4: TVec3;
  const MsgZeroEdge, MsgDegenerate: string): TFrame3;

// In-plane coordinates (u along ex, v along ey) of point p relative to
// origin o.
procedure ProjectToFrame(const F: TFrame3; const o, p: TVec3; out u, v: Double);

// ---------------------------------------------------------------------------
// Small closed-form inverses
// ---------------------------------------------------------------------------

// 2x2 inverse. Returns the determinant. If det = 0 the inverse outputs are
// set to 0 (callers test the determinant themselves and raise with their
// own, element-specific message).
function Inv2x2(a11, a12, a21, a22: Double;
  out i11, i12, i21, i22: Double): Double;

// 3x3 inverse (row-major, 0-based). Returns the determinant; if det = 0 the
// output is all zeros.
function Inv3x3(const a: array of Double; var inv: array of Double): Double;

// ---------------------------------------------------------------------------
// Structured element transforms
// ---------------------------------------------------------------------------

// Kg = T^T * Kl * T, where T = blockdiag(Lam, ..., Lam) with NBlocks copies
// of the M x 3 matrix Lam (rows = first M of F.ex, F.ey, F.ez).
//   M = 3: full 3D frame (beam, shell node = 2 blocks of 3: trans + rot).
//   M = 2: in-plane only (membrane: local (u,v) <- global (x,y,z)).
// Kl is (M*NBlocks) square, the result is (3*NBlocks) square, both 1-based.
function TransformBlockDiag(const Kl: TDenseMatrix; const F: TFrame3;
  M, NBlocks: Integer): TDenseMatrix;

// Ke += Scale * B^T * D * B for one integration point.
//   B: NR x NC, D: NR x NR, both row-major 1-based Pascal static arrays
//   (array[1..NR, 1..NC] / array[1..NR, 1..NR]) passed untyped so one
//   routine serves every element's differently-sized arrays.
//   Ke: (NC) square TDenseMatrix, accumulated into.
procedure AccumBtDB(Ke: TDenseMatrix; const B; const D; NR, NC: Integer;
  Scale: Double);

// ---------------------------------------------------------------------------
// General dense helpers (1-based TDenseMatrix; need not be square)
// ---------------------------------------------------------------------------
function NewMatrix(Rows, Cols: Integer): TDenseMatrix;
function MatRows(const A: TDenseMatrix): Integer;
function MatCols(const A: TDenseMatrix): Integer;
function MatTranspose(const A: TDenseMatrix): TDenseMatrix;
function MatMul(const A, B: TDenseMatrix): TDenseMatrix;      // A * B
function MatMulAtB(const A, B: TDenseMatrix): TDenseMatrix;   // A^T * B
function MatVec(const A: TDenseMatrix; const x: TDoubleArray): TDoubleArray;
// Gauss-Jordan with partial pivoting. False if a pivot magnitude falls to
// or below Tol * (largest entry of A); Inv is then undefined.
function MatInverse(const A: TDenseMatrix; out Inv: TDenseMatrix;
  Tol: Double = 1E-14): Boolean;

// ---------------------------------------------------------------------------
// Kernels (the only routines with optional assembly)
// ---------------------------------------------------------------------------
// Dst[0..N-1] += Alpha * Src[0..N-1]
procedure RowAxpy(Dst, Src: PDouble; Alpha: Double; N: Integer);
// sum of A[i]*B[i], i = 0..N-1
function RowDot(A, B: PDouble; N: Integer): Double;
// True when the assembly kernels are compiled in and active.
function MatrixKernelsAreAsm: Boolean;

implementation

// ---------------------------------------------------------------------------
// 3D vectors
// ---------------------------------------------------------------------------
function Vec3(x, y, z: Double): TVec3;
begin
  Result[0] := x; Result[1] := y; Result[2] := z;
end;

function VSub(const a, b: TVec3): TVec3;
begin
  Result[0] := a[0] - b[0]; Result[1] := a[1] - b[1]; Result[2] := a[2] - b[2];
end;

function VDot(const a, b: TVec3): Double;
begin
  Result := a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
end;

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

// ---------------------------------------------------------------------------
// Local frames
// ---------------------------------------------------------------------------
function QuadFrame(const p1, p2, p4: TVec3;
  const MsgZeroEdge, MsgDegenerate: string): TFrame3;
var
  edge1, edge2, nrm: TVec3;
begin
  // Uses the two edges off node 1 (not a diagonal) so a non-planar or
  // badly-wound quad still yields *some* normal rather than a near-zero
  // cross product from near-parallel diagonals.
  edge1 := VSub(p2, p1);
  edge2 := VSub(p4, p1);
  if VNorm(edge1) <= 0 then
    raise Exception.Create(MsgZeroEdge);
  Result.ex := VNormalize(edge1);
  nrm := VCross(edge1, edge2);
  if VNorm(nrm) <= 0 then
    raise Exception.Create(MsgDegenerate);
  Result.ez := VNormalize(nrm);
  Result.ey := VCross(Result.ez, Result.ex); // unit: ez, ex already orthonormal
end;

procedure ProjectToFrame(const F: TFrame3; const o, p: TVec3; out u, v: Double);
var
  rel: TVec3;
begin
  rel := VSub(p, o);
  u := VDot(rel, F.ex);
  v := VDot(rel, F.ey);
end;

// ---------------------------------------------------------------------------
// Small closed-form inverses
// ---------------------------------------------------------------------------
function Inv2x2(a11, a12, a21, a22: Double;
  out i11, i12, i21, i22: Double): Double;
begin
  Result := a11 * a22 - a12 * a21;
  if Result = 0.0 then
  begin
    i11 := 0; i12 := 0; i21 := 0; i22 := 0;
    Exit;
  end;
  i11 :=  a22 / Result; i12 := -a12 / Result;
  i21 := -a21 / Result; i22 :=  a11 / Result;
end;

function Inv3x3(const a: array of Double; var inv: array of Double): Double;
var
  c00, c01, c02: Double;
  k: Integer;
begin
  // cofactors of the first row give the determinant by expansion
  c00 := a[4] * a[8] - a[5] * a[7];
  c01 := a[5] * a[6] - a[3] * a[8];
  c02 := a[3] * a[7] - a[4] * a[6];
  Result := a[0] * c00 + a[1] * c01 + a[2] * c02;
  if Result = 0.0 then
  begin
    for k := 0 to 8 do inv[k] := 0;
    Exit;
  end;
  // inverse = adjugate / det
  inv[0] := c00 / Result;
  inv[1] := (a[2] * a[7] - a[1] * a[8]) / Result;
  inv[2] := (a[1] * a[5] - a[2] * a[4]) / Result;
  inv[3] := c01 / Result;
  inv[4] := (a[0] * a[8] - a[2] * a[6]) / Result;
  inv[5] := (a[2] * a[3] - a[0] * a[5]) / Result;
  inv[6] := c02 / Result;
  inv[7] := (a[1] * a[6] - a[0] * a[7]) / Result;
  inv[8] := (a[0] * a[4] - a[1] * a[3]) / Result;
end;

// ---------------------------------------------------------------------------
// Structured element transforms
// ---------------------------------------------------------------------------
function TransformBlockDiag(const Kl: TDenseMatrix; const F: TFrame3;
  M, NBlocks: Integer): TDenseMatrix;
var
  Lam: array[0..2, 0..2] of Double;
  n, N3: Integer;
  KT: array of Double; // n x N3 row-major: Kl * T
  i, jb, ib, r, k: Integer;
  pk: PDouble;         // current row of Kl, 0-based view
  po: PDouble;         // current row of KT
  l00, l01, l02, l10, l11, l12, l20, l21, l22: Double;
  a0, a1, a2: Double;
begin
  if (M < 1) or (M > 3) then
    raise Exception.Create('TransformBlockDiag: M must be 1..3');
  n := M * NBlocks;
  N3 := 3 * NBlocks;
  if (Length(Kl) <> n + 1) then
    raise Exception.CreateFmt('TransformBlockDiag: Kl is %d square, expected %d',
      [Length(Kl) - 1, n]);

  for k := 0 to 2 do
  begin
    Lam[0][k] := F.ex[k];
    Lam[1][k] := F.ey[k];
    Lam[2][k] := F.ez[k];
  end;
  l00 := Lam[0][0]; l01 := Lam[0][1]; l02 := Lam[0][2];
  l10 := Lam[1][0]; l11 := Lam[1][1]; l12 := Lam[1][2];
  l20 := Lam[2][0]; l21 := Lam[2][1]; l22 := Lam[2][2];

  // Stage 1: KT = Kl * T. Column block jb of T has Lam in rows
  // M*jb+1..M*jb+M, so each output triple is a (1 x M)(M x 3) product.
  // Written out per M so the compiler sees straight-line code.
  SetLength(KT, n * N3);
  for i := 1 to n do
  begin
    pk := @Kl[i][1];
    po := @KT[(i - 1) * N3];
    if M = 3 then
      for jb := 0 to NBlocks - 1 do
      begin
        a0 := pk[3 * jb]; a1 := pk[3 * jb + 1]; a2 := pk[3 * jb + 2];
        po[3 * jb]     := a0 * l00 + a1 * l10 + a2 * l20;
        po[3 * jb + 1] := a0 * l01 + a1 * l11 + a2 * l21;
        po[3 * jb + 2] := a0 * l02 + a1 * l12 + a2 * l22;
      end
    else if M = 2 then
      for jb := 0 to NBlocks - 1 do
      begin
        a0 := pk[2 * jb]; a1 := pk[2 * jb + 1];
        po[3 * jb]     := a0 * l00 + a1 * l10;
        po[3 * jb + 1] := a0 * l01 + a1 * l11;
        po[3 * jb + 2] := a0 * l02 + a1 * l12;
      end
    else
      for jb := 0 to NBlocks - 1 do
      begin
        a0 := pk[jb];
        po[3 * jb]     := a0 * l00;
        po[3 * jb + 1] := a0 * l01;
        po[3 * jb + 2] := a0 * l02;
      end;
  end;

  // Stage 2: Kg = T^T * KT. Row 3*ib+r of Kg is the M-term combination
  // sum_k Lam[k][r] * (KT row M*ib+k) -- whole-row AXPYs (long, contiguous:
  // this is where the SSE2 RowAxpy earns its keep).
  Result := NewDenseMatrix(N3);
  for ib := 0 to NBlocks - 1 do
    for r := 0 to 2 do
      for k := 0 to M - 1 do
        RowAxpy(@Result[3 * ib + r + 1][1], @KT[(M * ib + k) * N3], Lam[k][r], N3);
end;

procedure AccumBtDB(Ke: TDenseMatrix; const B; const D; NR, NC: Integer;
  Scale: Double);
const
  MaxNC = 48;
  MaxNR = 3;
var
  pB, pD: PDouble;
  BtD: array[0..MaxNC * MaxNR - 1] of Double; // NC x NR row-major
  i, j, k: Integer;
  s: Double;
begin
  if (NR > MaxNR) or (NC > MaxNC) then
    raise Exception.Create('AccumBtDB: dimensions exceed compiled-in limits');
  pB := @B;
  pD := @D;

  // BtD = B^T * D
  for i := 0 to NC - 1 do
    for j := 0 to NR - 1 do
    begin
      s := 0.0;
      for k := 0 to NR - 1 do
        s := s + pB[k * NC + i] * pD[k * NR + j];
      BtD[i * NR + j] := s;
    end;

  // K += Scale * BtD * B
  for i := 0 to NC - 1 do
    for j := 0 to NC - 1 do
    begin
      s := 0.0;
      for k := 0 to NR - 1 do
        s := s + BtD[i * NR + k] * pB[k * NC + j];
      Ke[i + 1][j + 1] := Ke[i + 1][j + 1] + s * Scale;
    end;
end;

// ---------------------------------------------------------------------------
// Kernels
// ---------------------------------------------------------------------------
{$IFDEF FEM_ASM}
{$ASMMODE INTEL}
// Dst[0..N-1] += Alpha * Src[0..N-1], SSE2 (baseline on every x86-64 CPU),
// unaligned loads/stores, 4 doubles per iteration then a 2- and 1-element
// tail. Separate mulpd/addpd (no FMA) keeps it bit-identical to the Pascal
// loop. Only caller-saved registers are used (rax, rcx, rdx, r8, xmm0-xmm3)
// so the same body is legal under both the SysV and Win64 ABIs; only the
// entry shuffle differs.
procedure RowAxpy(Dst, Src: PDouble; Alpha: Double; N: Integer); assembler; nostackframe;
asm
  {$IFDEF WIN64}
  // rcx=Dst, rdx=Src, xmm2=Alpha, r9d=N
  movapd  xmm0, xmm2
  mov     r8d, r9d
  {$ELSE}
  // SysV: rdi=Dst, rsi=Src, xmm0=Alpha, edx=N
  mov     r8d, edx
  mov     rcx, rdi
  mov     rdx, rsi
  {$ENDIF}
  // now: rcx=Dst, rdx=Src, xmm0=Alpha, r8d=N
  unpcklpd xmm0, xmm0
@loop4:
  cmp     r8d, 4
  jl      @tail2
  movupd  xmm1, [rdx]
  movupd  xmm2, [rdx + 16]
  mulpd   xmm1, xmm0
  mulpd   xmm2, xmm0
  movupd  xmm3, [rcx]
  addpd   xmm3, xmm1
  movupd  [rcx], xmm3
  movupd  xmm3, [rcx + 16]
  addpd   xmm3, xmm2
  movupd  [rcx + 16], xmm3
  add     rcx, 32
  add     rdx, 32
  sub     r8d, 4
  jmp     @loop4
@tail2:
  cmp     r8d, 2
  jl      @tail1
  movupd  xmm1, [rdx]
  mulpd   xmm1, xmm0
  movupd  xmm3, [rcx]
  addpd   xmm3, xmm1
  movupd  [rcx], xmm3
  add     rcx, 16
  add     rdx, 16
  sub     r8d, 2
@tail1:
  test    r8d, r8d
  jle     @done
  movsd   xmm1, [rdx]
  mulsd   xmm1, xmm0
  addsd   xmm1, [rcx]
  movsd   [rcx], xmm1
@done:
end;
{$ELSE}
procedure RowAxpy(Dst, Src: PDouble; Alpha: Double; N: Integer);
var
  i: Integer;
begin
  for i := 0 to N - 1 do
    Dst[i] := Dst[i] + Alpha * Src[i];
end;
{$ENDIF}

function RowDot(A, B: PDouble; N: Integer): Double;
var
  i: Integer;
begin
  Result := 0.0;
  for i := 0 to N - 1 do
    Result := Result + A[i] * B[i];
end;

function MatrixKernelsAreAsm: Boolean;
begin
  {$IFDEF FEM_ASM}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// General dense helpers
// ---------------------------------------------------------------------------
function NewMatrix(Rows, Cols: Integer): TDenseMatrix;
var
  i: Integer;
begin
  SetLength(Result, Rows + 1, Cols + 1);
  for i := 0 to Rows do
    FillChar(Result[i][0], (Cols + 1) * SizeOf(Double), 0);
end;

function MatRows(const A: TDenseMatrix): Integer;
begin
  Result := Length(A) - 1;
end;

function MatCols(const A: TDenseMatrix): Integer;
begin
  if Length(A) = 0 then Result := 0 else Result := Length(A[0]) - 1;
end;

function MatTranspose(const A: TDenseMatrix): TDenseMatrix;
var
  i, j, nr, nc: Integer;
begin
  nr := MatRows(A); nc := MatCols(A);
  Result := NewMatrix(nc, nr);
  for i := 1 to nr do
    for j := 1 to nc do
      Result[j][i] := A[i][j];
end;

function MatMul(const A, B: TDenseMatrix): TDenseMatrix;
var
  i, k, nr, nk, nc: Integer;
  aik: Double;
begin
  nr := MatRows(A); nk := MatCols(A); nc := MatCols(B);
  if MatRows(B) <> nk then
    raise Exception.Create('MatMul: inner dimensions do not match');
  Result := NewMatrix(nr, nc);
  // C[i,:] += A[i,k] * B[k,:]  -- contiguous row AXPYs
  for i := 1 to nr do
    for k := 1 to nk do
    begin
      aik := A[i][k];
      if aik <> 0.0 then
        RowAxpy(@Result[i][1], @B[k][1], aik, nc);
    end;
end;

function MatMulAtB(const A, B: TDenseMatrix): TDenseMatrix;
var
  i, k, nk, na, nc: Integer;
  aki: Double;
begin
  nk := MatRows(A); na := MatCols(A); nc := MatCols(B);
  if MatRows(B) <> nk then
    raise Exception.Create('MatMulAtB: row counts do not match');
  Result := NewMatrix(na, nc);
  // C[i,:] += A[k,i] * B[k,:]
  for k := 1 to nk do
    for i := 1 to na do
    begin
      aki := A[k][i];
      if aki <> 0.0 then
        RowAxpy(@Result[i][1], @B[k][1], aki, nc);
    end;
end;

function MatVec(const A: TDenseMatrix; const x: TDoubleArray): TDoubleArray;
var
  i, nr, nc: Integer;
begin
  nr := MatRows(A); nc := MatCols(A);
  if Length(x) < nc + 1 then
    raise Exception.Create('MatVec: vector shorter than matrix column count');
  SetLength(Result, nr + 1);
  Result[0] := 0.0;
  for i := 1 to nr do
    Result[i] := RowDot(@A[i][1], @x[1], nc);
end;

function MatInverse(const A: TDenseMatrix; out Inv: TDenseMatrix;
  Tol: Double): Boolean;
var
  n, i, j, k, p: Integer;
  W: TDenseMatrix; // working copy, reduced to I
  big, f, pv: Double;
  row: array of Double;
begin
  n := MatRows(A);
  if MatCols(A) <> n then
    raise Exception.Create('MatInverse: matrix is not square');
  Result := False;
  W := NewMatrix(n, n);
  Inv := NewMatrix(n, n);
  big := 0.0;
  for i := 1 to n do
  begin
    for j := 1 to n do
    begin
      W[i][j] := A[i][j];
      if Abs(A[i][j]) > big then big := Abs(A[i][j]);
    end;
    Inv[i][i] := 1.0;
  end;
  if big = 0.0 then Exit;

  SetLength(row, n + 1);
  for k := 1 to n do
  begin
    // partial pivot: largest magnitude in column k at or below row k
    p := k;
    for i := k + 1 to n do
      if Abs(W[i][k]) > Abs(W[p][k]) then p := i;
    if Abs(W[p][k]) <= Tol * big then Exit;
    if p <> k then
    begin
      Move(W[p][1], row[1], n * SizeOf(Double));
      Move(W[k][1], W[p][1], n * SizeOf(Double));
      Move(row[1], W[k][1], n * SizeOf(Double));
      Move(Inv[p][1], row[1], n * SizeOf(Double));
      Move(Inv[k][1], Inv[p][1], n * SizeOf(Double));
      Move(row[1], Inv[k][1], n * SizeOf(Double));
    end;
    pv := 1.0 / W[k][k];
    for j := 1 to n do
    begin
      W[k][j] := W[k][j] * pv;
      Inv[k][j] := Inv[k][j] * pv;
    end;
    for i := 1 to n do
      if i <> k then
      begin
        f := W[i][k];
        if f <> 0.0 then
        begin
          RowAxpy(@W[i][1], @W[k][1], -f, n);
          RowAxpy(@Inv[i][1], @Inv[k][1], -f, n);
        end;
      end;
  end;
  Result := True;
end;

end.
