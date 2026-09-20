# FEM3D Architecture â€” Process-Isolated Solvers

## Principle

FEM3D separates model authoring/presentation from numerical solving.

```text
FEM3D.EXE
  model editor / viewport / analysis UI / result viewer
          |
          | persisted ASCII analysis deck
          v
FEM3D_LinStatic.exe
FEM3D_Buckling.exe
FEM3D_Nonlinear.exe
          |
          | persisted result file
          v
FEM3D.EXE
```

The GUI is therefore not the numerical authority. The solver executable is the authority for the calculation it performs, and its result file records the solver, settings and model/analysis fingerprints.

## Analysis definition

An analysis case is model data, not a GUI state. It contains:

- stable ID and name;
- analysis type;
- referenced load case;
- solver-specific settings;
- associated result identifier.

This makes GUI, command line and future batch processing use the same analysis definition.

## Solver isolation

The modelling program launches solvers as child processes. A solver can therefore be run directly from a Windows command prompt without the modelling GUI.

The first CLI contract is:

```text
FEM3D_LinStatic.exe --info
FEM3D_LinStatic.exe --validate model.fem3d
FEM3D_LinStatic.exe --solve [--case N] model.fem3d
```

## UI plugins

Solver-specific GUI configuration is intended to become a DLL boundary once the settings format is sufficiently stable. The DLL should use a small C-compatible ABI and should not exchange Lazarus object instances across the module boundary.

The DLL is presentation/configuration only. Numerical solution remains in the EXE.

## Numerical implementation policy

Linear Static currently has a dense LDL^T reference implementation. It is deliberately retained as a verification/reference path while a production sparse/profile solver is developed.

Linear Buckling and Nonlinear Static have their analysis definitions and external process boundaries, but their numerical implementations remain gated. FEM3D must not report unverified buckling or nonlinear results as engineering results.

## Result-field architecture

Linear Static results are exposed to the GUI through `TResultField` objects. A field has an identifier, engineering name, units, entity location (node or element), entity IDs and scalar values. This deliberately separates numerical result production from display and derived-result evaluation.

The first result fields include displacement components/magnitude, reaction components/magnitude and beam axial stress. The viewport can contour any scalar field using the same renderer and can display the displaced geometry using the translational displacement fields.

A deterministic expression evaluator provides arithmetic and a small set of mathematical functions (`ABS`, `SQRT`, `MIN`, `MAX`) over compatible result fields. It is intentionally not a scripting engine. The intended future use is engineering-derived quantities such as utilisation, safety factors and fatigue-life equations while keeping the calculation auditable.
