program matrix_test;

// Standalone verification for fem_matrix. Every routine is checked against
// a deliberately naive reference written inline here (plain triple loops,
// textbook formulas), on random data, so the shared unit cannot quietly
// disagree with the maths it replaced:
//
//   1. Vectors:      VCross/VDot/VNormalize identities (orthogonality,
//                    Lagrange identity, unit length).
//   2. Frames:       QuadFrame is right-handed orthonormal; degenerate
//                    input raises the caller-supplied messages.
//   3. Inverses:     Inv2x2 / Inv3x3 / MatInverse give A*inv(A) = I;
//                    singular input is reported, not divided by.
//   4. Dense ops:    MatMul / MatMulAtB / MatTranspose / MatVec vs naive.
//   5. TransformBlockDiag vs the explicit dense T^T*K*T it replaces, for
//                    M=3 (beam/shell) and M=2 (membrane), bit-for-bit.
//   6. AccumBtDB:    vs the explicit B^T*D*B triple loop.
//   7. RowAxpy:      every length 0..67 at several misalignments; must be
//                    bit-identical to the plain Pascal loop (this is the
//                    check to run after enabling -dFEM_USE_ASM, especially
//                    on Windows).
//
// Exit code 0 = all passed.

{$mode objfpc}{$H+}

uses
  SysUtils, fem_types, fem_matrix;

var
  Fails, Checks: Integer;

procedure Check(const Name: string; Ok: Boolean; const Detail: string = '');
begin
  Inc(Checks);
  if Ok then
    WriteLn('PASS  ', Name)
  else
  begin
    Inc(Fails);
    WriteLn('FAIL  ', Name, '  ', Detail);
  end;
end;

function Rnd(lo, hi: Double): Double;
begin
  Result := lo + (hi - lo) * Random;
end;

function MaxAbsDiff(const A, B: TDenseMatrix): Double;
var i, j: Integer;
begin
  Result := 0;
  if (Length(A) <> Length(B)) or (Length(A[0]) <> Length(B[0])) then
  begin
    Result := 1E300; Exit;
  end;
  for i := 1 to Length(A) - 1 do
    for j := 1 to Length(A[0]) - 1 do
      if Abs(A[i][j] - B[i][j]) > Result then Result := Abs(A[i][j] - B[i][j]);
end;

function RandMat(R, C: Integer): TDenseMatrix;
var i, j: Integer;
begin
  Result := NewMatrix(R, C);
  for i := 1 to R do for j := 1 to C do Result[i][j] := Rnd(-1, 1);
end;

function RandFrame: TFrame3;
begin
  Result := QuadFrame(Vec3(0, 0, 0),
    Vec3(Rnd(0.5, 2), Rnd(-1, 1), Rnd(-1, 1)),
    Vec3(Rnd(-1, 1), Rnd(0.5, 2), Rnd(-1, 1)), 'e', 'd');
end;

procedure TestVectors;
var a, b, c: TVec3; i: Integer; ok1, ok2, ok3: Boolean; lhs, rhs: Double;
begin
  ok1 := True; ok2 := True; ok3 := True;
  for i := 1 to 200 do
  begin
    a := Vec3(Rnd(-3, 3), Rnd(-3, 3), Rnd(-3, 3));
    b := Vec3(Rnd(-3, 3), Rnd(-3, 3), Rnd(-3, 3));
    c := VCross(a, b);
    if (Abs(VDot(c, a)) > 1E-12) or (Abs(VDot(c, b)) > 1E-12) then ok1 := False;
    lhs := VDot(c, c);                                   // |axb|^2
    rhs := VDot(a, a) * VDot(b, b) - Sqr(VDot(a, b));    // Lagrange identity
    if Abs(lhs - rhs) > 1E-10 * (1 + Abs(rhs)) then ok2 := False;
    if Abs(VNorm(VNormalize(a)) - 1.0) > 1E-14 then ok3 := False;
  end;
  Check('VCross is orthogonal to both inputs', ok1);
  Check('VCross satisfies the Lagrange identity', ok2);
  Check('VNormalize returns unit vectors', ok3);
  try
    VNormalize(Vec3(0, 0, 0));
    Check('VNormalize rejects the zero vector', False);
  except
    on Exception do Check('VNormalize rejects the zero vector', True);
  end;
