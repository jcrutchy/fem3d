# v0.50 — CLI reliability and verified regression corpus

This increment makes the headless pipeline a regression-testable engineering workflow rather than a collection of individual smoke commands.

## End-to-end regression path

`tests/FEM3D_TestRunner.exe` launches the real `FEM3D_CLI.exe` as an external process. Verified cases therefore exercise:

1. native model-file parsing;
2. model validation;
3. CLI argument handling;
4. external solver discovery/process launch;
5. the strict one-argument solver boundary;
6. solver result-file creation;
7. result parsing and numerical comparison.

The runner does not call the solver's internal numerical classes directly.

## Verified corpus

`tests/verified/` contains small, manually hand-calculated cases. Each case has:

- `model.fem3d` — frozen input;
- `expected.fem3dres` — frozen reference quantities;
- `manifest.ini` — comparison tolerance and file names.

The current corpus includes:

1. cantilever tip Z load;
2. cantilever axial load;
3. cantilever tip Y load;
4. cantilever end moment;
5. two-element simply supported beam with centre point load.

The values are analytical Euler-Bernoulli beam results. The reference result files intentionally contain only the quantities needed by the regression comparison; the current solver's complete result remains the actual output.

## Corpus protection

`tests/verified/VERIFIED.INDEX` stores FNV-1a-64 fingerprints for each manifest, model and expected-result file. The normal runner refuses to execute a case whose fingerprint has changed. A change must therefore be explicitly re-frozen with:

    FEM3D_TestRunner.exe --freeze-verified

This is tamper/accidental-change evidence, not a cryptographic signature. Source control remains the authoritative review history for changes to verified engineering data.

## Invalid-input corpus

`tests/invalid/` contains deliberately bad models. These test that malformed input is rejected with predictable exit codes and useful diagnostics. New parser/validation bugs should normally become permanent invalid-input regression cases.

## CLI contract correction

The CLI command dispatcher now validates argument counts per command. In particular, `verify` correctly accepts exactly one argument (the command itself); the previous global `ParamCount < 2` gate made that command unreachable.

## Process safety

The GUI/CLI solver process wrapper now has a finite ten-minute process timeout and catches process-start exceptions. A hung solver can therefore not leave the calling application waiting indefinitely.

## Commands

Normal full regression:

    regression_headless.bat

Build only:

    build_headless.bat

Freeze/re-freeze verified corpus after independent review:

    freeze_verified.bat

The existing `smoke_headless.bat` now runs the complete regression runner in addition to the lower-level verification and round-trip checks.

## v0.51 hardening

The regression harness is now deliberately hostile to both malformed input and unexpected numerical output. Native model and result readers reject malformed syntax rather than silently skipping records or converting bad numbers to zero. Diagnostics include the source line number where possible.

The verified comparison checks every displacement/reaction slot represented by the actual result, treating omitted entries in a sparse expected file as zero. This is important because an unexpected non-zero displacement in a nominally fixed or unloaded degree of freedom is itself a regression.

The regression runner also applies a finite timeout to every child process so a hung CLI or solver becomes a deterministic test failure.


## Reliability boundary

The headless pipeline now treats parsing and semantic validation as separate layers:

- **Parsing** answers whether the file is structurally well-formed and numerically representable. It reports source line numbers and rejects unknown records/sections instead of skipping them.
- **Model validation** answers whether the resulting model is semantically usable: identifiers, references, element topology, physical properties, load data and analysis configuration are checked before assembly.
- **Solver validation** remains responsible for solver-specific constraints such as supported matrix storage and solver identity.
- **Result parsing** rejects malformed result files before their contents can be consumed by visualisation or automation.

This separation is deliberate: a typo in an input file must never quietly turn into a different engineering model.


## Recommended build/CI order

`regression_headless.bat` now runs the native mathematical verification suite, model persistence contract tests, and the external CLI regression corpus. This makes it suitable as the single headless gate for local development or a future CI job.

For each verified model the external runner performs `validate`, `solve`, `results`, and frozen numerical comparison.
