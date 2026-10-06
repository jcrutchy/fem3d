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
  - `fem_matrix.pas` — shared small-matrix/vector utilities: 3D vector ops,
    local-frame construction for quads, closed-form 2x2/3x3 inverses, a
    general dense inverse/multiply/transpose, and the structured element
    transforms (`TransformBlockDiag` for `T^T*K*T`, `AccumBtDB` for
    `B^T*D*B`) that `fem_elements` uses everywhere instead of per-element
    inline loops. Pure Pascal; an optional SSE2 `RowAxpy` kernel is
    available with `-dFEM_USE_ASM` (x86-64 Linux/Win64). Verified by
    `src/tools/matrix_test`.
  - `fem_fingerprint.pas` — the model fingerprint: SHA-256 of the model
    file's canonical text (comments, blank lines, indentation and line
    endings ignored), printed by every solver as `MODEL.FINGERPRINT=` so a
    viewer can detect results that are stale for the model it is showing.
    Checked by `src/tools/fingerprint_test`; rule in `docs/native_format.md`.
  - `fem_results.pas` / `fem_results_out.pas` — element force and stress
    recovery (truss axial force; shell membrane/bending/face stresses; beam shear/moment/torque at
    `BeamDivisions` stations, in local and global axes, with extreme-fibre
    stress, von Mises and Tresca) and the shared writer that `linstatic`
    and `linsparse` both use to print it. See "Element forces and stresses"
    in `docs/native_format.md`. Checked by regression cases 020–024 and
    `src/tools/results_test` and `src/tools/shell_results_test`.
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
  - `femresolve` — resolves a `.femref` (a model that refers to a section
    catalogue or a `femsection` `.prop` file) into a plain `.fem` with the
    referenced values copied in; solvers never read references. See
    `docs/femref.md`. `femresolve model.femref | linstatic -`.
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
    src/adaptors/femresolve/femresolve.lpr

fpc -MObjFPC -Sh -O2 -FE./bin -FU./bin -Fu./src/common \
    src/tools/fem_regress/fem_regress.lpr
