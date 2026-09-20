# `linsparse` — matrix-free, multithreaded linear-static solver

A second linear-static solver, alongside `linstatic`. Same physics, same
model format, same load-case/freedom-case/combination handling, same
output convention — the difference is entirely in how `Kx=f` gets solved:
`linstatic` assembles a skyline matrix and factorizes it directly (exact,
one factorization reused across every load case); `linsparse` never
assembles a global matrix at all, and solves each load case with a
preconditioned conjugate gradient (PCG) iteration built directly from
element contributions.

```
linsparse model.fem
linsparse model.fem > results.txt
FEM_THREADS=8 linsparse model.fem
```

## Why element-by-element (matrix-free)

Every PCG iteration only needs one thing: `y = K·x`. That product can be
computed directly as a sum of small element contributions
(`y_local = K_element · x_local`, scattered into the global `y`) without
ever building or storing `K` itself — no sparse matrix data structure,
no assembly bookkeeping, just a loop over elements. For very large models
this is the actual point: memory use is `O(elements)` (a handful of small
dense matrices) rather than `O(matrix nonzeros)`, and it sidesteps
bandwidth/profile concerns entirely, which is what a skyline solver's
memory and factorization cost scale with. Element stiffness is
precomputed once per freedom case (`fem_pcg.PrecomputeElementData`) and
reused across every load case and every PCG iteration.

## Threading — implemented correctly, not yet shown to help

The matvec is naturally parallel (each element's contribution is
independent), so it's the obvious place to thread. The first version did
exactly the obvious thing — spawn N OS threads per matvec call, join them,
repeat next iteration — and it was catastrophically slow: a ~240-element
model that converges in 10ms single-threaded still hadn't finished after
30 seconds with 4 threads. Creating and destroying OS threads on every
single PCG iteration (a solve can take hundreds to thousands of
iterations) dominates completely.

The fix (`fem_pcg.TMatVecWorker`) is a persistent worker pool: N threads
created once per solve, each assigned a fixed element range for its whole
lifetime, woken each iteration via a lightweight `RTLEvent` rather than
being respawned. This is correct — it produces identical results to
single-threaded, and no longer hangs — but **measured threading benefit
at every model size tested so far (up to ~6,000 elements, a few hundred
PCG iterations) was negative**, not positive: the fixed per-iteration
synchronization cost (two event round-trips per worker) exceeded the
compute time saved by splitting the work four ways, on this test
environment. `ElementCountThreadThreshold` in `fem_pcg.pas` is
consequently set high (50,000 elements) so threading stays off by default
for anything in the size range actually tested — this is a deliberately
conservative placeholder, not a calibrated crossover point. Where that
crossover actually is (if it exists on a given machine) hasn't been
measured; `FEM_THREADS` lets you experiment (`FEM_THREADS=1` forces
single-threaded regardless of model size).

## Preconditioning — a real, found limitation

The preconditioner is plain Jacobi (diagonal) — cheap to build, and
sufficient for well-conditioned problems: every regression case (a
compact 40×40 well-braced truss grid, 6,162 elements, included) converges
in a few hundred iterations. It is **not** sufficient for slender,
bending-dominated geometry: a 1,500-bay-long slender truss chain (6,001
elements — `linstatic` solves it directly in 50ms) failed to converge in
60,010 PCG iterations. This isn't a bug in the implementation; it's a
well-known weakness of diagonal preconditioning for high-aspect-ratio,
bending-dominated structural systems, and it means **`linsparse` is not
currently a safe drop-in replacement for `linstatic` on an arbitrary
large model** — for a long-span or slender structure, `linstatic`'s
direct solve remains the reliable choice regardless of size, until
`linsparse` gets a stronger preconditioner (incomplete Cholesky is the
natural next step — same spirit as the element-by-element approach:
built from the same element data, no global matrix required for a
reasonable approximate factorization either).

`linsparse` raises a clear error rather than returning a bad answer when
it can't solve a model: non-convergence within `max(500, 10·NEQ)`
iterations, or a non-positive search direction (PCG's analogue of
`linstatic`'s zero-pivot check — same underlying truth, a model that
isn't stable/positive-definite, caught a different way). See case 907 in
`tests/regression/` for the mechanism case caught this way.

## When to use which

- **`linstatic`**: the reliable default. Exact (to machine precision),
  robust regardless of geometry, and — for the model sizes this suite has
  actually tested — fast. Use this unless you have a specific reason not to.
- **`linsparse`**: proves the "small element data, no global matrix"
  architecture works and gives correct results (verified against
  `linstatic` on every applicable regression case, matching to 7+
  significant figures). Not yet a demonstrated performance win over
  `linstatic` at any tested scale, and unreliable on slender/bending-
  dominated geometry without a better preconditioner. Useful today mainly
  as the foundation to build on, and as a second, independently-implemented
  numerical method that regression cases can cross-check `linstatic`
  against.

## Exit codes

Same convention as every solver: 1=usage, 2=load error, 3=model failed
validation, 4=solver-level failure (PCG non-convergence, or a
non-positive-definite system).