end;

procedure TestFrames;
var F: TFrame3; i: Integer; ok: Boolean; raised1, raised2: string;
begin
  ok := True;
  for i := 1 to 200 do
  begin
    F := RandFrame;
    if (Abs(VNorm(F.ex) - 1) > 1E-13) or (Abs(VNorm(F.ey) - 1) > 1E-13) or
       (Abs(VNorm(F.ez) - 1) > 1E-13) or (Abs(VDot(F.ex, F.ey)) > 1E-13) or
       (Abs(VDot(F.ex, F.ez)) > 1E-13) or (Abs(VDot(F.ey, F.ez)) > 1E-13) or
       (VDot(VCross(F.ex, F.ey), F.ez) < 0.999999) then ok := False;
  end;
  Check('QuadFrame is right-handed orthonormal', ok);

  raised1 := '';
  try QuadFrame(Vec3(1, 1, 1), Vec3(1, 1, 1), Vec3(2, 3, 4), 'ZERO-EDGE', 'DEGENERATE');
  except on E: Exception do raised1 := E.Message; end;
  Check('QuadFrame reports a zero-length 1-2 edge with the caller''s message', raised1 = 'ZERO-EDGE', raised1);
  raised2 := '';
  try QuadFrame(Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 0, 0), 'ZERO-EDGE', 'DEGENERATE');
  except on E: Exception do raised2 := E.Message; end;
  Check('QuadFrame reports collinear corners with the caller''s message', raised2 = 'DEGENERATE', raised2);
end;

procedure TestInverses;
var
  a: array[0..8] of Double; inv: array[0..8] of Double;
  i, j, k, it: Integer; det, s, err: Double;
  i11, i12, i21, i22, d2: Double;
  A5, I5, P: TDenseMatrix; okInv: Boolean; Sing: TDenseMatrix;
begin
  err := 0;
  // 2x2: exact identity check on a known matrix
  d2 := Inv2x2(4, 7, 2, 6, i11, i12, i21, i22);
  Check('Inv2x2 determinant and entries (4 7; 2 6)',
    (Abs(d2 - 10) < 1E-14) and (Abs(i11 - 0.6) < 1E-14) and (Abs(i12 + 0.7) < 1E-14) and
    (Abs(i21 + 0.2) < 1E-14) and (Abs(i22 - 0.4) < 1E-14));
  d2 := Inv2x2(1, 2, 2, 4, i11, i12, i21, i22);
  Check('Inv2x2 flags a singular matrix (det = 0, zero output)',
    (d2 = 0) and (i11 = 0) and (i22 = 0));

  for it := 1 to 200 do
  begin
    for i := 0 to 8 do a[i] := Rnd(-1, 1);
    det := Inv3x3(a, inv);
    if Abs(det) < 1E-3 then Continue;
    for i := 0 to 2 do
      for j := 0 to 2 do
      begin
        s := 0;
        for k := 0 to 2 do s := s + a[3 * i + k] * inv[3 * k + j];
        if i = j then s := s - 1;
        if Abs(s) > err then err := Abs(s);
      end;
  end;
  Check('Inv3x3: A * inv(A) = I (200 random matrices)', err < 1E-10, FloatToStr(err));
  for i := 0 to 8 do a[i] := 0;
  a[0] := 1; a[1] := 2; a[3] := 2; a[4] := 4; a[8] := 1;
  Check('Inv3x3 flags a singular matrix', Inv3x3(a, inv) = 0);

  err := 0;
  for it := 1 to 50 do
  begin
    A5 := RandMat(7, 7);
    for i := 1 to 7 do A5[i][i] := A5[i][i] + 3.0; // keep it well-conditioned
    okInv := MatInverse(A5, I5);
    P := MatMul(A5, I5);
    for i := 1 to 7 do P[i][i] := P[i][i] - 1.0;
    for i := 1 to 7 do for j := 1 to 7 do if Abs(P[i][j]) > err then err := Abs(P[i][j]);
    if not okInv then err := 1;
  end;
  Check('MatInverse: A * inv(A) = I (7x7, 50 random)', err < 1E-12, FloatToStr(err));
  Sing := NewMatrix(3, 3);
  Sing[1][1] := 1; Sing[1][2] := 2; Sing[1][3] := 3;
  Sing[2][1] := 2; Sing[2][2] := 4; Sing[2][3] := 6;
  Sing[3][1] := 1; Sing[3][2] := 0; Sing[3][3] := 1;
  Check('MatInverse reports a singular matrix', not MatInverse(Sing, I5));
