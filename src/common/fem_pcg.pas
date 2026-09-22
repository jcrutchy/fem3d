unit fem_pcg;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, fem_dofmap, fem_elements, Classes, SysUtils, Math;

type
  // One element's precomputed local stiffness plus the (0-based) equation
  // number each of its local dofs maps to (0 = that dof is constrained,
  // i.e. not part of the reduced free-free system). Precomputed once per
  // freedom case and reused across every load case's solve and every PCG
  // iteration -- recomputing element stiffness per iteration would be
  // wasteful, and it doesn't change between load cases either.
  TElementData = record
    Klocal: TElemMatrix;
    EqIdx: TIntArray; // size = element's dof count, 0-based array, values are 1-based eq numbers or 0
  end;
  TElementDataArray = array of TElementData;

  // Sparse symmetric sparsity pattern in CSR-like row-major form, upper
  // triangular including the diagonal: row i's entries are the columns
  // j>=i where K(i,j) is nonzero, sorted ascending (so the diagonal is
  // always the first entry of its own row). Built once per freedom case
  // from element connectivity -- this is a TRUE sparse pattern (only
  // actual nonzeros), not a skyline envelope, which is what lets the
  // IC(0) preconditioner below capture more of the matrix's real
  // structure than plain Jacobi without needing anywhere near a dense
  // or profile-shaped amount of storage.
  TCSRPattern = record
    RowPtr: TIntArray; // size NEQ+2, 1-based; row i spans RowPtr[i]..RowPtr[i+1]-1
    ColIdx: TIntArray; // 1-based array (index 0 unused), sorted ascending within each row
  end;

  TMatVecWorker = class(TThread)
  private
    FED: TElementDataArray;
    FStart, FEnd, FNEQ: Integer;
    FX: TDoubleArray;
    FY: TDoubleArray;
    FWakeEvent, FDoneEvent: PRTLEvent;
    FStop: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AED: TElementDataArray; AStart, AEnd, ANEQ: Integer);
    destructor Destroy; override;
    procedure SignalWork(const AX: TDoubleArray); // main thread: hand over x, wake the worker
    procedure WaitForDone;                      // main thread: block until this iteration's y is ready
    procedure StopAndJoin;                       // main thread: signal exit and join the OS thread
    property Y: TDoubleArray read FY;
  end;
  TWorkerPool = array of TMatVecWorker;

  // Cache-line-padded flag: on x86-64 a cache line is 64 bytes, so each
  // worker's Go/Done flag gets its own line -- packing flags tightly
  // instead would make independent threads' polls/writes bounce the same
  // cache line between cores (false sharing) even though the flags are
  // logically unrelated.
  TAlignedFlag = record
    Value: LongInt;
    Padding: array[0..59] of Byte; // 4 + 60 = 64 bytes total
  end;

  // Spin-wait alternative to TMatVecWorker: same persistent-pool idea
  // (thread created once, dispatched every PCG iteration), but signaling
  // is a busy-spin on an Interlocked-guarded flag rather than an
  // RTLEvent, which goes through the kernel (a futex wake = a context
  // switch) on every dispatch. See docs/linsparse.md for the measured
  // comparison -- this exists to test, not assume, whether avoiding that
  // kernel round-trip is actually where our per-iteration overhead goes.
  // Selected via FEM_SYNC=spin (default remains the event-based pool).
  TSpinWorker = class(TThread)
  private
    FED: TElementDataArray;
    FStart, FEnd, FNEQ: Integer;
    FX: TDoubleArray;
    FY: TDoubleArray;
    FGoFlag, FDoneFlag: TAlignedFlag;
    FStop: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AED: TElementDataArray; AStart, AEnd, ANEQ: Integer);
    procedure SignalWork(const AX: TDoubleArray);
    procedure WaitForDone;
    procedure StopAndJoin;
    property Y: TDoubleArray read FY;
  end;
  TSpinWorkerPool = array of TSpinWorker;

function PrecomputeElementData(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const DofMap: TDofMap): TElementDataArray;

