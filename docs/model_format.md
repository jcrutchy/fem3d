# FEM Suite — Model Schema (v0)

This document covers what each field *means* — solver-agnostic, and
format-agnostic (the same fields and semantics apply whether the model
is written in the native `.fem` format or converted from JSON via
`adapt_json`). For the actual wire syntax, see `docs/native_format.md`.
`fem_validate` is shared by every solver, and each solver only looks at
the sections/element types it understands.

A model has: nodes, materials, properties, elements, one or more freedom
cases (named constraint sets), one or more load cases (named load sets),
optional combinations (named linear combinations of load case results),
and solver params. See `docs/native_format.md` for a complete worked
example in the actual file syntax.

## Fields

- **nodes** — `id` (unique integer), `x`/`y`/`z` coordinates. A node's dof
  count depends on what's connected to it: 3 (translations `x`,`y`,`z`)
  by default, or 6 (adding rotations `rx`,`ry`,`rz`) if it's touched by
  any beam element. A constraint or load referencing a rotational dof on
  a node with no beam connection is a validation error, not a silent
  no-op.
- **materials** — `id`, `E` (Young's modulus, > 0). `nu` (Poisson's
  ratio, required only if the material is used by a beam property --
  it's how the shear modulus `G = E / (2(1+nu))` for torsion is derived;
  omit it for truss-only materials). `rho` (density, > 0 if given) --
  optional here; only required by solvers that need mass (currently
  `modal`, see `docs/modal.md`), checked by that solver itself rather
  than by the shared validator (see "Validation" below for why).
- **properties** — a named combination of element type + material +
  section data, referenced by elements. `type` must match a supported
  element type.
  - `"truss"`: `material`, `area` (> 0).
  - `"beam"`: `material` (whose `nu` must be set), `area` (> 0), `Iy`,
    `Iz` (second moments of area about the local y/z axes, > 0), `J`
    (torsion constant, > 0).
  - `"shellq4"`: `material` (whose `nu` must be set), `thickness` (> 0).
- **elements** — `id`, `type`, `nodes` (ordered list, length depends on
  type), `property`. `"truss"` and `"beam"` take exactly 2 node ids;
  `"shellq4"` takes exactly 4, ordered counterclockwise around the
  element as seen from its positive-normal side, and must be flat (all
  4 nodes coplanar, within 1% of the element's characteristic edge
  length -- checked by the validator, not left to degrade silently).
  - `"truss"` models a 2-node, 3D pin-jointed axial bar (no bending
    stiffness).
  - `"beam"` models a 2-node 3D Euler-Bernoulli frame element (axial +
    bending about both local axes + torsion; no shear deformation).
    `Iz` resists bending that deflects the beam locally in y (rotation
    about local z); `Iy` resists bending that deflects it locally in z
    (rotation about local y). A beam also needs its "roll" about its own
    axis fixed, since a circular-ish cross-section orientation isn't
    implied by its two end nodes alone: give an optional `refVec`
    (`[x,y,z]`, any vector not parallel to the beam axis -- its own
    length doesn't matter) to set it explicitly, or omit it to use the
    default heuristic (global Z, falling back to global X for
    near-vertical members -- the same convention most frame-analysis
    tools default to).
  - `"shellq4"` models a 4-node flat-shell element: membrane (in-plane,
    bilinear) + DKQ (Discrete Kirchhoff Quad) thin-plate bending,
    combined locally into 6 dof/node (`x,y,z,rx,ry,rz` -- the same
    convention `"beam"` uses, so the two connect consistently at a
    shared node). In-plane corner rotation (`rz`, "drilling") has no
    real stiffness from either the membrane or bending formulation, so
    a small artificial penalty regularizes it -- a documented
    simplification (see `QuadShellStiffnessLocal` in
    `fem_elements.pas`), not a from-first-principles drilling
    formulation. Not yet supported by `modal` (no mass matrix
    implemented for it -- rejected by name rather than silently
    mishandled, see `docs/modal.md`).
- **constraints** — `node`, `dof` (`"x"`,`"y"`,`"z"`,`"rx"`,`"ry"`,`"rz"`),
  `value` (prescribed displacement/rotation; `0.0` = fixed). Non-zero
  values are supported — `linstatic` folds them into the load vector
  rather than requiring a separate "settlement" load case.
- **loads** — `node`, `dof`, `value` (applied force, or moment for a
  rotational dof).
- **solverParams.tolerance** — currently unused by `linstatic` (reserved
  for iterative solvers); the skyline solve is direct/exact.

## Validation

Every solver runs the model through `fem_validate` before touching a
matrix. It checks, among other things:
- duplicate node/material/property/element ids
- dangling references (element → node/property, property → material,
  constraint/load → node)
- unsupported element types, wrong node count for an element's type
- **an element's type matches its property's type** (e.g. a `beam`
  element pointing at a `shellq4` property is rejected outright, rather
  than silently reading that property's never-validated, likely-zero
  `Area`/`Iy`/`Iz`/`J`)
- non-positive `E`, `area`, `Iy`, `Iz`, `J`, `thickness`; `nu` out of the
  physically valid range; a beam or shellq4 material missing `nu`
- **every coordinate, material/section property, and freedom-case/
  load-case value is finite** (not NaN, not ±Infinity) -- this is
  separate from the parser's own strictness (below) because a value
  like the literal text `nan` parses successfully as a NaN double; only
  an explicit finite-value check catches it
- a beam's `refVec` (or the default heuristic, if none given) being
  (near-)parallel to its own axis -- degenerate, can't fix its roll
- a shellq4's 4 nodes are coplanar (within 1% of its characteristic edge
  length) -- the DKQ/membrane formulation assumes a flat element
