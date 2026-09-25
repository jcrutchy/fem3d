# FEM Suite

A modular, CLI-first finite element analysis package in FreePascal. Zero
third-party dependencies — only the FPC standard RTL (`fpjson`,
`jsonparser`, `Generics.Collections`, `SysUtils`, `Classes`).

## Architecture

- **Model file → solver executable → stdout (or a results file).** Each
  solver is a separate `.lpr` program. A model (nodes, elements,
  properties, freedom cases, load cases, combinations, solver params) is
  a single native `.fem` file (see `docs/native_format.md` — sectioned,
  tabular, Strand7-`.txt`-like, not JSON) passed as the one CLI argument;
  results go to stdout by default, or to a file named in the model's own
  `[SOLVERPARAMS]` section.
- **Common units, shared by every solver:**
  - `fem_types.pas` — the model's data structures (plain records/arrays,
    no logic).
  - `fem_native_model.pas` — parses a model file into a `TModel`. The
    format every solver actually reads. Only checks structural validity
    (right shape) — no semantic checks.
  - `fem_native_writer.pas` — writes a `TModel` back out in native
    format; used by `adapt_json`.
  - `fem_json_model.pas` — the original JSON parser. No longer used by
    any solver directly — only by `adapt_json` now, converting JSON
    input into the native format upstream of the solvers.
  - `fem_validate.pas` — the one validation unit every solver runs before
    touching a matrix. Semantic checks: dangling references, duplicate
    ids, unsupported element types, non-positive properties, missing
    constraints, etc. Returns a list of errors; empty = valid.
  - `fem_index.pas` — id → array-index lookup maps (`TDictionary`-based),
    used by both `fem_validate` and the solvers.
  - `fem_skyline.pas` — the common matrix library: symmetric skyline
    storage + in-place LDL^T factorization + solve. Solver-agnostic; any
    solver that needs to solve `Kx=b` for a sparse symmetric system uses
    this.
  - `fem_elements.pas` — element stiffness formulations: the 3D 2-node
    space-truss (axial bar) and the 3D 2-node Euler-Bernoulli beam
    (axial + biaxial bending + torsion). Both return a generic dynamically-
    sized matrix so solvers can assemble either uniformly.
  - `fem_dofmap.pas` — per-node dof counts, global dof numbering, and
    constraint elimination. Shared by every solver so two solvers can
    never number the same model's dofs differently; `linstatic` and
    `modal` both build a `TDofMap` from this unit rather than each
    rolling their own.
  - `fem_eigen.pas` — a from-scratch Jacobi eigenvalue algorithm for
    real symmetric matrices (used by `modal`; general enough for any
    future solver that needs a dense symmetric eigendecomposition).
  - `fem_pcg.pas` — element-by-element (matrix-free) preconditioned
    conjugate gradient with an IC(0) preconditioner (bounded-shift
    fallback for incomplete-factorization breakdown), and a persistent
    multithreaded worker pool (event- or spin-based, selectable) for the
    per-iteration matrix-vector product. Used by `linsparse`. See
    `docs/linsparse.md` for what's actually been verified about it
    (correctness: yes, including on geometry that broke the first
    Jacobi-preconditioned version; threading benefit: unmeasurable in
    this single-core development environment, so genuinely unknown
    pending real multi-core testing).
  - `fem_sha256.pas` — pure-Pascal SHA-256 (FPC's stdlib `hash` package
    ships MD5/SHA1 but not SHA256), used by the regression harness for
    model/manifest integrity checks.
