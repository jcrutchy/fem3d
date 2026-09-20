## v0.50 direction

The current development priority is the headless model/validate/solve/result toolchain. The Lazarus GUI is a client of the same shared model and engineering functionality, not a prerequisite for analysis. See `docs/V49_HEADLESS_TOOLCHAIN.md` and `docs/FERRO64_REVIEW.md`.

FEM3D
=====

Current engineering FEA development tree.

Architecture goals
------------------

* transparent, engineer-controlled finite element workflow
* modular and GUI-agnostic analysis/result services
* numerical solvers as completely separate CLI-only executables
* no third-party runtime dependencies in the FEM3D engine
* native Pascal implementation with explicit validation and audit trails
* extensible result fields and visualisation adapters
* human-readable, versioned native model/result formats

Current tree
------------

src/       FEM model, analysis, results, viewport and visualisation code
solver/    isolated command-line numerical solver(s)
tests/     native Pascal verification, contract and end-to-end regression programs
docs/      architecture and engineering notes

The OpenGL viewport uses the Lazarus OpenGLContext package supplied with
Lazarus. This is a platform/framework package, not a third-party FEM
library or numerical dependency.

Build notes
-----------

The source is intended for Lazarus/Free Pascal on Windows x64. The current
GUI project requires the LCL/FCL packages and lazopenglcontext. Numerical
solvers contain no Forms/LCL/OpenGL/plugin/web dependencies.

The package is source-only and has not been compiled in the target user
Lazarus environment during this increment.

Coding style
------------

Pascal source has been kept in a deliberately old-school Borland/Delphi
VCL-like style: explicit types, readable declarations, two-space indentation,
clear begin/end blocks, descriptive identifiers, and minimal abstraction in
GUI code. The project remains Free Pascal/Lazarus code where framework APIs
require it; this is a style convention, not a claim of Delphi compiler
compatibility.

Result visualisation
--------------------

FEMResultVisualisation defines a GUI-independent visualisation scene. The
OpenGL target consumes that scene through FEMResultVisualisationGL. Future
targets can consume the same scene model for SVG, HTML/CSS/HTMX, DXF, or
other exporters without changing result extraction or solver code.

## Headless operation

The model file is intentionally usable without the GUI. `cli/FEM3D_CLI.lpr` provides GUI-independent validation, model inspection, result inspection and solver orchestration. The numerical solver remains a separate CLI-only executable and receives only the model filename.


CLI reliability and regression
------------------------------

The headless toolchain now has a permanent external regression harness. `tests/FEM3D_TestRunner.exe` drives the real CLI through validate/solve, compares results against manually verified beam cases, and exercises deliberately invalid inputs and command-line contract errors.

Run `regression_headless.bat` for the full headless regression set. Verified cases live under `tests/verified`; their model, expected result and manifest fingerprints are frozen in `tests/verified/VERIFIED.INDEX`.

The verified corpus is deliberately small and hand-calculable. It currently covers cantilever bending, axial extension, end moment, and a two-element simply supported beam. New solver features should add independently verified cases before being considered regression-safe.


## v0.51 — headless reliability hardening

The CLI/model/result boundary is now intentionally strict: malformed records, invalid numeric values, duplicate identifiers, unknown records/sections and invalid persisted analysis settings are rejected instead of being silently ignored. Result files are likewise parsed strictly.

The regression runner exercises the public CLI process boundary, has a finite child-process timeout, protects the verified corpus with an index, and compares complete displacement/reaction vectors so unexpected non-zero DOFs cannot hide outside a sparse expected-result file.
