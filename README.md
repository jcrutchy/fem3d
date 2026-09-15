# FEM3D

Current increment: v0.35 - Viewport Box Selection.

The viewport supports perspective/orthographic inspection, engineering selection, interactive model creation/editing, and now window/crossing box selection with Ctrl-additive selection.

## v0.21 — Engineering viewport

The current viewport increment makes camera-aware picking and the existing sectioning foundation part of the same rendering path.

- Perspective/orthographic screen-ray picking for nodes and line elements.
- Four-plane clipping state is now consumed by OpenGL; the current GUI drives the primary plane.
- Primary clipping can reverse the retained side.
- Presentation-only sectioning remains outside the solver boundary.

# FEM3D v0.30 — Interactive Modelling and Beam Meshing

Native Lazarus/FreePascal 3D finite-element application foundation.

## What changed in v0.5

A verification pass also caught and corrected a dimensional error in the original beam bending stiffness coefficients: the `12EI` terms now use `12EI/L^3` and the `6EI` coupling terms use `6EI/L^2`. This is exactly the sort of defect the analytical regression suite is intended to expose.

This increment deliberately prioritises **trustworthiness and traceability over UI polish**.

### Analysis correctness

- Explicit `TDOFNumbering` abstraction separates equation numbering from node storage order.
- Constraint handling preserves the **unmodified global stiffness matrix and load vector** so reactions can be recovered from the original equilibrium equations.
- Solver residuals are now evaluated on the **free equations**, rather than incorrectly treating support reactions as numerical residual error.
- Support reactions are recovered from `K_original * U - F_original`.
- The solver reports constrained DOF count, free-equation residual and maximum reaction magnitude.
- Singular/ill-conditioned pivots are rejected explicitly.

### Model validation

A separate `FEMValidation` layer reports structured diagnostics for:

- duplicate IDs;
- invalid material properties;
- invalid beam-section properties;
- missing node/material/section/load-case references;
- repeated element nodes;
- zero-length 3D beams;
- orphan nodes;
- empty models/elements.

Validation is performed before assembly.

### Audit trail

Each analysis records a compact audit trail containing:

- model size and equation count;
- validation result and warning count;
- assembly diagnostics;
- number of constrained equations;
- solver identity.

The trail is currently attached to the analysis result message. It will become a first-class persistent analysis record as the document/result architecture matures.

### Verification suite

`tests/verify.lpr` is a native Pascal verification runner. No Python or external numerical library is required.

Current benchmarks:

1. cantilever bending in global Z â€” analytical Euler-Bernoulli solution;
2. cantilever bending in global Y â€” analytical solution;
3. cantilever axial extension â€” `PL/EA`;
4. cantilever torsional rotation â€” `TL/GJ`;
5. support reaction equilibrium;
6. rigid-body mechanism/singularity detection;
7. model validation error detection.

## Verification policy

FEM3D should distinguish three different claims:

**Verification** â€” the implementation reproduces a known mathematical formulation.

**Validation** â€” the chosen formulation represents the intended physical behaviour with acceptable engineering accuracy.

**Production readiness** â€” the implementation has adequate numerical robustness, performance, documentation, regression coverage and failure diagnostics for its intended engineering use.

Passing the current tests is only a verification milestone. It is **not** a claim that FEM3D is yet a production FEA solver.

In particular, the current triangular element is an extension boundary only and provides no structural stiffness. It must not be used as a plate-bending element. Proper shell/plate formulations will be introduced only with analytical benchmarks, patch tests and convergence studies.

## Planned next engineering increments

1. First-class analysis cases and persistent audit records.
2. Prescribed non-zero displacements and complete reaction recovery.
3. Beam force/moment result recovery in local coordinates.
4. Symmetry, positive-definiteness and energy consistency checks.
5. Sparse/profile matrix storage with the dense solver retained as a reference path.
6. Dense-versus-sparse regression comparisons.
7. Expanded analytical frame benchmarks and mesh/refinement studies.
8. Proper second-order shell elements (Quad8/Tri6) with documented formulation and validation evidence.
9. Only after profiling: optimised Pascal kernels and narrowly targeted ASM/SIMD paths with reference-kernel regression tests.

## Build status

The project is structured as a Lazarus/FreePascal application and native Pascal test project. The execution environment used to prepare this archive does **not** contain Lazarus/FreePascal, so compilation could not be performed here. The source has been reviewed statically, but the archive should be compiled with the target FPC/Lazarus version before relying on it.


## v0.6 trust-oriented analysis increment

Analysis results now retain a structured `AuditTrail` object in addition to the human-readable message. The audit records model size, validation status, assembly diagnostics, constraints, solver identity, residuals, reactions and energy balance. This is intended to become a persistent analysis provenance record in the eventual project/results database.

## v0.7 solver architecture
The numerical solver boundary is now deliberately process-oriented. `FEM3D.exe` is the modelling/result GUI; `FEM3D_LinStatic.exe` is an independent Windows x64 solver executable consuming a prepared FEM3D ASCII model/analysis file. This permits command-line and batch execution and keeps numerical solver failures isolated from the modelling GUI.

The model file persists analysis cases and solver configuration. The solver produces a separate `.fem3dres` ASCII result file containing solver metadata, deterministic model/analysis fingerprints, displacements, reactions and the audit trail. The fingerprints are deterministic 64-bit FNV-1a identifiers and are **not cryptographic hashes**.

Solver-specific GUI controls are intentionally treated as a future plugin boundary. A solver UI DLL may own configuration presentation/validation, while the numerical solver remains an EXE with a stable ASCII contract.

Current limitation: only Linear Static using the dense reference LDL^T solver is executable. Skyline storage, sparse production solvers and the other analysis types remain defined architectural targets, not implemented capabilities.