// Diagonal (Jacobi) preconditioner data: 1/K_ii per free equation. Kept
// only as a cheap building block IC(0) factorization checks against for
// its own diagnostics; PCGSolve itself now uses IC(0) below, not this.
function BuildInverseDiagonal(const ED: TElementDataArray; NEQ: Integer): TDoubleArray;

// Builds the sparsity pattern from element connectivity (see TCSRPattern).
function BuildCSRPattern(const ED: TElementDataArray; NEQ: Integer): TCSRPattern;

// Sums element stiffness contributions into a Values array matching Pat's
// layout (same order as Pat.ColIdx) -- a true sparse assembly of K,
// built once per freedom case purely to construct the preconditioner
// (the matvec itself stays element-by-element/matrix-free, see
// ParallelMatVec below -- this is the one place linsparse assembles
// anything resembling a global matrix, and it's sparse, not skyline).
function AssembleCSRValues(const ED: TElementDataArray; const Pat: TCSRPattern; NEQ: Integer): TDoubleArray;

// In-place incomplete Cholesky, zero fill-in (IC(0)): turns Values from
// holding K into holding U, upper triangular, where K = U^T*U up to the
// entries the original sparsity pattern doesn't have room for (that's
// the "incomplete" part -- any fill-in outside Pat's pattern is simply
// dropped rather than computed). Same derivation as fem_skyline's LDL^T,
// generalized from skyline's contiguous envelope to a true sparse
// pattern. Raises Exception on a non-positive pivot -- either the system
// genuinely isn't positive definite, or (rarer) the incompleteness
// itself caused a breakdown; either way, surfaced rather than hidden.
procedure ICFactorize(const Pat: TCSRPattern; var Values: TDoubleArray; NEQ: Integer);

// Solves (U^T*U)*z = rhs via sparse forward + back substitution against
// the IC(0) factor -- this is the M^-1*r step in PCG.
function ICForwardBackSolve(const Pat: TCSRPattern; const Values: TDoubleArray;
  const rhs: TDoubleArray; NEQ: Integer): TDoubleArray;

// Attempts IC(0) with a small diagonal shift if the unshifted factorization
// breaks down (see docs/linsparse.md -- dropping fill-in during an
// incomplete factorization can make an intermediate pivot go non-positive
// even when the full K is genuinely SPD). The shift is bounded to a small
// fraction of the matrix's own diagonal magnitude so this can fix a
// numerical breakdown without being able to mask a genuinely unstable
// model into producing a plausible-looking wrong answer.
function BuildIC0WithFallback(const Pat: TCSRPattern; const KValues: TDoubleArray;
  NEQ: Integer; out UsedShift: Double): TDoubleArray;

// A pool of persistent worker threads, one per PCG solve (created once,
// reused every iteration via a lightweight wake/done event pair -- see
// TMatVecWorker in the implementation section for why this replaced an
// earlier per-iteration-spawn version). Empty (Length=0) means "run
// single-threaded"; CreateWorkerPool returns that when there aren't
// enough elements to be worth threading (see ElementCountThreadThreshold)
// or NumThreads<=1. Always pair with FreeWorkerPool once done, even on
// an exception path (use try/finally).
function CreateWorkerPool(const ED: TElementDataArray; NEQ, NumThreads: Integer): TWorkerPool;
procedure FreeWorkerPool(var Pool: TWorkerPool);

// Spin-wait pool equivalents of the two functions above -- see TSpinWorker.
function CreateSpinWorkerPool(const ED: TElementDataArray; NEQ, NumThreads: Integer): TSpinWorkerPool;
procedure FreeSpinWorkerPool(var Pool: TSpinWorkerPool);
function ParallelMatVecSpin(const ED: TElementDataArray; const x: TDoubleArray;
  NEQ: Integer; const Pool: TSpinWorkerPool): TDoubleArray;

// y = Kff * x over the reduced (free-dof-only) system, computed directly
// from element contributions -- no global matrix is ever assembled, which
// is the whole memory-scaling point of this solver (see docs/linsparse.md).
function ParallelMatVec(const ED: TElementDataArray; const x: TDoubleArray;
  NEQ: Integer; const Pool: TWorkerPool): TDoubleArray;

