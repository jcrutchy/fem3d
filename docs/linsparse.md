# `linsparse` — matrix-free linear-static solver

A second linear-static solver, alongside `linstatic`. Same physics, same
model format, same load-case/freedom-case/combination handling, same
output convention — the difference is entirely in how `Kx=f` gets solved:
`linstatic` assembles a skyline matrix and factorizes it directly (exact,
one factorization reused across every load case); `linsparse` never
assembles a *global* matrix at all for the solve itself, and solves each
load case with a preconditioned conjugate gradient (PCG) iteration built
directly from element contributions.

```
linsparse model.fem
linsparse model.fem > results.txt
FEM_THREADS=8 linsparse model.fem
```

## Why element-by-element (matrix-free)

Every PCG iteration only needs one thing: `y = K·x`. That product can be
computed directly as a sum of small element contributions
(`y_local = K_element · x_local`, scattered into the global `y`) without
ever building or storing `K` itself for that step. For very large models
this is the actual point: the matvec's memory use is `O(elements)` (a
handful of small dense matrices) rather than `O(matrix nonzeros)`, and it
sidesteps bandwidth/profile concerns entirely, which is what a skyline
solver's memory and factorization cost scale with. Element stiffness is
precomputed once per freedom case (`fem_pcg.PrecomputeElementData`) and
reused across every load case and every PCG iteration.

## Preconditioning: IC(0), with a bounded shift fallback

Plain Jacobi (scalar diagonal) preconditioning was the first version of
this solver, and it had a real, found limitation: a 1,500-bay slender
truss chain (6,001 elements — `linstatic` solves it directly in 50ms)
**failed to converge in 60,010 PCG iterations**. That's a known weakness
of diagonal preconditioning for high-aspect-ratio, bending-dominated
structural systems, not a tuning problem.

The fix is incomplete Cholesky, zero fill-in (IC(0)) — the same
mathematical derivation as `fem_skyline`'s LDL^T factorization, adapted
from skyline's contiguous envelope to a true sparse CSR pattern built
from element connectivity (`fem_pcg.BuildCSRPattern` /
`AssembleCSRValues` / `ICFactorize`). This is the *one* place `linsparse`
assembles anything resembling a global matrix — and it's genuinely
sparse (only real nonzeros, no skyline-style envelope fill), built once
per freedom case purely to construct the preconditioner. The matvec
itself stays element-by-element throughout.

**A real wrinkle, and how it's handled.** Dropping fill-in during an
incomplete factorization can make an intermediate pivot go non-positive
even when the full matrix is genuinely positive definite — a known IC(0)
phenomenon, confirmed here on two different truss models that both broke
down at the identical local equation number (same repeating geometry
near their support), while `linstatic`'s direct solve on the same models
succeeded without any singularity warning. `BuildIC0WithFallback` handles
this with a small, **bounded** diagonal shift, retried with increasing
magnitude on breakdown, capped at 1% of the matrix's average diagonal.
The cap matters: it's what stops this from being able to mask a
genuinely unstable model (a mechanism, say) into producing a
plausible-looking wrong answer — a true non-PD system still fails, past
the cap, with a clear error naming what happened. See case 907 in
`tests/regression/` for the mechanism case still being correctly
rejected with this fallback active.

