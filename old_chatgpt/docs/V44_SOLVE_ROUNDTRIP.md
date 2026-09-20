# FEM3D v0.44 — GUI → CLI Solver → Results Round Trip

This is a surgical continuation of v0.43. It does not replace MainUnit wholesale conceptually; the supplied MainUnit.pas is the current source with the round-trip edits applied.

## Solver contract

`FEM3D_LinStatic.exe model.fem3d` is the complete invocation. There are no solver options or analysis-selection arguments. All solver inputs belong to the persisted model/analysis case.

The solver writes `<model>.fem3dres` beside the model. It writes a result document for both success and failure. On failure, `[ERRORS]` contains machine-readable diagnostic lines and the GUI can display them. stdout is deliberately minimal and reports only `RESULT_FILE=...`.

## GUI workflow

The desktop application now keeps the actual model filename. Opening/saving a model records that filename. `Solve -> Linear Static` saves the current model, invokes the solver with exactly one argument (the model filename), loads the resulting result document even when the solver reports failure, and displays diagnostic errors through the existing Inspector.

## Existing result contours

The current result-field pipeline already supplies displacement magnitude and beam axial stress, plus beam end-force fields. The OpenGL renderer maps the active result field through the existing contour range. This increment deliberately wires the end-to-end workflow before changing the visual renderer, so numerical/result plumbing can be tested independently.

## Important

Source-only. Not compiled in the target Lazarus/FreePascal environment.
