unit fem_eigen;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils, Math;

// Classic cyclic Jacobi eigenvalue algorithm for a real symmetric NxN
// matrix A (1-based). Returns all N eigenvalues, ascending, and the
// corresponding eigenvectors as columns of V (V[i][k] = component i of
// eigenvector k). A is not modified (a working copy is used internally).
// Raises Exception if it fails to converge within MaxSweeps -- for a
// genuinely symmetric input this essentially never happens in practice
// for the modest matrix sizes this suite targets, so a failure here is
// worth surfacing rather than silently returning a partial result.
procedure JacobiEigenSymmetric(const A: TDenseMatrix; N: Integer;
  out EigenValues: TDoubleArray; out V: TDenseMatrix;
  MaxSweeps: Integer = 100; Tol: Double = 1e-13);

implementation

procedure JacobiEigenSymmetric(const A: TDenseMatrix; N: Integer;
  out EigenValues: TDoubleArray; out V: TDenseMatrix;
  MaxSweeps: Integer = 100; Tol: Double = 1e-13);
var
  Aw: TDenseMatrix; // working copy, reduced toward diagonal in place
  p, q, i, k, sweep: Integer;
  offDiagSq, theta, t, c, s, tau, h, aOffNorm: Double;
  app, aqq, apq, aip, aiq, vip, viq: Double;
  idx: TIntArray;
  sortedVals: TDoubleArray;
  sortedV: TDenseMatrix;
begin
  Aw := NewDenseMatrix(N);
  for i := 1 to N do
    for k := 1 to N do
      Aw[i][k] := A[i][k];

  V := NewDenseMatrix(N);
  for i := 1 to N do
    V[i][i] := 1.0;

  // Scale the convergence tolerance to the matrix's own magnitude (same
  // reasoning as the skyline solver's pivot check: an absolute constant
  // would be meaningless against, e.g., stiffness entries ~1e8).
  aOffNorm := 0.0;
  for i := 1 to N do
    for k := 1 to N do
      if i <> k then
        aOffNorm := aOffNorm + Sqr(Aw[i][k]);
  aOffNorm := Sqrt(aOffNorm);
  if aOffNorm = 0.0 then aOffNorm := 1.0;

  for sweep := 1 to MaxSweeps do
  begin
    offDiagSq := 0.0;
    for i := 1 to N do
      for k := i + 1 to N do
        offDiagSq := offDiagSq + Sqr(Aw[i][k]);
    if Sqrt(offDiagSq) <= Tol * aOffNorm then
    begin
      // converged
      SetLength(EigenValues, N + 1);
      for i := 1 to N do
        EigenValues[i] := Aw[i][i];

      // sort ascending, permuting V's columns to match
      SetLength(idx, N + 1);
      for i := 1 to N do idx[i] := i;
      for i := 1 to N - 1 do
        for k := i + 1 to N do
          if EigenValues[idx[k]] < EigenValues[idx[i]] then
          begin
            p := idx[i]; idx[i] := idx[k]; idx[k] := p;
          end;
      begin
        SetLength(sortedVals, N + 1);
        sortedV := NewDenseMatrix(N);
        for i := 1 to N do
        begin
          sortedVals[i] := EigenValues[idx[i]];
          for k := 1 to N do
            sortedV[k][i] := V[k][idx[i]];
        end;
        EigenValues := sortedVals;
        V := sortedV;
      end;
      Exit;
    end;

    for p := 1 to N - 1 do
      for q := p + 1 to N do
      begin
        apq := Aw[p][q];
        if apq = 0.0 then Continue;

        app := Aw[p][p]; aqq := Aw[q][q];
        theta := (aqq - app) / (2.0 * apq);
        if theta >= 0 then
          t := 1.0 / (theta + Sqrt(1.0 + theta * theta))
        else
          t := -1.0 / (-theta + Sqrt(1.0 + theta * theta));
        c := 1.0 / Sqrt(1.0 + t * t);
        s := t * c;
        tau := s / (1.0 + c);

        Aw[p][p] := app - t * apq;
        Aw[q][q] := aqq + t * apq;
        Aw[p][q] := 0.0; Aw[q][p] := 0.0;

        for i := 1 to N do
          if (i <> p) and (i <> q) then
          begin
            aip := Aw[i][p]; aiq := Aw[i][q];
            h := aip - s * (aiq + tau * aip);
            Aw[i][p] := h; Aw[p][i] := h;
            h := aiq + s * (aip - tau * aiq);
            Aw[i][q] := h; Aw[q][i] := h;
          end;

        for i := 1 to N do
        begin
          vip := V[i][p]; viq := V[i][q];
          V[i][p] := vip - s * (viq + tau * vip);
          V[i][q] := viq + s * (vip - tau * viq);
        end;
      end;
  end;

  raise Exception.CreateFmt(
    'Jacobi eigenvalue solver did not converge within %d sweeps', [MaxSweeps]);
end;

end.