- a constraint/load referencing a rotational dof at a node with no
  rotational dof (i.e. not connected to any beam or shellq4)
- **no duplicate `(node, dof)` constraint within one freedom case** --
  two constraints on the same dof (even identical ones) is rejected
  rather than letting the later one silently win
- at least one constraint present (an unconstrained model is caught here
  before assembly, as a fast, specific error rather than a generic
  singular-matrix failure from the solver)
- `SolverParams.Tolerance` is finite, positive, and within a plausible
  range (roughly 1e-15 to 1.0 -- outside that is almost certainly a typo)

Separately, the **native `.fem` parser itself** (`fem_native_model.pas`)
is strict about syntax: a numeric field that isn't empty/`-` but fails
to parse at all (a stray letter, a typo) is a load-time error naming the
line, section, and field -- never silently coerced to `0`, the way it
used to work. This is a distinct layer from the semantic checks above:
the parser answers "did I read a number", `fem_validate` answers "is
that number physically usable".

Validation errors are printed to stderr, one per line, and the process
exits with code 3 (a parse-syntax error from the loader itself exits
with code 2 instead). See "Exit codes" below.

**What belongs in `fem_validate` vs. a solver itself.** The shared
validator only checks things that are true or false about the *model*,
independent of which solver runs it -- a beam needing `nu` is a fact
about beam elements, not about `linstatic` specifically. Something a
model only needs for a *particular kind of analysis* (mass, for a modal
solve) is that solver's own job to check, after the shared validation
passes. This keeps the shared unit from accumulating solver-specific
special cases while every solver still gets a consistent, named error
(and the same exit-code convention) for its own extra requirements.

## Exit codes (all solvers should follow this convention)

| Code | Meaning                                   |
|------|--------------------------------------------|
| 0    | Success                                     |
| 1    | Usage error (bad/missing CLI args)          |
| 2    | Could not load the model file (I/O, malformed input)  |
| 3    | Model failed validation                     |
| 4    | Solver-level failure (e.g. singular system) |

## Load cases, freedom cases, and combinations

A model can define more than one **load case** (a named set of loads) and
more than one **freedom case** (a named set of constraints -- Strand7's
term, since the same structure is sometimes analyzed under different
support conditions). Every solver solves *every load case against every
freedom case that applies*, and -- for `linstatic` -- evaluates any
**combinations** (named linear combinations of load case results) too, all
in one invocation. See `docs/native_format.md` for the actual
`[FREEDOMCASE ...]` / `[LOADCASE ...]` / `[COMBINATION ...]` syntax.

**Backward compatible by construction.** A model using a single unnamed
freedom case and load case (no repeated `[FREEDOMCASE ...]`/
`[LOADCASE ...]` sections) is normalized by the loader into one freedom
case and one load case, both named `"default"` -- every model from
before this feature existed still works unchanged, and (see "Output"
below) still produces byte-identical output.