- **Solvers**, each its own executable under `src/solvers/<name>/`:
  - `linstatic` — linear-static analysis via the skyline solver. The
    first one, and the reference implementation for the conventions above
    (exit codes, KV output, `FEM_DEBUG`, stdin via `-`, `ResultsFile`).
    The reference solver: a direct, non-pivoting symmetric-positive-
    definite skyline solve. Not "exact" in a floating-point sense and
    not immune to conditioning problems (a legitimate but badly-scaled
    stiffness matrix can still trip its pivot-rejection threshold) --
    but for a well-posed model it's the most trustworthy of the three,
    and the one the others get checked against.
  - `modal` — lumped-mass modal analysis (natural frequencies + mode
    shapes) via a dense Jacobi eigensolve. See `docs/modal.md`. The
    second solver, proving out the "common library, separate executable"
    architecture: shares `fem_types`, `fem_native_model`, `fem_validate`,
    `fem_index`, `fem_dofmap`, `fem_elements` with `linstatic`, and only
    diverges where the physics genuinely diverges (mass instead of just
    stiffness, an eigensolve instead of a linear solve).
  - `linsparse` — the same linear-static analysis as `linstatic`, but via
    a matrix-free, IC(0)-preconditioned PCG solve instead of a direct
    skyline factorization. See `docs/linsparse.md` for an honest account
    of what this has and hasn't been shown to deliver (correctness:
    verified against `linstatic` on every applicable regression case,
    including a previously-failing slender-truss case now fixed by
    switching from Jacobi to IC(0) preconditioning; threading: correctly
    implemented, two synchronization strategies built and compared, but
    this development environment has exactly one CPU core, so no
    threading performance claim from here should be trusted as general —
    see the doc for what that means concretely).
- **Adaptors**, under `src/adaptors/<format>/` — convert some other
  format into the canonical native model. Solvers never parse anything
  but the native format; this is the only place other formats enter the
  pipeline. See `docs/adaptors.md`.
  - `adapt_json` — converts a JSON model (the format this suite used to
    read directly, before the native format existed) into native `.fem`.
    `adapt_json old.json | linstatic -`.
- **Tools**, under `src/tools/<name>/`:
  - `fem_regress` — the regression test harness (see
    `docs/regression_testing.md`). Runs manifest-declared cases, checks
    model/manifest integrity via SHA-256, compares solver output against
    hand-verified expectations within tolerance, and separately checks
    that deliberately-invalid ("BORKED") models are correctly rejected.
    Captures a solver's stdout/stderr on two independent reader threads
    (see the top of `fem_regress.lpr`) — deliberate, not incidental: it
    dodges both a two-pipe deadlock and an FPC `TProcess.Running` quirk
    that corrupts exit codes, each of which a simpler approach hit in turn.

See `docs/native_format.md` for the file syntax, `docs/model_format.md`
for the schema/semantics (format-agnostic), and `docs/modal.md` for the
modal solver's specifics.

## Building

```
fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/solvers/linstatic/linstatic.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/solvers/modal/modal.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/solvers/linsparse/linsparse.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/adaptors/adapt_json/adapt_json.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/tools/fem_regress/fem_regress.lpr
```

(`-FE`/`-FU` = executable/unit output dirs, `-Fu` = common-unit search
path. Each new solver/tool/adaptor just needs the same `-Fu` flag pointed
at `src/common`.)

## Running

```
./bin/linstatic tests/regression/001_single_bar/model.fem
./bin/linstatic tests/regression/001_single_bar/model.fem > results.txt
cat tests/regression/001_single_bar/model.fem | ./bin/linstatic -   # stdin works too

./bin/modal tests/regression/005_modal_single_dof/model.fem

./bin/linsparse tests/regression/011_sparse_single_bar/model.fem
FEM_THREADS=8 ./bin/linsparse some_large_model.fem   # see docs/linsparse.md before relying on this for speed

./bin/adapt_json some_old_model.json > model.fem   # bring in a JSON model

./bin/fem_regress tests/regression --bin bin        # run every regression case
```

## Tests / examples

- `tests/regression/` — `fem_regress` manifest-driven cases with
  SHA-256-protected models and hand-verified expected values. See
  `docs/regression_testing.md`. 23 cases: 4 truss, 2 beam, 2 moment
  frame (an L-shaped cantilever with hand-verified reactions, and a
  statically-indeterminate portal frame cross-checked against NumPy),
  2 modal, 1 load-case-combination, 1 multi-freedom-case, 5 of the above
  re-run through `linsparse` to cross-check it against `linstatic`, and
  6 deliberately-BORKED (one of them `linsparse`-specific, proving PCG's
  non-positive-definite check catches the same mechanism `linstatic`'s
  zero-pivot check does). Each case directory keeps both `model.fem`
  (what solvers actually read) and, where applicable, the original
  `model.json` it was converted from via `adapt_json`, as a working
  round-trip check.
