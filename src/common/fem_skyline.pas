unit fem_skyline;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils, Math;

type
  { TSkylineMatrix
    Symmetric skyline-storage matrix with LDL^T (no pivoting) factorization,
    intended for SPD or well-conditioned symmetric FEM stiffness systems.

    All indices are 1-based equation numbers (1..Neq); index 0 is unused
    but present so callers can use natural 1-based loops without off-by-one
    juggling.

    Storage layout (classic "active column" skyline):
      FMaxa[j]   = address in FAA of the diagonal entry of column j
      FMaxa[j+1] - FMaxa[j] - 1 = number of stored off-diagonal entries
                                   above the diagonal in column j
      entry (row=i, col=j), i<=j, lives at FAA[FMaxa[j] + (j - i)]

    After Factorize, FAA holds the LDL^T factors in place:
      FAA[FMaxa[i]]            = D(i)
      FAA[FMaxa[j] + (j - i)]  = L(j,i) * D(i)   for i < j (i.e. c(i))
  }
  TSkylineMatrix = class
  private
    FNeq: Integer;
    FMaxa: TIntArray;
    FAA: TDoubleArray;
    FNWK: Integer;
    FFactorized: Boolean;
    FMaxOrigDiag: Double; // largest |diagonal| at assembly time, used to scale the pivot check
    function ColFirstRow(ACol: Integer): Integer; inline;
  public
    constructor Create(ANeq: Integer; const Height: TIntArray);
    procedure AddToK(ARow, ACol: Integer; AValue: Double);
    function GetEntry(ARow, ACol: Integer): Double; // debug helper: 0 if outside stored skyline
    procedure Factorize;
    function Solve(const RHS: TDoubleArray): TDoubleArray;
    property Neq: Integer read FNeq;
    property NWK: Integer read FNWK;
  end;

// Computes the skyline column heights (1..Neq) from the list of equation
// numbers touched by each element. Equation numbers <= 0 are treated as
// "not in the system" (constrained dofs) and ignored, so the profile only
// reflects free-free coupling.
function ComputeSkylineHeight(ANeq: Integer; const ElementEqs: array of TIntArray): TIntArray;

implementation

function ComputeSkylineHeight(ANeq: Integer; const ElementEqs: array of TIntArray): TIntArray;
var
  i, j, minEq, eq: Integer;
begin
  SetLength(Result, ANeq + 1);
  for i := 1 to ANeq do Result[i] := 0;
  for i := 0 to High(ElementEqs) do
  begin
    if Length(ElementEqs[i]) = 0 then Continue;
    minEq := 0;
    for j := 0 to High(ElementEqs[i]) do
    begin
      eq := ElementEqs[i][j];
      if eq <= 0 then Continue;
      if (minEq = 0) or (eq < minEq) then minEq := eq;
    end;
    if minEq = 0 then Continue; // element touches no free dofs
    for j := 0 to High(ElementEqs[i]) do
    begin
      eq := ElementEqs[i][j];
      if eq <= 0 then Continue;
      if (eq - minEq) > Result[eq] then Result[eq] := eq - minEq;
    end;
  end;
end;

constructor TSkylineMatrix.Create(ANeq: Integer; const Height: TIntArray);
var
  j: Integer;
begin
  inherited Create;
  FNeq := ANeq;
  FFactorized := False;
  SetLength(FMaxa, FNeq + 2);
  FMaxa[1] := 1;
  for j := 1 to FNeq do
    FMaxa[j + 1] := FMaxa[j] + Height[j] + 1;
  FNWK := FMaxa[FNeq + 1] - 1;
  SetLength(FAA, FNWK + 1);
  for j := 1 to FNWK do FAA[j] := 0.0;
end;

function TSkylineMatrix.ColFirstRow(ACol: Integer): Integer;
begin
  Result := ACol - (FMaxa[ACol + 1] - FMaxa[ACol] - 1);
end;

procedure TSkylineMatrix.AddToK(ARow, ACol: Integer; AValue: Double);
var
  r, c, addr: Integer;