```

(`-FE`/`-FU` = executable/unit output dirs, `-Fu` = common-unit search
path. Each new solver/tool/adaptor just needs the same `-Fu` flag pointed
at `src/common`.)

The same pattern builds the remaining programs: `src/tools/femsection`,
`src/tools/femgeocheck`, `src/adaptors/dxf2femgeo` and the test programs in
`src/tools/*_test` and `src/tools/patch_test`. On Windows with Lazarus,
`build.bat` compiles every `.lpi` in the tree into `bin\`, `test.bat` runs
everything, and `run.bat` does both.

## Repository layout

```
src/common/      shared units (model, solvers' maths, section, geometry, crack growth)
src/solvers/     linstatic, linsparse, modal
src/adaptors/    adapt_json, femresolve, dxf2femgeo (IGES/STEP adaptors: not yet written)
src/tools/       fem_regress, femsection, femgeocheck, femrun (web gateway), test programs
db/              section catalogues (liberty_db.json)
docs/            all documentation (formats, tools, tutorials, TODOs)
examples/        example inputs (section .fgeo files, rivet-flange DXF/FGEO)
tests/           regression/ (fem_regress cases), geometry/ (.fgeo fixtures),
                 liberty/ (catalogue-vs-calculator manifest)
viewer/          web results viewer
section_editor/  single-file browser section editor (writes .fgeo)
bin/             build output (not committed)
```

## Running

```
./bin/linstatic tests/regression/001_single_bar/model.fem
./bin/linstatic tests/regression/001_single_bar/model.fem > results.txt
cat tests/regression/001_single_bar/model.fem | ./bin/linstatic -   # stdin works too

./bin/modal tests/regression/005_modal_single_dof/model.fem

./bin/linsparse tests/regression/011_sparse_single_bar/model.fem
FEM_THREADS=8 ./bin/linsparse some_large_model.fem   # see docs/linsparse.md before relying on this for speed

./bin/adapt_json some_old_model.json > model.fem   # bring in a JSON model
./bin/femresolve model.femref > model.fem          # resolve section references (docs/femref.md)

./bin/fem_regress tests/regression --bin bin        # run every regression case
```

## Tutorials

`docs/tutorials/` — a graduated series of worked examples (single truss
bar → cantilever beam → portal frame → natural frequencies of a
two-mass chain, more to come), aimed at someone
learning FEA itself, not just this package: theory, an annotated model
file, and the solver's actual verbose output read line by line against
a hand calculation (or, once hand calculation stops being possible, an
independently cross-checked one). Every tutorial's model is a real
`tests/regression/` case — start there if you're new to this project.

## Tests / examples

- `tests/regression/` — `fem_regress` manifest-driven cases with
  SHA-256-protected models and hand-verified (or, where hand calculation
  isn't possible, independently cross-checked) expected values. See
  `docs/regression_testing.md`. Cases run in name order, so the report is the same on every machine. 59 cases, split roughly evenly between
  VERIFIED (truss, beam, moment frames including a statically-
  indeterminate portal frame cross-checked against NumPy, modal,
  shellq4/shellq8 membrane patch tests, load-case combinations,
  multi-freedom-case models, several re-run through `linsparse` to
  cross-check it against `linstatic`) and deliberately BORKED (bad
  geometry, dangling references, non-positive properties, mechanisms,
  unsupported element/solver combinations, and the like — each checked
  for the *specific* rejection reason, not just a nonzero exit code).
  Each case directory keeps both `model.fem` (what solvers actually
  read) and, where applicable, the original `model.json` it was
  converted from via `adapt_json`, as a working round-trip check.
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
      not a from-first-principles formulation.
- [x] 2nd-order plate/shell element `shellq8` — 8-node quadratic
      Mindlin-Reissner (shear-deformable) flat shell with selective
      reduced integration; membrane, bending/shear, combined-shell, and
      global-3D layers each patch-tested independently (44 checks across
      four standalone programs), wired through the same pipeline as
      `shellq4`, and covered end-to-end by a regression case whose
      expected reactions were derived independently. A thin-plate-only
      discrete-Kirchhoff 8-node variant is kept in reserve as an
      alternative formulation.
- [x] Tutorial-style verbose solver output (default on; `Verbose=0` for
      terse) with physical self-checks, in all three solvers.
- [x] Hardening pass from an external code review, each claim verified
      against the code first (about half held up): spin-wait yields
      instead of starving, corner-orientation validation for shell
      quads (concave / bow-tie / degenerate corners rejected as model
      errors), `PivotTolerance` solver parameter, typed constants
      untyped, duplicate test file removed.
- [x] One-command build and test on Windows: `run.bat` = `build.bat` (every
      `.lpi` under the repo, via `lazbuild`) then `test.bat` (every
      `bin\*test*.exe`, the geometry fixtures, and the `fem_regress`
      suite; exits non-zero if anything failed). `build.bat nopause` /
      `test.bat nopause` skip the final pause for scripted use.
- [x] Review of the Windows build/test logs: everything builds (0 errors) and
      52/52 pass; the 296 numbers printed match a Linux build digit for
      digit. It exposed 8 regression manifests whose integrity hashes sat in
      the wrong section and were never checked -- now fixed, with `fem_regress`
      failing such a manifest, `--update-hashes` always writing into `[FILES]`
      (and hashing in the right order), cases run in name order, and manifest
      hashing independent of the Windows code page.
- [x] Shared matrix/vector library `fem_matrix` (block-structured element
      transforms, B^T·D·B accumulation, small inverses, dense helpers, an
      optional SSE2 kernel behind `-dFEM_USE_ASM`); the per-element inline
      copies were removed. Verified by `src/tools/matrix_test` and a
      differential test against the previous element code (stiffness
      matrices agree to ~6e-16).
- [x] Element forces and stresses: truss axial force/stress; beam
      N/Vy/Vz/T/My/Mz at `BeamDivisions` stations in local and global axes,
      with extreme-fibre stress, von Mises and Tresca; shellq4/shellq8
      membrane forces, bending moments, (shellq8) shear forces, and
      top/bottom face stresses with principal values, von Mises and
      Tresca. Regression cases 020-031, plus `results_test` and
      `shell_results_test`. See `docs/native_format.md`.
- [x] External code review (Gemini) triaged against the code: fixed the
      skyline solver accepting negative pivots (an indefinite system was
      "solved"; also unchecked pivots on columns with no off-diagonals),
      locale-dependent number parsing in `dxf2femgeo` (comma-decimal systems
      silently produced all-zero geometry; `-dFEM_TEST_COMMA_LOCALE` now
      reproduces it), the shellq4/shellq8 flatness tolerance (now relative to
      the shorter edge; regression case 919), and an unguarded `Smax/sigma0 >= 1`
      in the Newman closure. Per-iteration allocation in PCG removed
      (byte-identical results). Checked by `src/tools/skyline_test`.
- [x] Results viewer, web version (`viewer/`): plain HTML/CSS/JS, no
      dependencies. A "dumb" viewer of a model file + solver output: 3-D
      view with deformed shape, contours and curved beams; selecting an
      element shows its force and stress diagrams, section view, Mohr's
      circles and tables in a side panel. Solvers now print
      `MODEL.FINGERPRINT` (SHA-256 of the canonical model text) and the
      viewer refuses results that are not for the model it was given. See
      `viewer/README.md`. A Lazarus version is still open; the format the
      viewer reads is the same `DISP/REACT/ELEM` key=value output.
- [ ] Geometry/CAD web app (vanilla JS, headless core, CLI-backed through a
      vdrx route; eventually replaces `cad/cad.htm`): proposal and
      milestones in `docs/cad_architecture.md`
- [ ] Viewer: solve from the browser through a vdrx route; JSON models and
      modal results; depth-correct ordering of intersecting shells
- [ ] Shell stress averaging across elements (nodal smoothing) and
      Gauss-point output, if the unaveraged centroid/corner values prove
      too coarse in practice
- [ ] Adaptors for other ASCII formats (Strand7 `.txt` first candidate;
      see `docs/adaptors.md` — low priority for now, not started)
- [x] `modal` on beam frames with free rotations: the massless rotational
      dofs are eliminated exactly by static condensation (no longer
      required to be fixed). Regression case 035, cross-checked against an
      independent NumPy reference (~1e-15). Not done: genuine rotary
      inertia (so no pure torsional modes); see `docs/modal.md`