- `tests/*.json`, `examples/*.json` — earlier, pre-regression-harness
  JSON models from when this suite was worked out during development;
  kept for reference but not wired into anything, and not converted to
  native format (still readable via `adapt_json` if ever needed).

## Status / next steps

- [x] Native model format (`.fem`, sectioned/tabular) + parser + writer;
      every solver reads only this. See `docs/native_format.md`
- [x] `adapt_json`: JSON -> native format adaptor, replacing direct JSON
      support in solvers
- [x] Results can go to a file named in the model's own
      `[SOLVERPARAMS].ResultsFile`, not just stdout
- [x] Common validation unit
- [x] Skyline matrix library (LDL^T, relative-tolerance singularity check)
- [x] `linstatic`: 3D space-truss + Euler-Bernoulli beam elements
      (axial + biaxial bending + torsion), variable dofs/node (3 or 6,
      per-node), configurable beam orientation reference vector
- [x] Canonical KV output format (`DISP.*` / `REACT.*`)
- [x] Regression harness (`fem_regress`) with integrity-checked manifests,
      VERIFIED and deliberately-BORKED cases, threaded stdout/stderr
      capture (fixed a deadlock risk and, in fixing that, an exit-code
      corruption bug the first fix introduced)
- [x] `fem_dofmap`: DOF numbering factored out into a shared unit so two
      solvers can't number a model's dofs differently
- [x] `modal`: lumped-mass modal analysis via a from-scratch Jacobi
      eigensolver (`fem_eigen`) — the second solver, proving out the
      shared-library architecture for real (see `docs/modal.md`)
- [x] 3D moment frame regression tests — no new element code needed, the
      beam element already models full moment continuity at shared nodes
- [x] Load cases, freedom cases, and combinations (Strand7-style):
      multiple named load/constraint sets per model, solved together
      (one stiffness factorization per freedom case, reused across every
      load case's RHS), plus combinations as exact post-hoc linear
      superposition
- [x] `linsparse`: element-by-element (matrix-free) PCG solver.
      Correctness verified against `linstatic` on every applicable
      regression case. `fem_elements.ElementStiffnessFor` factored out
      as a byproduct, removing a third near-duplicate of the truss/beam
      dispatch that would otherwise have been needed
- [x] IC(0) preconditioning for `linsparse`, replacing plain Jacobi,
      with a bounded diagonal-shift fallback for incomplete-factorization
      breakdown. Fixes the real limitation found above: a 1,500-bay
      slender truss chain that failed to converge in 60,010 iterations
      under Jacobi now converges in 9,494 under IC(0). The shift is
      capped small enough that it can't mask a genuinely unstable model
      (verified: the mechanism case is still correctly rejected)
- [x] Persistent-pool threading for `linsparse`'s matvec, two
      synchronization strategies (event-based via `RTLEvent`, spin-based
      via padded `Interlocked` flags), both correct -- but this
      development environment turned out to have exactly one CPU core,
      so no performance claim about either is trustworthy as a general
      result; see `docs/linsparse.md` for what was actually learned
      (per-iteration thread spawning is unconditionally wrong; which
      sync strategy wins depends on real core count, unmeasured here)
- [ ] Re-measure `linsparse` threading (event vs. spin, and whether
      threading helps at all) on genuine multi-core hardware -- the
      current high default thread-count threshold is a placeholder
      pending that, not a calibrated value
- [x] Plate/shell elements — 1st-order (flat, linear) `shellq4` built,
      verified (57-check standalone patch-test suite covering membrane,
      DKQ bending, and the combined flat shell's full 6-rigid-body-mode
      invariance), and wired through the full pipeline (native/JSON
      format, `fem_validate`, `fem_dofmap`, `linstatic`/`linsparse`; not
      yet supported by `modal` -- no shell mass matrix, rejected by
      name). Drilling dof (`rz`) uses a documented artificial penalty,
      not a from-first-principles formulation. 2nd-order (curved-edge)
      not started.
- [ ] Adaptors for other ASCII formats (Strand7 `.txt` first candidate;
      see `docs/adaptors.md` — low priority for now, not started)
- [ ] Rotary inertia for beam elements, so `modal` can handle a beam's
      rotational dofs when they're free rather than requiring them fixed