end;

procedure TestDenseOps;
var
  A, B, C, Ref, T: TDenseMatrix; i, j, k: Integer; s: Double;
  x, y: TDoubleArray; e: Double;
begin
  A := RandMat(9, 6); B := RandMat(6, 11);
  Ref := NewMatrix(9, 11);
  for i := 1 to 9 do for j := 1 to 11 do
  begin
    s := 0; for k := 1 to 6 do s := s + A[i][k] * B[k][j]; Ref[i][j] := s;
  end;
  C := MatMul(A, B);
  Check('MatMul (9x6 * 6x11) vs naive', MaxAbsDiff(C, Ref) < 1E-13, FloatToStr(MaxAbsDiff(C, Ref)));

  T := MatTranspose(A);
  Check('MatTranspose dimensions and entries',
    (MatRows(T) = 6) and (MatCols(T) = 9) and (T[2][5] = A[5][2]) and (T[6][9] = A[9][6]));

  B := RandMat(9, 4);
  Ref := NewMatrix(6, 4);
  for i := 1 to 6 do for j := 1 to 4 do
  begin
    s := 0; for k := 1 to 9 do s := s + A[k][i] * B[k][j]; Ref[i][j] := s;
  end;
  C := MatMulAtB(A, B);
  Check('MatMulAtB (A^T * B) vs naive', MaxAbsDiff(C, Ref) < 1E-13, FloatToStr(MaxAbsDiff(C, Ref)));
  Check('MatMulAtB equals MatMul(MatTranspose(A), B)', MaxAbsDiff(C, MatMul(MatTranspose(A), B)) < 1E-13);

  SetLength(x, 7); x[0] := 0;
  for i := 1 to 6 do x[i] := Rnd(-1, 1);
  y := MatVec(A, x);
  e := 0;
  for i := 1 to 9 do
  begin
    s := 0; for k := 1 to 6 do s := s + A[i][k] * x[k];
    if Abs(y[i] - s) > e then e := Abs(y[i] - s);
  end;
  Check('MatVec vs naive', e < 1E-13, FloatToStr(e));
end;

// Explicit dense T^T * K * T with T built the long way (the code this unit replaced).
function NaiveTransform(const Kl: TDenseMatrix; const F: TFrame3; M, NB: Integer): TDenseMatrix;
var
  T, KT: TDenseMatrix; Lam: array[0..2, 0..2] of Double;
  n, N3, i, j, k, b, r, c: Integer; s: Double;
begin
  for c := 0 to 2 do
  begin
    Lam[0][c] := F.ex[c]; Lam[1][c] := F.ey[c]; Lam[2][c] := F.ez[c];
  end;
  n := M * NB; N3 := 3 * NB;
  T := NewMatrix(n, N3);
  for b := 0 to NB - 1 do
    for r := 0 to M - 1 do
      for c := 0 to 2 do
        T[b * M + r + 1][b * 3 + c + 1] := Lam[r][c];
  KT := NewMatrix(n, N3);
  for i := 1 to n do for j := 1 to N3 do
  begin
    s := 0; for k := 1 to n do s := s + Kl[i][k] * T[k][j]; KT[i][j] := s;
  end;
  Result := NewMatrix(N3, N3);
  for i := 1 to N3 do for j := 1 to N3 do
  begin
    s := 0; for k := 1 to n do s := s + T[k][i] * KT[k][j]; Result[i][j] := s;
  end;
end;

procedure TestTransform;
var Kl: TDenseMatrix; F: TFrame3; d, worst: Double; it: Integer;
  cfgM, cfgNB: array[0..3] of Integer; q: Integer;
