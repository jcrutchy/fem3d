# FEM3D Validation Trail

This file is intentionally kept with the source tree. The purpose is to make numerical confidence auditable rather than relying on visual inspection of results.

## v0.5 review record

### 1. Beam formulation dimensional check

During review of the 3D beam stiffness matrix, the bending coefficients were found to use the wrong powers of element length:

- incorrect: `12 E I / L^2`
- correct: `12 E I / L^3`
- incorrect: `6 E I / L`
- correct: `6 E I / L^2`

The implementation was corrected before this version was packaged.

This defect demonstrates why analytical regression tests are mandatory: the code could assemble and solve a constrained model while still producing physically incorrect bending stiffness.

### 2. Analytical cantilever benchmarks

For the standard cantilever used by the verification suite:

- `E = 200 GPa`
- `A = 0.01 m^2`
- `Iy = 8e-6 m^4`
- `Iz = 3e-6 m^4`
- `J = 1e-6 m^4`
- `L = 5 m`
- point load/moment magnitude = `10 kN` / `10 kNm`

Expected reference quantities are:

| Case | Reference expression | Expected |
|---|---|---:|
| Axial | `PL/(EA)` | `2.5e-5 m` |
| Y bending | `PL^3/(3 E Iz)` | `-0.694444444444444 m` |
| Z bending | `PL^3/(3 E Iy)` | `-0.260416666666667 m` |
| Torsion | `TL/(GJ)` | `0.65 rad` |
| Z support reaction | `-Fz` | `+10000 N` |

These are mathematical reference values, not empirical validation claims.

### 3. Numerical consistency checks

The verification suite includes:

- stiffness symmetry;
- positive strain-energy quadratic form;
- free-equation residual calculation;
- support reaction recovery from the original, unconstrained equations;
- rigid-body mechanism rejection;
- model-reference and geometry validation.

### 4. Current verification status

The source archive was prepared in an environment without Lazarus/FreePascal, so the native test executable could not be built or run here.

Therefore the status of the Pascal regression suite in this archive is:

**DEFINED — NOT EXECUTED IN THIS ENVIRONMENT**

The first build on the target Lazarus/FPC environment should run `tests/verify.lpr` and preserve the console output as the first executable validation record for this revision.

## Future evidence requirements

Before an element or solver is considered engineering-ready, the project should accumulate evidence for:

1. analytical solutions;
2. patch tests where applicable;
3. rigid-body and mechanism behaviour;
4. symmetry and energy checks;
5. mesh/refinement convergence;
6. comparison against an independent implementation or trusted reference where practical;
7. reaction/global-equilibrium checks;
8. sensitivity to tolerances and conditioning;
9. regression results retained between revisions.

Shell/plate bending will additionally require second-order element benchmarks and convergence evidence. A triangular constant-strain membrane is not considered a substitute for a bending-capable shell element.


## v0.6 validation additions

### Energy balance
For a linear static system, the converged solution should satisfy `U^T K U = U^T F`, hence strain energy `1/2 U^T K U` equals half the external work. FEM3D now records both quantities and a relative energy-balance error. This is an independent check from the solver residual.

### Beam force recovery
The BEAM3D implementation now exposes recovered local end forces from the solved global displacement vector. A cantilever benchmark checks that the recovered end shear is consistent with the applied tip load. This establishes the beginning of the result-recovery layer: reported engineering quantities must be recoverable from the same solved state and independently testable.

### Trust rule
A successful matrix factorisation is not sufficient to declare an analysis trustworthy. FEM3D should accumulate independent evidence: model validation, solver residual, reaction equilibrium, energy balance, element result recovery, and benchmark agreement. Future result objects will retain these checks as structured data rather than only formatted text.


### Structured provenance
Analysis results retain the audit records as data. The formatted message is a presentation of that record, not its only storage. A verification case confirms that the records survive the solver call and contain multiple independent analysis stages.

### Result-sign convention check
The beam end-force verification uses the element internal force vector `K_e u_e`: for a downward tip load, the tip-end force component balances the applied load and the fixed-end component gives the corresponding support-side internal force. The verification therefore checks both ends, not merely the global reaction.

## v0.7 solver-process verification status
- Architecture reviewed statically: GUI → prepared FEM3D ASCII input → independent `FEM3D_LinStatic.exe` → `.fem3dres` ASCII output.
- CLI contract and exit codes are documented in `docs/SOLVER_INTERFACE.md`.
- Persistence and provenance code paths are present in `FEMAnalysisCases`, `FEMIO`, `FEMHash`, and `FEMAnalysis`.
- Native Pascal compilation/execution is **DEFINED — NOT EXECUTED IN THIS ENVIRONMENT** because Lazarus/FreePascal is not installed here.
- No claim is made that the new Windows executable has been compiler-verified yet.

## v0.7.1 additions

- Analysis cases now persist solver-specific settings for Linear Static, Linear Buckling and Nonlinear Static.
- Native save/load verification covers analysis type, load case, matrix storage, tolerances, eigenvalue controls and nonlinear load-step controls.
- Model fingerprint coverage was expanded to include nodal restraints and nodal load values so important boundary/loading changes alter provenance.
- Linear Buckling and Nonlinear Static remain explicitly gated. Their UI and process boundaries are present, but no numerical results are claimed until geometric stiffness, eigenvalue extraction, nonlinear residual/tangent consistency and convergence behaviour have dedicated verification suites.

## v0.8 result-view validation targets

Before treating the result renderer as production capability, verify at minimum:

- deformed-shape coordinates reproduce known analytical displacements;
- automatic deformation scaling does not alter numerical result values;
- contour min/max values match the underlying result field exactly;
- manual contour ranges only alter visual mapping, not stored values;
- node/element probing reports the same values as the result field;
- model/result fingerprint mismatch is reported before interpreting stale results;
- result expressions reproduce independently calculated derived quantities;
- beam axial stress agrees with the recovered axial end force divided by section area;
- validation warnings identify the intended model entities and can be acted on by selection/highlighting.

## v0.10 inspection additions

Validation findings now carry an optional entity reference (`Node` or `Element` plus ID), so the UI can later make warnings directly selectable in the viewport. Additional geometry checks include coincident nodes, small polygon angles, and quadrilateral face warpage. These checks are diagnostics only and do not silently modify the model.