- **A freedom case** -- id (the section's argument) must be unique;
  its constraints are the same shape as a single flat constraint set.
  Each freedom case is validated independently (needs at least one
  constraint, etc.) -- see "Validation" above.
- **A load case** -- likewise, id unique, loads same shape as a flat
  load set.
- **A combination** -- `FreedomCase` is the id of the freedom case this
  combination is evaluated within (required if the model has more than
  one freedom case; resolved to the model's sole freedom case
  automatically if there's only one). `Terms` is a list of
  `<loadCaseId>:<factor>` pairs; the combination's result is the
  weighted sum of those load cases' results, evaluated at every
  displacement and reaction component -- valid because linear-static
  analysis is linear (pure superposition), so this is exact
  post-processing arithmetic, not a new solve.

**Performance note, not just a formality.** Stiffness assembly and
factorization depend only on a freedom case's constraints, not on any
load case, so `linstatic` builds and factorizes the skyline matrix
**once per freedom case** and reuses it for every load case's solve
(forward/back substitution only -- cheap). Combinations cost nothing
further: they're computed from already-solved load case results.

## Output

`linstatic` writes results to stdout as a plain, greppable key=value
stream -- one measurement per line, full double precision, `.` decimal
separator regardless of locale:

```
# FreePascal FEM Suite - linstatic (skyline linear-static solver)
# model=model.fem
# nodes=2 elements=1 freedom_cases=1 load_cases=1 combinations=0
DISP.1.x=0.0000000000000000E+000
DISP.1.y=0.0000000000000000E+000
DISP.1.z=0.0000000000000000E+000
DISP.2.x=9.5238095238095231E-006
...
REACT.1.x=-9.9999999999999989E+002
...
```

Lines starting with `#` are informational comments; everything else is
`DISP.<nodeId>.<dof>=<value>` or `REACT.<nodeId>.<dof>=<value>` (reactions
are only emitted for constrained dofs). This is the stable contract other
tools parse against -- `fem_regress` (see `docs/regression_testing.md`),
and any future pretty-printer or plotting tool. Redirect as usual:

```
linstatic model.fem > results.txt
```

Or name a results file directly in the model itself
(`[SOLVERPARAMS].ResultsFile=...`, see `docs/native_format.md`) rather
than relying on shell redirection.

The model argument can also be `-`, reading the model from stdin instead
of a file -- this is what lets an adaptor (see `docs/adaptors.md`) feed a
solver directly: `adapt_json old.json | linstatic -`.

Set `FEM_DEBUG=1` in the environment to also dump the DOF numbering map,
the dense free-free stiffness matrix, and the assembled RHS to stderr —
useful when a model isn't behaving as expected.

### Output with multiple cases

The key format above is what you get from a model with exactly one
freedom case, one load case, and no combinations (i.e. legacy-equivalent)
-- unprefixed, byte-identical to this solver's output before load/freedom
cases existed. With more than that:
- **More than one freedom case**: `<freedomCaseId>.<caseId>.DISP...`
- **Exactly one freedom case but more than one load case/combination**:
  `<caseId>.DISP...` (no freedom-case segment, since there's nothing to
  disambiguate).

`<caseId>` is a load case's or combination's own `id`. `modal` follows
the same freedom-case prefixing rule (it has no load cases, so only the
freedom-case segment ever applies): `<freedomCaseId>.MODE.<n>...` when
there's more than one freedom case, bare `MODE.<n>...` otherwise.

## Planned extensions

- Plate/shell elements: 1st-order (flat, linear) `shellq4` is built and
  wired (membrane + DKQ bending, 6 dof/node, artificial drilling-dof
  penalty -- see the `"shellq4"` property/element entries above).
  2nd-order (curved-edge) variant not started.
- Adaptors for other ASCII input formats (Strand7 `.txt`, etc.) — see
  `docs/adaptors.md`. `adapt_json` (JSON -> native) exists; a
  Strand7-format adaptor is low priority for now, not started.
- Additional solvers as separate executables against the same model
  format and the same `fem_skyline`/`fem_validate` units: nonlinear
  static, etc.
