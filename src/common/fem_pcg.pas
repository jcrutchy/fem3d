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

function PrecomputeElementData(const Model: TModel;
  NodeIdx, MatIdx, PropIdx: TIntIntMap; const DofMap: TDofMap): TElementDataArray;

// Diagonal (Jacobi) preconditioner data: 1/K_ii per free equation, built
// once from the same element data (cheap: O(elements), no threading
// needed, it's not the bottleneck).
function BuildInverseDiagonal(const ED: TElementDataArray; NEQ: Integer): TDoubleArray;

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

// y = Kff * x over the reduced (free-dof-only) system, computed directly
// from element contributions -- no global matrix is ever assembled, which
// is the whole memory-scaling point of this solver (see docs/linsparse.md).
function ParallelMatVec(const ED: TElementDataArray; const x: TDoubleArray;
  NEQ: Integer; const Pool: TWorkerPool): TDoubleArray;

const
  // NOT empirically validated as a net win -- see docs/linsparse.md. Testing
  // up to ~6000 elements / a few hundred PCG iterations in this environment
  // showed threading was consistently *slower* than single-threaded (fixed
  // per-iteration RTLEvent synchronization overhead exceeded the compute
  // time saved), even with the persistent-worker-pool fix that removed the
  // far worse per-iteration-thread-spawn cost. Set deliberately high so
  // threading stays off by default for anything in the range actually
  // tested; FEM_THREADS=1 always forces single-threaded regardless.
  ElementCountThreadThreshold = 50000;
  DefaultThreadCount = 4;

// Preconditioned Conjugate Gradient. Raises Exception if it fails to
// converge within MaxIter, or if the system isn't (numerically) positive
// definite -- same "surface it, don't hide it" stance as fem_skyline's
// singular-pivot check and fem_eigen's non-convergence check.
function PCGSolve(const ED: TElementDataArray; const b: TDoubleArray;
  NEQ: Integer; Tolerance: Double; NumThreads: Integer; out Iterations: Integer): TDoubleArray;

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
  NEQ: Integer; Tolerance: Double; NumThreads: Integer; out Iterations: Integer): TDoubleArray;
var
  invDiag: TDoubleArray;
  x, r, z, p, Ap: TDoubleArray;
  i, iter, maxIter: Integer;
  rz, rzNew, pAp, alpha, beta, bnorm: Double;
  Pool: TWorkerPool;
begin
  invDiag := BuildInverseDiagonal(ED, NEQ);

  SetLength(x, NEQ + 1);
  SetLength(r, NEQ + 1);
  SetLength(z, NEQ + 1);
  SetLength(p, NEQ + 1);
  for i := 1 to NEQ do
  begin
    x[i] := 0.0;
    r[i] := b[i];
    z[i] := r[i] * invDiag[i];
    p[i] := z[i];
  end;

  bnorm := VecNorm(b, NEQ);
  if bnorm = 0.0 then
  begin
    Iterations := 0;
    Result := x; // zero load -> zero displacement, no iteration needed
    Exit;
  end;

  rz := VecDot(r, z, NEQ);
  maxIter := Max(500, 10 * NEQ);

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
      for i := 1 to NEQ do
        z[i] := r[i] * invDiag[i];
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

end.