const
  DefaultThreadCount = 4;
  DefaultElementCountThreadThreshold = 50000;

  // A typed constant, not a plain const: FPC allows these to be
  // reassigned at runtime by default, which is what lets linsparse.lpr's
  // FEM_THREAD_THRESHOLD override it for experimentation without
  // recompiling. Defaults deliberately high -- see docs/linsparse.md.
  // Testing up to ~6000 elements / a few hundred PCG iterations in this
  // environment showed event-based threading was consistently *slower*
  // than single-threaded (fixed per-iteration synchronization overhead
  // exceeded the compute time saved), even with the persistent-worker-
  // pool fix that removed the far worse per-iteration-thread-spawn cost.
  // FEM_THREADS=1 always forces single-threaded regardless of this value.
  ElementCountThreadThreshold: Integer = DefaultElementCountThreadThreshold;

// Preconditioned Conjugate Gradient. Raises Exception if it fails to
// converge within MaxIter, or if the system isn't (numerically) positive
// definite -- same "surface it, don't hide it" stance as fem_skyline's
// singular-pivot check and fem_eigen's non-convergence check. ICShiftUsed
// reports the diagonal shift BuildIC0WithFallback needed (0 if the
// unshifted IC(0) factorization worked outright) -- exposed so a caller
// can log it (see linsparse's FEM_DEBUG output) when diagnosing a model
// that needed the fallback.
function PCGSolve(const ED: TElementDataArray; const b: TDoubleArray;
  NEQ: Integer; Tolerance: Double; NumThreads: Integer;
  out Iterations: Integer; out ICShiftUsed: Double; UseSpinSync: Boolean = False): TDoubleArray;

implementation

function PrecomputeElementData(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const DofMap: TDofMap): TElementDataArray;
var
  ei, k, N: Integer;
  el: TElement;
  gd: TIntArray;
begin
  SetLength(Result, Length(Model.Elements));
  for ei := 0 to High(Model.Elements) do
  begin
    el := Model.Elements[ei];
    Result[ei].Klocal := ElementStiffnessFor(Model, NodeIdx, MatIdx, PropIdx, el);
    gd := ElementGlobalDofs(DofMap, NodeIdx, el); // 1-based, index 0 unused
    N := High(gd);
    SetLength(Result[ei].EqIdx, N);
    for k := 1 to N do
      Result[ei].EqIdx[k - 1] := DofMap.GlobalToEq[gd[k]];
  end;
end;

function BuildInverseDiagonal(const ED: TElementDataArray; NEQ: Integer): TDoubleArray;
var
  ei, i, N, eqi: Integer;
begin
  SetLength(Result, NEQ + 1);
  for i := 1 to NEQ do Result[i] := 0.0;
  for ei := 0 to High(ED) do
  begin
    N := Length(ED[ei].EqIdx);
    for i := 0 to N - 1 do
    begin
      eqi := ED[ei].EqIdx[i];
      if eqi > 0 then
        Result[eqi] := Result[eqi] + ED[ei].Klocal[i + 1][i + 1];
    end;
  end;
  for i := 1 to NEQ do
    if Result[i] > 0 then
      Result[i] := 1.0 / Result[i]
    else
      raise Exception.CreateFmt(
        'Equation %d has a non-positive assembled diagonal -- system is not positive definite ' +
        '(check for a mechanism or disconnected part of the model)', [i]);
end;

function BuildCSRPattern(const ED: TElementDataArray; NEQ: Integer): TCSRPattern;
var
  RowCols: array of TIntArray; // temp per-row column lists, index 1..NEQ
  ei, a, b, i, j, k, m, L, tmp, nnz, pos, N: Integer;

  procedure AddColToRow(row, col: Integer);
  var
    mm, LL: Integer;
  begin
    LL := Length(RowCols[row]);
    for mm := 0 to LL - 1 do
      if RowCols[row][mm] = col then Exit; // already present
    SetLength(RowCols[row], LL + 1);
    RowCols[row][LL] := col;
  end;

