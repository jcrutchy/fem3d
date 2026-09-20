# Regression testing — `fem_regress`

A model file alone doesn't build trust; a manually-verified result that's
protected against silent drift does. `fem_regress` is a small harness for
exactly that: given a folder of cases, each with a model, a hand/independently
verified expected result, and a manifest tying them together with SHA-256
hashes, it re-runs every case and reports pass/fail.

## Directory convention

```
tests/regression/<ID>_<slug>/
  manifest.ini
  model.fem
```

`<ID>` is free-form (numeric ranges are just a convention -- this repo
uses 0xx for verified-good cases and 9xx for deliberately-borked ones, so
they sort apart at a glance).

## manifest.ini

```ini
[CASE]
ID=001
Name=Cantilever tip load
Status=VERIFIED
Solver=linstatic
Verification=Manual calculation

[FILES]
Model=model.fem
ModelSHA256=<sha256 of model.fem>
ManifestSHA256=<sha256 of this file, computed with this field blanked>

[EXPECTATIONS]
Tolerance=1E-8
TipUY=-0.0260416666667
ReactionFY=10000

[MAP]
TipUY=DISP.5.y
ReactionFY=REACT.1.y
```

- **`[CASE].Status`** — `VERIFIED` or `BORKED`. `VERIFIED` cases must run
  cleanly and match `[EXPECTATIONS]`. `BORKED` cases are deliberately
  invalid/unstable models that the solver (or `fem_validate` inside it)
  is expected to *reject* -- these matter just as much, because a solver
  that silently "succeeds" on a bad model is worse than one that's merely
  slow or incomplete.
- **`[FILES].ModelSHA256`** — hash of `model.fem` as it stood when the
  expected values were verified. If the model file changes later (even a
  whitespace edit) without the manifest being regenerated, the hash
  mismatches and the case fails loudly rather than silently comparing
  against a model that's since drifted.
- **`[FILES].ManifestSHA256`** — a self-referential hash of the manifest
  itself (computed with this field's own value blanked out, lines joined
  with `\n` regardless of on-disk line endings). Protects the
  `[EXPECTATIONS]` values from casual editing -- if someone "fixes" a
  failing test by loosening the expected number instead of the solver,
  this catches it.
- **`[EXPECTATIONS]`** (VERIFIED only) — `Tolerance` plus any number of
  named values. Names are yours to choose (`TipUY`, `ReactionFY`,
  whatever reads clearly for the case).
- **`[MAP]`** (VERIFIED only) — maps each expectation name to the solver's
  actual KV output key (`DISP.<node>.<dof>` / `REACT.<node>.<dof>` for
  `linstatic` today). If a name is omitted from `[MAP]`, the harness
  assumes the expectation name *is* the solver's key directly.
- **`[EXPECTATIONS]`** (BORKED only) — `ExpectedExitCode` (required) and
  optionally `ExpectedErrorContains` (a substring that must appear in
  stderr). If the solver exits 0 on a BORKED case, that's flagged as a
  **CRITICAL** failure regardless of anything else -- it means the solver
  accepted a model it should have rejected.

## Authoring a case

1. Build `model.fem`, work out the expected values by hand or an
   independent tool, write `[CASE]`/`[FILES]`/`[EXPECTATIONS]`/`[MAP]`,
   leaving `ModelSHA256`/`ManifestSHA256` blank.
2. `fem_regress tests/regression/<case>/manifest.ini --update-hashes`
   fills both in.
3. `fem_regress tests/regression/<case>/manifest.ini` to confirm it
   passes.

## Running

```
fem_regress tests/regression              # every case under the tree
fem_regress tests/regression/001_x/manifest.ini   # a single case
fem_regress tests/regression --bin ./bin  # solver executables live here (default: ./bin)
```

Exit code is 0 iff every case passed -- suitable for a CI gate once/if
there's a CI.

## Solver output capture

`fem_regress` reads a solver's stdout and stderr on two independent
threads (one blocking read-to-EOF per pipe), then calls `WaitOnExit`
once both have finished. This is deliberate, not incidental: alternating
blocking reads between the two pipes can deadlock (stuck reading one
while the child blocks writing a full buffer to the other), and the
seemingly-obvious non-blocking-poll-via-`Proc.Running` alternative has
its own hazard on at least this FPC/platform combination -- querying
`Running` on an already-exited process appears to reap it in a way that
leaves `Proc.ExitStatus` holding the raw, unshifted `wait()` status
(surfacing as exit codes like 768 instead of 3). Two independent threads
sidestep both: no alternation to deadlock on, and `Running`/`WaitOnExit`
are only ever touched once, after both pipes have already hit EOF on
their own.
