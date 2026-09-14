# FEM3D External Solvers

The solver family is intentionally process-isolated from the modelling GUI.

## Current executables

| Executable | Analysis | State |
|---|---|---|
| `FEM3D_LinStatic.exe` | Linear Static | Reference dense LDL^T implementation |
| `FEM3D_Buckling.exe` | Linear Buckling | External boundary established; numerical solver gated |
| `FEM3D_Nonlinear.exe` | Nonlinear Static | External boundary established; numerical solver gated |

Each solver accepts a prepared FEM3D ASCII model file and an optional analysis-case ID. The modelling application launches the same executables rather than embedding numerical solution code in the GUI.

## Solver-core isolation

Solver projects use the snapshot under `solver/core/`. They do **not** compile numerical units directly from the GUI `src/` directory. This creates a deliberate validation boundary: changes to rendering, selection, contours, result tables and other viewer functionality cannot silently change the solver kernel.

When the numerical kernel changes, increment its solver/kernel revision and repeat the appropriate verification and validation work.

The buckling and nonlinear executables deliberately return an explicit `NOT_IMPLEMENTED` result rather than producing unverified engineering results.
