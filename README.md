# FEM Suite

A modular, CLI-first finite element analysis package in FreePascal. Zero
third-party dependencies — only the FPC standard RTL (`fpjson`,
`jsonparser`, `Generics.Collections`, `SysUtils`, `Classes`).

## Architecture

- **Model file → solver executable → stdout.** Each solver is a separate
  `.lpr` program. A model (nodes, elements, properties, freedom cases,
  load cases, combinations, solver params) is a single JSON file passed
  as the one CLI argument; results go to stdout, redirect as needed.
- **Common units, shared by every solver:**
  - `fem_types.pas` — the model's data structures (plain records/arrays,
    no logic).
  - `fem_json_model.pas` — parses a model file into a `TModel`. Only
    checks structural JSON validity (right types, right shape) — no
    semantic checks.
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
  - `fem_sha256.pas` — pure-Pascal SHA-256 (FPC's stdlib `hash` package
    ships MD5/SHA1 but not SHA256), used by the regression harness for
    model/manifest integrity checks.
- **Solvers**, each its own executable under `src/solvers/<name>/`:
  - `linstatic` — linear-static analysis via the skyline solver. The
    first one, and the reference implementation for the conventions above
    (exit codes, KV output, `FEM_DEBUG`, stdin via `-`).
  - `modal` — lumped-mass modal analysis (natural frequencies + mode
    shapes) via a dense Jacobi eigensolve. See `docs/modal.md`. The
    second solver, and the first real test of the "common library,
    separate executable" architecture: shares `fem_types`,
    `fem_json_model`, `fem_validate`, `fem_index`, `fem_dofmap`,
    `fem_elements` with `linstatic`, and only diverges where the physics
    genuinely diverges (mass instead of just stiffness, an eigensolve
    instead of a linear solve).
- **Adaptors** (planned, see `docs/adaptors.md`), under
  `src/adaptors/<format>/` — convert some other ASCII format (Strand7
  `.txt`, etc.) into the canonical JSON model. Solvers never parse
  anything but the canonical format; this is the only place other
  formats enter the pipeline. `adapt_x in.txt | linstatic -`.
- **Tools**, under `src/tools/<name>/`:
  - `fem_regress` — the regression test harness (see
    `docs/regression_testing.md`). Runs manifest-declared cases, checks
    model/manifest integrity via SHA-256, compares solver output against
    hand-verified expectations within tolerance, and separately checks
    that deliberately-invalid ("BORKED") models are correctly rejected.

See `docs/model_format.md` for the full model file schema, exit code
conventions, KV output format, and the `FEM_DEBUG=1` debug dump.

## Building

```
fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/solvers/linstatic/linstatic.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/solvers/modal/modal.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/tools/fem_regress/fem_regress.lpr
```

(`-FE`/`-FU` = executable/unit output dirs, `-Fu` = common-unit search
path. Each new solver/tool/adaptor just needs the same `-Fu` flag pointed
at `src/common`.)

## Running

```
./bin/linstatic examples/aframe_truss.json
./bin/linstatic tests/single_bar.json > results.txt
cat tests/single_bar.json | ./bin/linstatic -          # stdin works too

./bin/modal tests/regression/005_modal_single_dof/model.json

./bin/fem_regress tests/regression --bin bin            # run every regression case
```

## Tests / examples

- `tests/single_bar.json` — single axial bar, closed-form answer
  (`u = PL/AE`); used as a basic regression check.
- `tests/mechanism_should_fail.json` — a 2-member "A-frame" with a
  sliding roller and no bottom chord: statically a 1-DOF mechanism.
  Expected to fail with exit code 4 (singular pivot) — a useful
  regression check that the solver actually detects instability rather
  than silently returning garbage.
- `tests/dangling_ref_should_fail.json` — element references a
  non-existent node; expected to fail with exit code 3.
- `examples/aframe_truss.json` — the same A-frame with the bottom chord
  added (statically determinate), cross-checked independently against a
  NumPy assembly of the same model.
- `tests/regression/` — the same cases (plus the two "should fail" ones),
  wired up as `fem_regress` manifest-driven cases with SHA-256-protected
  models and hand-verified expected values. See
  `docs/regression_testing.md`. This is the version worth trusting and
  extending going forward; the flat files above are just how they were
  worked out during development. 17 cases as of now: 4 truss, 2 beam,
  2 moment frame (an L-shaped cantilever with hand-verified reactions,
  and a statically-indeterminate portal frame cross-checked against
  NumPy), 2 modal, 1 load-case-combination, 1 multi-freedom-case, and
  5 deliberately-BORKED.

## Status / next steps

- [x] Model format + JSON loader (file or stdin)
- [x] Common validation unit
- [x] Skyline matrix library (LDL^T, relative-tolerance singularity check)
- [x] `linstatic`: 3D space-truss elements, prescribed (incl. non-zero)
      displacement constraints, point loads, reactions
- [x] `linstatic`: 3D Euler-Bernoulli beam elements (axial + biaxial
      bending + torsion), variable dofs/node (3 or 6, per-node), a
      configurable orientation reference vector with a sensible default
- [x] Canonical KV output format (`DISP.*` / `REACT.*`)
- [x] Regression harness (`fem_regress`) with integrity-checked manifests
      and both VERIFIED and deliberately-BORKED cases (13 cases: 4 truss,
      2 beam, 2 modal, 5 borked)
- [x] `fem_dofmap`: DOF numbering factored out of `linstatic` into a
      shared unit, so a second solver can't number a model's dofs
      differently
- [x] `modal`: lumped-mass modal analysis via a from-scratch Jacobi
      eigensolver (`fem_eigen`) — the second solver, proving out the
      shared-library architecture for real (see `docs/modal.md`)
- [x] 3D moment frame regression tests (L-shaped cantilever with
      hand-verified reactions; a statically-indeterminate portal frame
      cross-checked against NumPy) — no new element code needed, the
      beam element already models full moment continuity at shared nodes
- [x] Load cases, freedom cases, and combinations (Strand7-style):
      multiple named load/constraint sets per model, solved together
      (one stiffness factorization per freedom case, reused across every
      load case's RHS), plus combinations as exact post-hoc linear
      superposition. Fully backward compatible -- a legacy single-case
      model's output is byte-identical to before. See `docs/model_format.md`.
- [ ] Plate/shell elements, including a 2nd-order variant — substantial
      scope on its own (shape functions, Gauss quadrature, Jacobian-mapped
      B-matrix, membrane/bending coupling); planned as its own incremental
      build (like truss -> beam), not started
- [ ] A compact native format (Strand7-`.txt`-like: sectioned, tabular
      rows) for both models and solver results, replacing JSON as the
      primary format (JSON becomes an adaptor input) once real models
      reach node/element counts where JSON's verbosity actually matters;
      results filenames specified per-solver in the model file rather
      than solvers only writing to stdout. Planned as its own dedicated
      pivot, not started
- [ ] Adaptors for other ASCII formats (Strand7 `.txt` first candidate;
      see `docs/adaptors.md` — low priority for now, not started)
- [ ] Rotary inertia for beam elements, so `modal` can handle a beam's
      rotational dofs when they're free rather than requiring them fixed
- [ ] A third solver would be the next real test of the shared-library
      pattern (nonlinear static? a sparse/iterative modal for larger
      models?)
