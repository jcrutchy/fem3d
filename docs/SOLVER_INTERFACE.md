# FEM3D Solver Interface — v0.7

## Purpose
FEM3D separates modelling from numerical solution. The GUI prepares a complete ASCII input deck and launches an independent solver process. The solver has no dependency on the GUI.

## Linear static command line
```text
FEM3D_LinStatic.exe --info
FEM3D_LinStatic.exe --validate model.fem3d
FEM3D_LinStatic.exe --solve model.fem3d
```

Exit codes:
- `0` success
- `2` command-line usage error
- `3` input/read error
- `4` model validation failure
- `5` no analysis case
- `6` wrong analysis type for this executable
- `7` unsupported matrix storage
- `8` unsupported solver implementation

## Input contract
The input is the native FEM3D ASCII model file. Analysis cases are persisted in blocks such as:

```text
[ANALYSIS_CASE 1]
Name=Linear Static — LC1
Type=LinearStatic
LoadCase=1
[SETTINGS]
Solver=Reference dense LDL^T
MatrixStorage=Dense
PivotTolerance=1e-12
ResidualTolerance=1e-8
CheckEquilibrium=1
CheckEnergy=1
RecoverElementForces=1
StoreSolverData=1
[END_ANALYSIS_CASE]
```

The current solver selects the first analysis case. A future revision will support explicit case selection (`--case`) and multiple solver implementations.

## Output contract
`--solve` writes `<input basename>.fem3dres`. The result contains:
- analysis case/type
- solver name
- model and analysis fingerprints
- equation counts
- residual/reaction/energy diagnostics
- displacement vector
- reaction vector
- audit trail

## Plugin boundary
Solver-specific GUI code may later be supplied as a DLL/plugin. It should create and validate the persistent analysis settings; it must not contain the numerical solver implementation. The EXE remains independently runnable and testable.

## Primary solver family

The initial solver family is deliberately limited to the three commonly used structural analyses:

- Linear Static — active reference implementation.
- Linear Buckling — analysis definition and external-process boundary established; numerical formulation gated pending geometric-stiffness verification.
- Nonlinear Static — analysis definition, load-step controls and external-process boundary established; numerical formulation gated pending nonlinear element/tangent verification.

The modelling application does not contain these numerical solver implementations as its primary execution path. It prepares an ASCII FEM3D input deck and launches the corresponding solver executable.

### CLI contract

Linear Static:

```text
FEM3D_LinStatic.exe --info
FEM3D_LinStatic.exe --validate model.fem3d
FEM3D_LinStatic.exe --solve [--case N] model.fem3d
```

The result is written beside the input model with the `.fem3dres` extension. Result files contain analysis identity, solver identity, fingerprints, numerical summary and the audit trail.

Buckling and nonlinear static use the same process boundary and file convention, but currently terminate with an explicit `NOT_IMPLEMENTED` status rather than producing engineering results. This is intentional: no solver is considered production-capable until its formulation has independent analytical and regression verification.

### UI plugin boundary

Solver-specific GUI configuration is intended to become an optional Windows x64 DLL/plugin layer. The DLL owns presentation and settings validation; the numerical solver remains an independent EXE. The model file remains the authoritative persisted analysis definition.
