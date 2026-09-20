# FEM Suite — Model File Format (v0)

The model file is JSON. It is solver-agnostic: `fem_validate` is shared by
every solver, and each solver only looks at the sections/element types it
understands.

```json
{
  "solver": "linstatic",
  "units": "free-form label, e.g. SI (N, m, Pa) -- informational only for now",
  "nodes": [
    { "id": 1, "x": 0.0, "y": 0.0, "z": 0.0 }
  ],
  "materials": [
    { "id": 1, "E": 210.0e9 }
  ],
  "properties": [
    { "id": 1, "type": "truss", "material": 1, "area": 0.001 }
  ],
  "elements": [
    { "id": 1, "type": "truss", "nodes": [1, 2], "property": 1 }
  ],
  "constraints": [
    { "node": 1, "dof": "x", "value": 0.0 }
  ],
  "loads": [
    { "node": 2, "dof": "x", "value": 1000.0 }
  ],
  "solverParams": {
    "tolerance": 1e-9
  }
}
```

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
- **elements** — `id`, `type`, `nodes` (ordered list, length depends on
  type), `property`. Both `"truss"` and `"beam"` take exactly 2 node
  ids.
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
- non-positive `E`, `area`, `Iy`, `Iz`, `J`; `nu` out of the physically
  valid range; a beam material missing `nu`
- a beam's `refVec` (or the default heuristic, if none given) being
  (near-)parallel to its own axis -- degenerate, can't fix its roll
- a constraint/load referencing a rotational dof at a node with no
  rotational dof (i.e. not connected to any beam)
- at least one constraint present (an unconstrained model is caught here
  before assembly, as a fast, specific error rather than a generic
  singular-matrix failure from the solver)

Validation errors are printed to stderr, one per line, and the process
exits with code 3. See "Exit codes" below.

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
| 2    | Could not load the model file (I/O, bad JSON) |
| 3    | Model failed validation                     |
| 4    | Solver-level failure (e.g. singular system) |

## Load cases, freedom cases, and combinations

A model can define more than one **load case** (a named set of loads) and
more than one **freedom case** (a named set of constraints -- Strand7's
term, since the same structure is sometimes analyzed under different
support conditions). Every solver solves *every load case against every
freedom case that applies*, and -- for `linstatic` -- evaluates any
**combinations** (named linear combinations of load case results) too, all
in one invocation.

```json
{
  "freedomCases": [
    { "id": "FC1", "name": "Service supports", "constraints": [ ... ] }
  ],
  "loadCases": [
    { "id": "DL", "name": "Dead load", "loads": [ ... ] },
    { "id": "LL", "name": "Live load", "loads": [ ... ] }
  ],
  "combinations": [
    {
      "id": "COMB1", "name": "1.2DL + 1.6LL", "freedomCase": "FC1",
      "terms": [
        { "loadCase": "DL", "factor": 1.2 },
        { "loadCase": "LL", "factor": 1.6 }
      ]
    }
  ]
}
```

**Backward compatible by construction.** A model using the original flat
`"constraints"` / `"loads"` arrays (no `"freedomCases"`/`"loadCases"` keys)
is normalized by the loader into a single freedom case and a single load
case, both named `"default"` -- every model from before this feature
existed still works unchanged, and (see "Output" below) still produces
byte-identical output.

- **freedomCases[].id / name / constraints** -- `id` must be unique;
  `constraints` is the same array you'd put in the flat `"constraints"`
  form. Each freedom case is validated independently (needs at least one
  constraint, etc.) -- see `docs/model_format.md`'s Validation section.
- **loadCases[].id / name / loads** -- likewise, `id` unique, `loads` same
  shape as the flat `"loads"` form.
- **combinations[].id / name / freedomCase / terms** -- `freedomCase` is
  the id of the freedom case this combination is evaluated within
  (required if the model has more than one freedom case; resolved to the
  model's sole freedom case automatically if there's only one). `terms`
  is a list of `{ "loadCase": <id>, "factor": <number> }`; the
  combination's result is the weighted sum of those load cases' results,
  evaluated at every displacement and reaction component -- valid because
  linear-static analysis is linear (pure superposition), so this is exact
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
# model=model.json
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
linstatic model.json > results.txt
```

The model argument can also be `-`, reading the model from stdin instead
of a file -- this is what lets an adaptor (see `docs/adaptors.md`) feed a
solver directly: `adapt_strand7 in.txt | linstatic -`.

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

- Plate/shell elements, including a 2nd-order (curved-edge) variant --
  substantial scope (shape functions, Gauss quadrature, a Jacobian-mapped
  B-matrix, membrane/bending coupling, drilling-dof stabilization); to be
  built and verified incrementally like beam was (truss -> beam), not in
  one pass. Not started.
- A compact native format (input model, and solver results), closer to
  Strand7's `.txt` layout -- sectioned, tabular rows rather than
  once-per-record JSON objects, since JSON gets prohibitively verbose at
  the node/element counts a real model reaches. JSON becomes an adaptor
  input rather than the primary format once this lands; solver results
  gain the same treatment, plus letting the model file itself name a
  results file per solver-params section rather than solvers only ever
  writing to stdout. Not started -- a real pivot, planned as its own
  dedicated increment rather than folded into another change.
- Adaptors for other ASCII input formats (Strand7 `.txt`, etc.) — see
  `docs/adaptors.md`. Solvers themselves stay on the canonical native
  format; adaptors convert into it upstream. Low priority for now.
- Additional solvers as separate executables against the same model
  format and the same `fem_skyline`/`fem_validate` units: nonlinear
  static, etc.