begin
  SetLength(RowCols, NEQ + 1);
  for ei := 0 to High(ED) do
  begin
    N := Length(ED[ei].EqIdx);
    for a := 0 to N - 1 do
    begin
      i := ED[ei].EqIdx[a];
      if i = 0 then Continue;
      for b := 0 to N - 1 do
      begin
        j := ED[ei].EqIdx[b];
        if (j = 0) or (j < i) then Continue; // upper triangular only
        AddColToRow(i, j);
      end;
    end;
  end;

  // insertion sort each row's columns ascending -- rows are small (bounded
  // by element connectivity), so this is cheap despite being O(n^2) per row
  for i := 1 to NEQ do
  begin
    L := Length(RowCols[i]);
    for a := 1 to L - 1 do
    begin
      tmp := RowCols[i][a];
      b := a - 1;
      while (b >= 0) and (RowCols[i][b] > tmp) do
      begin
        RowCols[i][b + 1] := RowCols[i][b];
        Dec(b);
      end;
      RowCols[i][b + 1] := tmp;
    end;
  end;

  SetLength(Result.RowPtr, NEQ + 2);
  Result.RowPtr[1] := 1;
  for i := 1 to NEQ do
    Result.RowPtr[i + 1] := Result.RowPtr[i] + Length(RowCols[i]);
  nnz := Result.RowPtr[NEQ + 1] - 1;
  SetLength(Result.ColIdx, nnz + 1);
  pos := 1;
  for i := 1 to NEQ do
  begin
    L := Length(RowCols[i]);
    for k := 0 to L - 1 do
    begin
      Result.ColIdx[pos] := RowCols[i][k];
      Inc(pos);
    end;
  end;
end;

