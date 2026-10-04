program skyline_test;

// Pivot checks of the skyline LDL^T factorization (fem_skyline).
//
// linstatic is a symmetric-POSITIVE-DEFINITE direct solver: every pivot of a
// valid stiffness system is strictly positive. A zero pivot means a mechanism
// (rigid-body motion / disconnected part); a NEGATIVE pivot means the matrix is
// indefinite, which no physically valid linear-elastic model produces -- if one
// ever turns up it must be rejected, not "solved" into plausible-looking but
// meaningless displacements. These cases pin that down, including a column
// with no off-diagonal entries (which the elimination loop skips) and the very
// first pivot (which has its own check).
// Exit code 0 = all passed.

{$mode objfpc}{$H+}

uses
  SysUtils, fem_types, fem_skyline;

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

function Eqs(const A: array of Integer): TIntArray;
var i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A));
  for i := 0 to High(A) do Result[i] := A[i];
end;

// Build a skyline matrix of order N from a list of "elements" (the equations each
// couples) and a list of (row, col, value) entries, then try to factorize.
// Returns '' on success, else the exception message.
function TryFactor(N: Integer; const Elems: array of TIntArray;
  const Entries: array of Double; out Sol: TDoubleArray; const Rhs: array of Double): string;
var
  H: TIntArray;
  K: TSkylineMatrix;
  i: Integer;
  b: TDoubleArray;
begin
  H := ComputeSkylineHeight(N, Elems);
  K := TSkylineMatrix.Create(N, H);
  try
    i := 0;
    while i < Length(Entries) do
    begin
      K.AddToK(Round(Entries[i]), Round(Entries[i + 1]), Entries[i + 2]);
      Inc(i, 3);
    end;
    Result := '';
    try
      K.Factorize;
      SetLength(b, N + 1);
      b[0] := 0.0;
      for i := 1 to N do b[i] := Rhs[i - 1];
      Sol := K.Solve(b);
    except
      on E: Exception do Result := E.Message;
    end;
  finally
    K.Free;
  end;
end;

var
  msg: string;
  sol: TDoubleArray;
begin
  Fails := 0; Checks := 0;

  // A. a well-conditioned SPD tridiagonal system solves correctly
  //    [ 2 -1  0 ] [x1]   [1]        solution x = (1.5, 2, 1.5)
  //    [-1  2 -1 ] [x2] = [0] ... use b = (1, 2, 1)? -> verify by residual below
  msg := TryFactor(3, [Eqs([1, 2]), Eqs([2, 3])],
    [1,1,2, 2,2,4, 3,3,2, 1,2,-1, 2,3,-1], sol, [1, 2, 1]);
  Check('SPD tridiagonal factorizes', msg = '', msg);
  if msg = '' then
  begin
    // 2x1 - x2 = 1 ; -x1 + 4x2 - x3 = 2 ; -x2 + 2x3 = 1  -> x = (0.642857.., 0.285714.., 0.642857..)? check residuals
    Check('SPD tridiagonal residual row 1', Abs(2 * sol[1] - sol[2] - 1) < 1E-12, FloatToStr(2 * sol[1] - sol[2] - 1));
    Check('SPD tridiagonal residual row 2', Abs(-sol[1] + 4 * sol[2] - sol[3] - 2) < 1E-12);
    Check('SPD tridiagonal residual row 3', Abs(-sol[2] + 2 * sol[3] - 1) < 1E-12);
  end;

  // B. indefinite 2x2 [[1,2],[2,1]] (eigenvalues 3 and -1): pivots 1, then 1-4 = -3
  msg := TryFactor(2, [Eqs([1, 2])], [1,1,1, 2,2,1, 1,2,2], sol, [1, 1]);
  Check('indefinite matrix (negative second pivot) is rejected', msg <> '', 'accepted -> solved an indefinite system');
  Check('...with a message saying it is not positive definite',
    (msg = '') or (Pos('positive definite', msg) > 0), msg);

  // C. negative FIRST pivot: diag(-1, 2)
  msg := TryFactor(2, [Eqs([1]), Eqs([2])], [1,1,-1, 2,2,2], sol, [1, 1]);
  Check('negative first pivot is rejected', msg <> '', 'accepted');

  // D. an equation coupled to nothing, with a zero diagonal: diag(1, 0)
  msg := TryFactor(2, [Eqs([1]), Eqs([2])], [1,1,1], sol, [1, 1]);
  Check('isolated zero-stiffness equation is rejected', msg <> '', 'accepted');

  // E. an isolated NEGATIVE diagonal after a good one: diag(1, -3)
  msg := TryFactor(2, [Eqs([1]), Eqs([2])], [1,1,1, 2,2,-3], sol, [1, 1]);
  Check('isolated negative diagonal is rejected', msg <> '', 'accepted');

  // F. a genuinely singular coupled system (the classic mechanism): [[1,1],[1,1]]
  msg := TryFactor(2, [Eqs([1, 2])], [1,1,1, 2,2,1, 1,2,1], sol, [1, 1]);
  Check('singular coupled system is still rejected', msg <> '', 'accepted');

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
