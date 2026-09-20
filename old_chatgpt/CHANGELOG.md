# Changelog

## 0.51.0 — Headless reliability hardening

- Hardened native model parsing: malformed records, invalid numeric values, duplicate IDs, unknown records/sections and unterminated analysis cases are rejected with line-numbered diagnostics.
- Native model numeric parsing is invariant to the host decimal separator.
- Analysis-case type is now selected before settings are applied, preventing persisted type metadata from being silently lost.
- Hardened result parsing with strict headers, required status, finite numeric values, vector-index checks, duplicate-index detection and DOF consistency checks.
- End-to-end regression comparison now checks zero-valued/unlisted DOFs as well as non-zero reference quantities.
- Regression child processes now have a finite timeout.
- Added invalid result-file regression cases.
- Expanded invalid model corpus.
- CLI now catches otherwise-unhandled exceptions at its process boundary and emits a stable fatal diagnostic.


## v0.50 — CLI reliability and verified regression corpus

- Added external end-to-end `FEM3D_TestRunner.exe`.
- Added manually verified linear-static beam corpus.
- Added invalid-input regression corpus.
- Added frozen corpus fingerprints with explicit re-freeze workflow.
- Added five hand-calculable beam benchmark sets:
  - cantilever tip Z load;
  - cantilever axial load;
  - cantilever tip Y load;
  - cantilever end moment;
  - simply supported two-element centre-load beam.
- Fixed CLI command-dispatch argument-count bug that made `verify` unreachable.
- Added ten-minute solver process timeout and process-start exception handling.
- Added `regression_headless.bat` and `freeze_verified.bat`.
- Expanded headless smoke test to include the end-to-end regression corpus.