function FindInRow(const Pat: TCSRPattern; row, col: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := Pat.RowPtr[row]; hi := Pat.RowPtr[row + 1] - 1;
  Result := -1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if Pat.ColIdx[mid] = col then begin Result := mid; Exit; end
    else if Pat.ColIdx[mid] < col then lo := mid + 1
    else hi := mid - 1;
  end;
end;

function AssembleCSRValues(const ED: TElementDataArray; const Pat: TCSRPattern; NEQ: Integer): TDoubleArray;
var
  ei, a, b, i, j, N, addr: Integer;
begin
  SetLength(Result, Length(Pat.ColIdx));
  for ei := 0 to High(ED) do
  begin
    N := Length(ED[ei].EqIdx);
    for a := 0 to N - 1 do
    begin
      i := ED[ei].EqIdx[a];
      if i = 0 then Continue;
      for b := 0 to N - 1 do
      begin
        j := ED[ei].EqIdx[b];
        if (j = 0) or (j < i) then Continue;
        addr := FindInRow(Pat, i, j);
        if addr < 0 then
          raise Exception.Create('internal error: CSR pattern missing an entry present during assembly');
        Result[addr] := Result[addr] + ED[ei].Klocal[a + 1][b + 1];
      end;
    end;
  end;
end;

procedure ICFactorize(const Pat: TCSRPattern; var Values: TDoubleArray; NEQ: Integer);
var
  k, i, j, ii, jj, rowKStart, rowKEnd, idxK, addr: Integer;
  Ukk: Double;
begin
  for k := 1 to NEQ do
  begin
    idxK := Pat.RowPtr[k]; // diagonal is always the first entry of its row
    if Values[idxK] <= 0 then
      raise Exception.CreateFmt(
        'IC(0): non-positive pivot at equation %d during factorization -- system is not positive ' +
        'definite (or the incomplete factorization broke down; check for a mechanism)', [k]);
    Ukk := Sqrt(Values[idxK]);
    Values[idxK] := Ukk;

    rowKStart := Pat.RowPtr[k] + 1;
    rowKEnd := Pat.RowPtr[k + 1] - 1;
    for ii := rowKStart to rowKEnd do
      Values[ii] := Values[ii] / Ukk;

    // rank-1 update to pairs (i,j), k<i<=j, both columns of row k --
    // dropped silently if (i,j) isn't itself in the pattern (that's the
    // "incomplete": any fill-in outside the original sparsity is discarded)
    for ii := rowKStart to rowKEnd do
    begin
      i := Pat.ColIdx[ii];
      for jj := ii to rowKEnd do
      begin
        j := Pat.ColIdx[jj];
        addr := FindInRow(Pat, i, j);
        if addr >= 0 then
          Values[addr] := Values[addr] - Values[ii] * Values[jj];
      end;
    end;
  end;
end;

function ICForwardBackSolve(const Pat: TCSRPattern; const Values: TDoubleArray;
  const rhs: TDoubleArray; NEQ: Integer): TDoubleArray;
var
  y, z: TDoubleArray;
  k, idx, rowStart, rowEnd, col: Integer;
begin
  // forward: U^T y = rhs (U^T lower triangular; scatter contributions
  // forward as each y[k] is finalized, since row k's pattern is exactly
  // the set of later rows U(k,*) affects)
  SetLength(y, NEQ + 1);
  for k := 1 to NEQ do y[k] := rhs[k];
  for k := 1 to NEQ do
  begin
    y[k] := y[k] / Values[Pat.RowPtr[k]];
    rowStart := Pat.RowPtr[k] + 1;
    rowEnd := Pat.RowPtr[k + 1] - 1;
    for idx := rowStart to rowEnd do
    begin
      col := Pat.ColIdx[idx];
      y[col] := y[col] - Values[idx] * y[k];
    end;
  end;

  // backward: U z = y (U upper triangular; standard gather back-substitution,
  // row k's own pattern already lists exactly the needed later-z terms)
  SetLength(z, NEQ + 1);
  for k := NEQ downto 1 do
  begin
    rowStart := Pat.RowPtr[k] + 1;
    rowEnd := Pat.RowPtr[k + 1] - 1;
    z[k] := y[k];
    for idx := rowStart to rowEnd do
    begin
      col := Pat.ColIdx[idx];
      z[k] := z[k] - Values[idx] * z[col];
    end;
    z[k] := z[k] / Values[Pat.RowPtr[k]];
  end;
  Result := z;
end;

function BuildIC0WithFallback(const Pat: TCSRPattern; const KValues: TDoubleArray;
  NEQ: Integer; out UsedShift: Double): TDoubleArray;
const
  MaxAttempts = 10;
  MaxShiftFraction = 1e-2; // never shift by more than 1% of the average diagonal
var
  avgDiag, shift: Double;
  attempt, i: Integer;
begin
  avgDiag := 0.0;
  for i := 1 to NEQ do
    avgDiag := avgDiag + KValues[Pat.RowPtr[i]];
  avgDiag := avgDiag / NEQ;

  shift := 0.0;
  for attempt := 0 to MaxAttempts do
  begin
    SetLength(Result, Length(KValues));
    Move(KValues[0], Result[0], Length(KValues) * SizeOf(Double));
    if shift > 0 then
      for i := 1 to NEQ do
        Result[Pat.RowPtr[i]] := Result[Pat.RowPtr[i]] + shift;
    try
      ICFactorize(Pat, Result, NEQ);
      UsedShift := shift;
      Exit;
    except
      on E: Exception do
      begin
        if shift = 0.0 then
          shift := 1e-10 * avgDiag
        else
          shift := shift * 10.0;
        if shift > MaxShiftFraction * avgDiag then
          raise Exception.CreateFmt(
            'IC(0) factorization failed even after diagonal shifting up to %.1f%% of the average ' +
            'diagonal -- this model likely is not positive definite (check for a mechanism or ' +
            'disconnected part), or needs linstatic''s direct solve instead. Original error: %s',
            [MaxShiftFraction * 100, E.Message]);
      end;
    end;
  end;
end;

procedure MatVecRange(const ED: TElementDataArray; StartIdx, EndIdx: Integer;
  const x: TDoubleArray; var y: TDoubleArray; NEQ: Integer);
var
  ei, i, j, N, eqi, eqj: Integer;
  Klocal: TElemMatrix;
  sum: Double;
begin
  SetLength(y, NEQ + 1);
  for i := 1 to NEQ do y[i] := 0.0;
  for ei := StartIdx to EndIdx do
  begin
    Klocal := ED[ei].Klocal;
    N := Length(ED[ei].EqIdx);
    for i := 0 to N - 1 do
    begin
      eqi := ED[ei].EqIdx[i];
      if eqi = 0 then Continue; // this local dof is constrained -- no row in the reduced system
      sum := 0.0;
      for j := 0 to N - 1 do
      begin
        eqj := ED[ei].EqIdx[j];
        if eqj = 0 then Continue; // constrained dofs are implicitly zero in the reduced x
        sum := sum + Klocal[i + 1][j + 1] * x[eqj];
      end;
      y[eqi] := y[eqi] + sum;
    end;
  end;
end;

// Persistent worker: created once per PCG solve, assigned a fixed
// element range for its whole lifetime, and re-dispatched via a
// lightweight RTL event on every PCG iteration rather than being
// spawned fresh each time. Spawning/joining OS threads per iteration
// (hundreds to thousands of them over a solve) turned out to dominate
// runtime completely -- a first version of this unit did exactly that,
// and a ~240-element model that converges in 10ms single-threaded still
// hadn't finished after 30 seconds with 4 threads spawned per
// iteration. This is the fix: pay thread-creation cost once, not once
// per iteration.

constructor TMatVecWorker.Create(const AED: TElementDataArray; AStart, AEnd, ANEQ: Integer);
begin
  inherited Create(True);
  FED := AED; FStart := AStart; FEnd := AEnd; FNEQ := ANEQ;
  FWakeEvent := RTLEventCreate;
  FDoneEvent := RTLEventCreate;
  FStop := False;
  FreeOnTerminate := False;
  Start; // begins running immediately; Execute blocks on FWakeEvent right away, idle until dispatched
end;

destructor TMatVecWorker.Destroy;
begin
  RTLEventDestroy(FWakeEvent);
  RTLEventDestroy(FDoneEvent);
  inherited Destroy;
end;

procedure TMatVecWorker.Execute;
begin
  while True do
  begin
    RTLEventWaitFor(FWakeEvent);
    if FStop then Break;
    MatVecRange(FED, FStart, FEnd, FX, FY, FNEQ);
    RTLEventSetEvent(FDoneEvent);
  end;
end;

procedure TMatVecWorker.SignalWork(const AX: TDoubleArray);
begin
  FX := AX;
  RTLEventSetEvent(FWakeEvent);
end;

procedure TMatVecWorker.WaitForDone;
begin
  RTLEventWaitFor(FDoneEvent);
end;

procedure TMatVecWorker.StopAndJoin;
begin
  FStop := True;
  RTLEventSetEvent(FWakeEvent); // wake it so it notices FStop and exits Execute
  WaitFor;
end;

// A pool of persistent workers, one per PCG solve. Empty (Length=0) means
// "run single-threaded" -- ParallelMatVec below falls back to a direct
// MatVecRange call in that case, same as it would for a small model.
function CreateWorkerPool(const ED: TElementDataArray; NEQ, NumThreads: Integer): TWorkerPool;
var
  NumElems, chunk, t, startIdx, endIdx, made: Integer;
begin
  NumElems := Length(ED);
  if (NumElems < ElementCountThreadThreshold) or (NumThreads <= 1) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  SetLength(Result, NumThreads);
  chunk := (NumElems + NumThreads - 1) div NumThreads;
  made := 0;
  for t := 0 to NumThreads - 1 do
  begin
    startIdx := t * chunk;
    endIdx := Min(startIdx + chunk - 1, NumElems - 1);
    if startIdx > endIdx then Continue; // more threads than useful chunks for this element count
    Result[made] := TMatVecWorker.Create(ED, startIdx, endIdx, NEQ);
    Inc(made);
  end;
  SetLength(Result, made);
end;

procedure FreeWorkerPool(var Pool: TWorkerPool);
var
  t: Integer;
begin
  for t := 0 to High(Pool) do
  begin
    Pool[t].StopAndJoin;
    Pool[t].Free;
  end;
  SetLength(Pool, 0);
end;

function ParallelMatVec(const ED: TElementDataArray; const x: TDoubleArray;
  NEQ: Integer; const Pool: TWorkerPool): TDoubleArray;
var
  t, i: Integer;
begin
  if Length(Pool) = 0 then
  begin
    MatVecRange(ED, 0, High(ED), x, Result, NEQ);
    Exit;
  end;

  for t := 0 to High(Pool) do
    Pool[t].SignalWork(x);
  SetLength(Result, NEQ + 1);
  for i := 1 to NEQ do Result[i] := 0.0;
  for t := 0 to High(Pool) do
  begin
    Pool[t].WaitForDone;
    for i := 1 to NEQ do
      Result[i] := Result[i] + Pool[t].Y[i];
  end;
end;

constructor TSpinWorker.Create(const AED: TElementDataArray; AStart, AEnd, ANEQ: Integer);
begin
  inherited Create(True);
  FED := AED; FStart := AStart; FEnd := AEnd; FNEQ := ANEQ;
  FGoFlag.Value := 0;
  FDoneFlag.Value := 0;
  FStop := False;
  FreeOnTerminate := False;
  Start;
end;

procedure TSpinWorker.Execute;
begin
  while True do
  begin
    while InterlockedCompareExchange(FGoFlag.Value, 0, 1) <> 1 do ; // spin until Go=1, consume it
    if FStop then Break;
    MatVecRange(FED, FStart, FEnd, FX, FY, FNEQ);
    InterlockedExchange(FDoneFlag.Value, 1);
  end;
end;

procedure TSpinWorker.SignalWork(const AX: TDoubleArray);
begin
  FX := AX;
  InterlockedExchange(FDoneFlag.Value, 0);
  InterlockedExchange(FGoFlag.Value, 1);
end;

procedure TSpinWorker.WaitForDone;
begin
  while InterlockedCompareExchange(FDoneFlag.Value, 0, 1) <> 1 do ; // spin until Done=1, consume it
end;

procedure TSpinWorker.StopAndJoin;
begin
  FStop := True;
  InterlockedExchange(FGoFlag.Value, 1); // wake it so it notices FStop and exits Execute
  WaitFor;
end;

function CreateSpinWorkerPool(const ED: TElementDataArray; NEQ, NumThreads: Integer): TSpinWorkerPool;
var
  NumElems, chunk, t, startIdx, endIdx, made: Integer;
begin
  NumElems := Length(ED);
  if (NumElems < ElementCountThreadThreshold) or (NumThreads <= 1) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  SetLength(Result, NumThreads);
  chunk := (NumElems + NumThreads - 1) div NumThreads;
  made := 0;
  for t := 0 to NumThreads - 1 do
  begin
    startIdx := t * chunk;
    endIdx := Min(startIdx + chunk - 1, NumElems - 1);
    if startIdx > endIdx then Continue;
    Result[made] := TSpinWorker.Create(ED, startIdx, endIdx, NEQ);
    Inc(made);
  end;
  SetLength(Result, made);
end;

procedure FreeSpinWorkerPool(var Pool: TSpinWorkerPool);
var
  t: Integer;
begin
  for t := 0 to High(Pool) do
  begin
    Pool[t].StopAndJoin;
    Pool[t].Free;
  end;
  SetLength(Pool, 0);
end;

function ParallelMatVecSpin(const ED: TElementDataArray; const x: TDoubleArray;
  NEQ: Integer; const Pool: TSpinWorkerPool): TDoubleArray;
var
  t, i: Integer;
begin
  if Length(Pool) = 0 then
  begin
    MatVecRange(ED, 0, High(ED), x, Result, NEQ);
    Exit;
  end;

  for t := 0 to High(Pool) do
    Pool[t].SignalWork(x);
  SetLength(Result, NEQ + 1);
  for i := 1 to NEQ do Result[i] := 0.0;
  for t := 0 to High(Pool) do
  begin
    Pool[t].WaitForDone;
    for i := 1 to NEQ do
      Result[i] := Result[i] + Pool[t].Y[i];
  end;
end;

function VecDot(const a, b: TDoubleArray; N: Integer): Double;
var
  i: Integer;
begin
  Result := 0.0;
  for i := 1 to N do
    Result := Result + a[i] * b[i];
end;

function VecNorm(const a: TDoubleArray; N: Integer): Double;
begin
  Result := Sqrt(VecDot(a, a, N));
end;

function PCGSolve(const ED: TElementDataArray; const b: TDoubleArray;
  NEQ: Integer; Tolerance: Double; NumThreads: Integer;
  out Iterations: Integer; out ICShiftUsed: Double; UseSpinSync: Boolean): TDoubleArray;
var
  Pat: TCSRPattern;
  KValues, ICValues: TDoubleArray;
  x, r, z, p, Ap: TDoubleArray;
  i, iter, maxIter: Integer;
  rz, rzNew, pAp, alpha, beta, bnorm: Double;
  Pool: TWorkerPool;
  SpinPool: TSpinWorkerPool;
begin
  Pat := BuildCSRPattern(ED, NEQ);
  KValues := AssembleCSRValues(ED, Pat, NEQ);
  ICValues := BuildIC0WithFallback(Pat, KValues, NEQ, ICShiftUsed);

  SetLength(x, NEQ + 1);
  SetLength(r, NEQ + 1);
  SetLength(p, NEQ + 1);
  for i := 1 to NEQ do
  begin
    x[i] := 0.0;
    r[i] := b[i];
  end;
  z := ICForwardBackSolve(Pat, ICValues, r, NEQ);
  for i := 1 to NEQ do
    p[i] := z[i];

  bnorm := VecNorm(b, NEQ);
  if bnorm = 0.0 then
  begin
    Iterations := 0;
    Result := x; // zero load -> zero displacement, no iteration needed
    Exit;
  end;

  rz := VecDot(r, z, NEQ);
  maxIter := Max(500, 10 * NEQ);

  if UseSpinSync then
  begin
    SpinPool := CreateSpinWorkerPool(ED, NEQ, NumThreads);
    try
      for iter := 1 to maxIter do
      begin
        Ap := ParallelMatVecSpin(ED, p, NEQ, SpinPool);
        pAp := VecDot(p, Ap, NEQ);
        if pAp <= 0 then
          raise Exception.CreateFmt(
            'PCG: search direction is non-positive-definite at iteration %d -- system is not positive ' +
            'definite (check for a mechanism or disconnected part of the model)', [iter]);
        alpha := rz / pAp;
        for i := 1 to NEQ do
        begin
          x[i] := x[i] + alpha * p[i];
          r[i] := r[i] - alpha * Ap[i];
        end;
        if VecNorm(r, NEQ) <= Tolerance * bnorm then
        begin
          Iterations := iter;
          Result := x;
          Exit;
        end;
        z := ICForwardBackSolve(Pat, ICValues, r, NEQ);
        rzNew := VecDot(r, z, NEQ);
        beta := rzNew / rz;
        for i := 1 to NEQ do
          p[i] := z[i] + beta * p[i];
        rz := rzNew;
      end;
      raise Exception.CreateFmt('PCG did not converge within %d iterations (tolerance %.3e)', [maxIter, Tolerance]);
    finally
      FreeSpinWorkerPool(SpinPool);
    end;
  end
  else
  begin
    Pool := CreateWorkerPool(ED, NEQ, NumThreads);
    try
      for iter := 1 to maxIter do
      begin
        Ap := ParallelMatVec(ED, p, NEQ, Pool);
        pAp := VecDot(p, Ap, NEQ);
        if pAp <= 0 then
          raise Exception.CreateFmt(
            'PCG: search direction is non-positive-definite at iteration %d -- system is not positive ' +
            'definite (check for a mechanism or disconnected part of the model)', [iter]);
        alpha := rz / pAp;
        for i := 1 to NEQ do
        begin
          x[i] := x[i] + alpha * p[i];
          r[i] := r[i] - alpha * Ap[i];
        end;
        if VecNorm(r, NEQ) <= Tolerance * bnorm then
        begin
          Iterations := iter;
          Result := x;
          Exit;
        end;
        z := ICForwardBackSolve(Pat, ICValues, r, NEQ);
        rzNew := VecDot(r, z, NEQ);
        beta := rzNew / rz;
        for i := 1 to NEQ do
          p[i] := z[i] + beta * p[i];
        rz := rzNew;
      end;
      raise Exception.CreateFmt('PCG did not converge within %d iterations (tolerance %.3e)', [maxIter, Tolerance]);
    finally
      FreeWorkerPool(Pool);
    end;
  end;
end;

end.