begin
  cfgM[0] := 3; cfgNB[0] := 4;    // beam: 2 nodes x (trans + rot)
  cfgM[1] := 3; cfgNB[1] := 8;    // shellq4
  cfgM[2] := 3; cfgNB[2] := 16;   // shellq8
  cfgM[3] := 2; cfgNB[3] := 4;    // membrane (in-plane rows only)
  for q := 0 to 3 do
  begin
    worst := 0;
    for it := 1 to 20 do
    begin
      F := RandFrame;
      Kl := RandMat(cfgM[q] * cfgNB[q], cfgM[q] * cfgNB[q]);
      d := MaxAbsDiff(TransformBlockDiag(Kl, F, cfgM[q], cfgNB[q]),
                      NaiveTransform(Kl, F, cfgM[q], cfgNB[q]));
      if d > worst then worst := d;
    end;
    Check(Format('TransformBlockDiag M=%d blocks=%d vs explicit dense T^T*K*T', [cfgM[q], cfgNB[q]]),
      worst = 0.0, 'max abs diff ' + FloatToStr(worst));
  end;
end;

procedure TestAccumBtDB;
var
  B3: array[1..3, 1..8] of Double; D3: array[1..3, 1..3] of Double;
  B2: array[1..2, 1..24] of Double; D2: array[1..2, 1..2] of Double;
  K, Ref: TDenseMatrix; i, j, a, b: Integer; s, sc, d: Double;
begin
  for a := 1 to 3 do for i := 1 to 8 do B3[a, i] := Rnd(-1, 1);
  for a := 1 to 3 do for b := 1 to 3 do D3[a, b] := Rnd(-1, 1);
  K := RandMat(8, 8); Ref := NewMatrix(8, 8); sc := 0.37;
  for i := 1 to 8 do for j := 1 to 8 do
  begin
    s := 0;
    for a := 1 to 3 do for b := 1 to 3 do s := s + B3[a, i] * D3[a, b] * B3[b, j];
    Ref[i][j] := K[i][j] + sc * s;
  end;
  AccumBtDB(K, B3, D3, 3, 8, sc);
  d := MaxAbsDiff(K, Ref);
  Check('AccumBtDB 3x8 (membrane Q4) vs explicit B^T D B', d < 1E-13, FloatToStr(d));

  for a := 1 to 2 do for i := 1 to 24 do B2[a, i] := Rnd(-1, 1);
  D2[1, 1] := 2.5; D2[1, 2] := 0; D2[2, 1] := 0; D2[2, 2] := 2.5;
  K := NewMatrix(24, 24); Ref := NewMatrix(24, 24); sc := 1.9;
  for i := 1 to 24 do for j := 1 to 24 do
  begin
    s := 0;
    for a := 1 to 2 do for b := 1 to 2 do s := s + B2[a, i] * D2[a, b] * B2[b, j];
    Ref[i][j] := sc * s;
  end;
  AccumBtDB(K, B2, D2, 2, 24, sc);
  d := MaxAbsDiff(K, Ref);
  Check('AccumBtDB 2x24 (Q8 shear, diagonal D) vs explicit B^T D B', d < 1E-13, FloatToStr(d));
end;

procedure TestRowAxpy;
var
  buf1, buf2, src: array[0..127] of Double;
  n, off, i: Integer; alpha: Double; allOk: Boolean; bad: string;
begin
  allOk := True; bad := '';
  for n := 0 to 67 do
    for off := 0 to 3 do
    begin
      alpha := Rnd(-2, 2);
      for i := 0 to 127 do
      begin
        src[i] := Rnd(-1, 1);
        buf1[i] := Rnd(-1, 1);
        buf2[i] := buf1[i];
      end;
      RowAxpy(@buf1[off], @src[3 - off], alpha, n);
      for i := 0 to n - 1 do
        buf2[off + i] := buf2[off + i] + alpha * src[3 - off + i];
      // bitwise compare (including the guard region after the span)
      if CompareByte(buf1, buf2, SizeOf(buf1)) <> 0 then
      begin
        allOk := False;
        bad := Format('n=%d off=%d', [n, off]);
      end;
    end;
  Check('RowAxpy bit-identical to the Pascal loop (n=0..67, 4 misalignments)' +
        ' [asm active: ' + BoolToStr(MatrixKernelsAreAsm, True) + ']', allOk, bad);
end;

begin
  Randomize;
  RandSeed := 20260930;
  Fails := 0; Checks := 0;
  TestVectors;
  TestFrames;
  TestInverses;
  TestDenseOps;
  TestTransform;
  TestAccumBtDB;
  TestRowAxpy;
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