## Primary analysis workflow

The primary FEM3D analysis family is now centred on three engineering workflows:

1. **Linear Static** â€” implemented through the external reference solver `FEM3D_LinStatic.exe`.
2. **Linear Buckling** â€” persistent settings and external solver boundary are implemented, but numerical solving is gated pending verification of geometric stiffness and eigenvalue extraction.
3. **Nonlinear Static** â€” persistent load-step/convergence settings and external solver boundary are implemented, but numerical solving is gated pending verification of nonlinear element tangents and convergence behaviour.

The modelling GUI prepares the analysis definition and launches a separate solver process. This keeps the numerical solver independent from the GUI and makes batch/CLI operation a first-class workflow.

### Linear Static result inspection

The current development line now treats Linear Static as the primary end-to-end reference workflow. The GUI can display exaggerated deformed geometry, generic node/element result contours, reactions, beam axial stress, result legends, selected-entity result values, and simple user-defined result expressions. The expression evaluator is intentionally small and deterministic at this stage; it is a foundation for later engineering/fatigue equations rather than a general scripting engine.

Model validation is also becoming an interactive engineering diagnostic rather than only a pass/fail gate, including element aspect-ratio and beam slenderness checks.

### v0.9 result inspection direction
Linear Static is currently the primary numerical reference workflow. Result fields are deliberately generic: direct solver quantities, recovered beam forces and deterministic user expressions feed the same inspection/contour path. The expression evaluator supports arithmetic, comparisons, SQRT/ABS/MIN/MAX and IF(), allowing simple derived engineering quantities without embedding arbitrary scripting in model files.

### v0.10 engineering inspection

The Linear Static result viewer now provides node/element result tables, field statistics, and richer deterministic derived-result expressions. Validation findings retain optional entity references so geometry-quality diagnostics can be connected directly to viewport selection in a subsequent UI pass.

## v0.11 graphics

FEM3D now has an OpenGL-based engineering viewport foundation. The LCL provides `TOpenGLControl` through the `lazopenglcontext` package; on Windows the control uses WGL. The renderer is intentionally kept in `FEMOpenGLView.pas` rather than coupling OpenGL calls into the model/result classes.

The initial renderer provides depth-buffered 3D linework, deformed/undeformed overlays, contour colours, selection highlighting, axes, grid, and an interactive X/Y/Z clipping plane. The existing `TFEMViewport` remains responsible for camera/picking semantics and is also a useful fallback/reference renderer.

## Solver validation boundary

The numerical solver executables are intentionally isolated from the modelling and graphics source tree. The solver projects consume snapshots under `solver/core`, while result files retain solver/kernel provenance. This means graphics and viewer development can proceed without silently changing an already validated numerical kernel.

### v0.33 viewport graphics

The OpenGL viewport now has independently switchable engineering symbol layers for loads, restraints, element local axes and coordinate-system triads. These are presentation-only and remain outside the numerical solver boundary.


## v0.22 — 3D member body rendering

The engineering viewport can now display `BEAM3D` members as faceted 3D bodies rather than centre-lines. The body is intentionally an **area-equivalent display proxy**, not a claim about the physical section shape. This keeps the existing transparent section data and solver formulation unchanged while making perspective inspection substantially more useful.

Use the **Solid members** viewport toggle to switch between body and centre-line display. Element edge visibility remains separately controlled.


## v0.23 engineering viewport feedback

The viewport now maintains a separate hover/preselection state from persistent selection. Hover uses the camera-aware screen-ray picking path and is presentation-only; it does not modify the model or solver state.


## v0.24 modelling foundation
The GUI now has an explicit model-editing layer with node/beam creation, node movement, deletion, beam splitting, and snapshot-based undo/redo. See `docs/MODEL_EDITING.md`.


## v0.25 interactive modelling

The viewport now supports a first direct-construction workflow. **Add node** places nodes by intersecting the camera ray with an XY/XZ/YZ construction plane, with optional grid snapping. **Add beam** creates or reuses two nodes and creates BEAM3D members in sequence, making simple frame/line construction much faster than dialog-only editing. All changes continue through the model editor command layer and remain undoable. See `docs/INTERACTIVE_MODELLING.md`.

## Interactive modelling

The current modeller supports viewport-driven node and beam creation, construction-plane/grid snapping, beam chaining, beam splitting, conservative snapshot undo/redo, and viewport-driven node movement with a non-destructive drag preview. Model edits remain separated from the numerical solver layer.


### Interactive modelling — v0.27

The modeller now provides rubber-band feedback while creating chained BEAM3D geometry, construction-plane-aware grid snapping, and equal-length beam subdivision through the model-editing command layer. Model mutations remain undoable and invalidate stale results.


### v0.28 modelling assignment

Interactive BEAM3D creation exposes material, section and group assignment directly in the model-editing panel, while the selection inspector now remains useful before any analysis results exist.


### v0.29 beam meshing

Straight two-node BEAM3D members can now be subdivided automatically from a requested maximum element length. The mesher remains separate from the FEM solver and delegates all topology mutation to the undoable model-editing layer.

### v0.31 modelling increment
The modeller now supports batch engineering-property assignment to the current element selection. Material, beam section and group references can be assigned to multiple selected elements as one undoable operation. This establishes the pattern needed for later multi-element transformations and property editing without coupling those operations to the solver.

### v0.34 CAD wireframe import

FEM3D now has a more deliberate CAD-wireframe import path for structural stick models. DXF LINE/POINT/LWPOLYLINE geometry can be promoted to BEAM3D elements, and IGES Type 110 wireframe lines can be imported. Imported geometry receives placeholder engineering properties that must be reviewed before analysis. Persistent IGES surface geometry is intentionally reserved for the forthcoming CAD geometry/surface-meshing layer.
