# Solver Isolation and Validation Boundary

FEM3D deliberately separates numerical solver executables from the modelling and results UI.

## Why

A viewer, renderer, contour, selection tool or other GUI feature should not invalidate a previously verified numerical kernel. The numerical solver is therefore built from a **solver-core snapshot** under `solver/core/`, not from the GUI's `src/` tree.

The snapshot contains the model/schema reader and numerical units required by the solver. Changes to the GUI source tree do not silently change the compiled solver kernel.

## Validation boundary

The Linear Static reference solver has an explicit identity:

- Solver ID: `FEM3D_LinStatic`
- Kernel: `ReferenceDenseLDLT`
- Kernel revision: `RS-001`
- Model contract: `FEM3D_ASCII_0.7`
- Result contract: `FEM3D_RESULT_0.7`

A numerical change requires a new kernel revision and a corresponding validation review. A viewer-only change does not.

## Provenance

Linear Static result files record:

- solver version
- solver kernel
- solver kernel revision
- model contract
- result contract
- model fingerprint
- analysis fingerprint

This allows an engineering result to be traced back to the exact solver boundary that produced it.

## Important distinction

Isolation is not a claim that the current solver is fully validated. The dense LDL^T implementation remains the **reference solver** and must pass the native verification suite and engineering benchmark cases when compiled and executed in the development environment.

Isolation simply ensures that subsequent UI work does not accidentally alter that numerical implementation.