begin
  if (ARow <= 0) or (ACol <= 0) then Exit; // one or both dofs constrained: not in the free system
  if ARow <= ACol then begin r := ARow; c := ACol; end
  else begin r := ACol; c := ARow; end;
  if c - r > c - ColFirstRow(c) then
    raise Exception.CreateFmt(
      'Skyline profile too narrow for entry (%d,%d) in column %d -- profile was computed incorrectly',
      [ARow, ACol, c]);
  addr := FMaxa[c] + (c - r);
  FAA[addr] := FAA[addr] + AValue;
end;

function TSkylineMatrix.GetEntry(ARow, ACol: Integer): Double;
var
  r, c: Integer;
begin
  if ARow <= ACol then begin r := ARow; c := ACol; end
  else begin r := ACol; c := ARow; end;
  if r < ColFirstRow(c) then
    Result := 0.0
  else
    Result := FAA[FMaxa[c] + (c - r)];
end;

procedure TSkylineMatrix.Factorize;
var
  j, i, k, first_i, first_j, kl: Integer;
  c, dk, relTol: Double;
  addr_ij: Integer;
begin
  // Scale the singular-pivot check to the problem's own stiffness magnitude
  // (e.g. EA/L ~ 1e8) rather than an absolute constant, which would silently
  // accept a genuinely singular (mechanism) system as "solved".
  FMaxOrigDiag := 0.0;
  for j := 1 to FNeq do
    if Abs(FAA[FMaxa[j]]) > FMaxOrigDiag then
      FMaxOrigDiag := Abs(FAA[FMaxa[j]]);
  if FMaxOrigDiag = 0.0 then
    FMaxOrigDiag := 1.0;
  relTol := 1e-10 * FMaxOrigDiag;

  if (FNeq >= 1) and (Abs(FAA[FMaxa[1]]) < relTol) then
    raise Exception.CreateFmt(
      'Singular or near-singular system: zero pivot at equation %d ' +
      '(check for unconstrained rigid-body motion or a disconnected part of the model)', [1]);

  for j := 2 to FNeq do
  begin
    first_j := ColFirstRow(j);
    if first_j > j - 1 then Continue; // no off-diagonal entries stored above this diagonal

    for i := first_j to j - 1 do
    begin
      first_i := ColFirstRow(i);
      kl := first_i;
      if first_j > kl then kl := first_j;
      addr_ij := FMaxa[j] + (j - i);
      c := FAA[addr_ij];
      for k := kl to i - 1 do
        c := c - (FAA[FMaxa[i] + (i - k)] / FAA[FMaxa[k]]) * FAA[FMaxa[j] + (j - k)];
      FAA[addr_ij] := c;
    end;

    dk := FAA[FMaxa[j]];
    for i := first_j to j - 1 do
      dk := dk - Sqr(FAA[FMaxa[j] + (j - i)]) / FAA[FMaxa[i]];

    if Abs(dk) < relTol then
      raise Exception.CreateFmt(
        'Singular or near-singular system: zero pivot at equation %d ' +
        '(check for unconstrained rigid-body motion or a disconnected part of the model)', [j]);
    FAA[FMaxa[j]] := dk;
  end;
  FFactorized := True;
end;

function TSkylineMatrix.Solve(const RHS: TDoubleArray): TDoubleArray;
var
  y, x: TDoubleArray;
  i, j, k, first_i, first_j: Integer;
begin
  if not FFactorized then
    raise Exception.Create('TSkylineMatrix.Solve called before Factorize');

  SetLength(y, FNeq + 1);
  for i := 1 to FNeq do y[i] := RHS[i];

  // Forward substitution: L y = b
  for i := 1 to FNeq do
  begin
    first_i := ColFirstRow(i);
    for k := first_i to i - 1 do
      y[i] := y[i] - (FAA[FMaxa[i] + (i - k)] / FAA[FMaxa[k]]) * y[k];
  end;

  // Diagonal solve: z = D^-1 y
  SetLength(x, FNeq + 1);
  for i := 1 to FNeq do
    x[i] := y[i] / FAA[FMaxa[i]];

  // Back substitution: L^T x = z, processed column-by-column from n down to 1
  for j := FNeq downto 2 do
  begin
    first_j := ColFirstRow(j);
    for i := first_j to j - 1 do
      x[i] := x[i] - (FAA[FMaxa[j] + (j - i)] / FAA[FMaxa[i]]) * x[j];
  end;

  Result := x;
end;

end.