**Verified fixed**, not just patched: the previously-failing 1,500-bay
chain now converges in 9,494 iterations (a real diagonal shift was
needed there); the medium test case that also broke down converges in
66 iterations (fewer than plain Jacobi's 372, since IC(0) is a
genuinely stronger preconditioner whenever it doesn't need shifting).
Every regression case that used to run under Jacobi still passes.

`FEM_DEBUG=1` reports the iteration count and, when relevant, the shift
that was needed.

## Threading — implemented correctly, but not validatable in this environment

The matvec is naturally parallel (each element's contribution is
independent), so it's the obvious place to thread. Two real things were
learned building this, both worth knowing before trusting any threading
claim about this solver:

**Per-iteration OS thread spawning is catastrophic.** The first version
spawned N threads per matvec call, joined them, repeated next iteration.
A ~240-element model that converges in 10ms single-threaded still hadn't
finished after 30 seconds with 4 threads. Fixed with a persistent worker
pool (`fem_pcg.TMatVecWorker`): threads created once per solve, woken
each iteration via a lightweight `RTLEvent` rather than respawned.

**Synchronization strategy matters, but the *direction* it matters
depends entirely on core count — and this development environment has
exactly one CPU core** (`nproc` = 1). That changes what can honestly be
claimed here. Two synchronization strategies were built and compared:

- **Event-based** (`fem_pcg.TMatVecWorker`, the default): blocking
  `RTLEvent` wake/wait, which goes through the kernel (a futex wake is a
  context switch) on every dispatch.
- **Spin-based** (`fem_pcg.TSpinWorker`, opt-in via `FEM_SYNC=spin`):
  busy-spin on an `Interlocked`-guarded flag, padded to its own 64-byte
  cache line per worker to avoid false sharing between threads polling
  adjacent flags. This avoids the kernel round-trip entirely — the
  standard fix for exactly this "many short parallel bursts" pattern in
  HPC code, *when genuine parallel hardware is available to spin on*.

Measured on the 6,162-element compact grid: single-threaded 0.14s,
4 threads event-sync 0.49s, 4 threads spin-sync 1.80s. Spin was worse,
not better — the opposite of the HPC-conventional-wisdom prediction, and
directly explained by the single core: a spinning "waiting" thread
doesn't yield the CPU, so on one core it starves the worker thread that
needs that same core to actually compute, while blocking sync correctly
yields and lets the scheduler run the worker. **Every threading
measurement in this file was taken somewhere that cannot demonstrate a
parallel speedup even in principle** — there is no second core for
concurrent work to land on. What *is* real and portable from this
testing: per-iteration synchronization has measurable, non-trivial fixed
overhead regardless of mechanism, and naive per-iteration thread spawning
is unconditionally wrong. Which synchronization strategy wins, and
whether threading helps at all, needs re-measuring on genuine multi-core
hardware — the code for both is in place and correct (both produce
identical results to single-threaded on every regression case), but
their relative performance claim in this file should be read as
"measured on 1 core," not "true in general."

`ElementCountThreadThreshold` (`fem_pcg.pas`) stays at a deliberately
high default (50,000 elements) so threading remains off by default until
it's validated somewhere the question is actually answerable. Both it
and the sync strategy are runtime-overridable for experimentation:
`FEM_THREADS`, `FEM_THREAD_THRESHOLD`, `FEM_SYNC=spin|event`.

## GPU offload

Deliberately not attempted yet. The workload here — many small (6x6 or
12x12) element matrices, with a hard sequential dependency between PCG
iterations (no pipelining across iterations, each needs the previous
one's result) — means every iteration would still need a host<->device
round trip, and GPU kernel-launch + sync latency is typically in the same
tens-of-microseconds range as what's currently bottlenecking this on
CPU. GPU compute wins when latency can be amortized over a lot of
resident work per call or many independent calls in flight; neither is
true here without restructuring the algorithm itself. Worth revisiting
once it's established that CPU-side synchronization overhead is actually
the binding constraint on real multi-core hardware -- not before.

## When to use which

- **`linstatic`**: the reliable default. Exact (to machine precision),
  robust regardless of geometry, and — for the model sizes this suite has
  actually tested — fast. Use this unless you have a specific reason not to.
- **`linsparse`**: matrix-free by design (the actual point for scaling
  past what a skyline profile can hold in memory), and now robust on
  geometry that broke the first version (slender/bending-dominated
  structures, via IC(0)). Verified against `linstatic` to 7+ significant
  figures on every applicable regression case. Threading exists and is
  correct but its performance benefit is unvalidated pending real
  multi-core measurement -- see above.

## Exit codes

Same convention as every solver: 1=usage, 2=load error, 3=model failed
validation, 4=solver-level failure (IC(0) breakdown past the shift cap,
PCG non-convergence, or a non-positive-definite system caught mid-solve).
