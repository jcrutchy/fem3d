# Native model format (`.fem`)

The format every solver actually reads. Sectioned and tabular, in the
spirit of Strand7's `.txt` model export — not JSON's once-per-record
object structure, which gets prohibitively verbose at real model scale
(thousands of elements, hundreds of thousands of nodes: repeating
`"id"`, `"x"`, `"y"`, `"z"` as literal text on every single node line
adds up fast). This file covers the wire syntax; see
`docs/model_format.md` for what each field *means* (that doc is
format-agnostic — same fields, same semantics, either format).

## Shape

```
# comments start with # or ; and may appear anywhere
[HEADER]
Solver=linstatic
Units=SI (N, m, Pa, rad)

[NODES]
# id, x, y, z
1, 0, 0, 0
2, 2, 0, 0

[MATERIALS]
# id, E, nu, rho    ('-' = not specified)
1, 210e9, -, -

[PROPERTIES]
# id, type, material, area[, Iy, Iz, J[, Cy, Cz, Rt]]    (Iy/Iz/J only for beam; Cy/Cz/Rt optional, for stresses)
# id, type, material, thickness             (shellq4, shellq8)
1, truss, 1, 0.001

[ELEMENTS]
# id, type, node1, node2, property[, refX, refY, refZ]    (refVec optional, beam only)
# id, type, node1, node2, node3, node4, property           (shellq4: 4 corners around the perimeter, either direction; flat, convex)
# id, type, node1..node8, property                         (shellq8: 4 corners, then midsides 5=1-2, 6=2-3, 7=3-4, 8=4-1 at exact edge midpoints)
1, truss, 1, 2, 1

[FREEDOMCASE default]
# node, dof, value
1, x, 0
1, y, 0
1, z, 0
2, y, 0
2, z, 0

[LOADCASE default]
# node, dof, value
2, x, 1000

[COMBINATION COMB1]
FreedomCase=default
Terms=DL:1.2,LL:1.6

[SOLVERPARAMS]
Tolerance=1e-9
ResultsFile=results.txt
```

## Syntax rules

- **Sections**: `[NAME]` for a singleton section (`HEADER`, `NODES`,
  `MATERIALS`, `PROPERTIES`, `ELEMENTS`, `SOLVERPARAMS`); `[NAME arg]`
  (name, one space, an id) for a repeatable named section
  (`FREEDOMCASE`, `LOADCASE`, `COMBINATION`) — one such section per
  freedom case / load case / combination, `arg` becomes that case's `id`.
  Section names are case-insensitive.
- **Data rows**: comma-separated fields, whitespace around each field
  trimmed, under whichever section header precedes them. `NODES`,
  `MATERIALS`, `PROPERTIES`, `ELEMENTS`, and the body of each
  `FREEDOMCASE`/`LOADCASE` section are all tabular this way — one record
  per line, no repeated key names.
- **`-` sentinel**: for an optional field (`MATERIALS`' `nu`/`rho`),
  `-` or an empty field means "not specified" — distinct from `0`, which
  is a real, valid value for either. This preserves the same
  present-vs-zero distinction the JSON format's field presence gave you.
- **Variable field count by type**: `PROPERTIES` and `ELEMENTS` rows have
  more fields for a `beam` than a `truss` (section properties, an
  optional orientation vector), and a `shellq4`/`shellq8` row has its own
  shape again (`thickness` instead of `area`/`Iy`/`Iz`/`J`; 4 or 8 node
  ids instead of 2, no orientation vector — a flat shell's orientation
  comes from its node order, not a separate refVec) — the parser reads the `type`
  field to know how many to expect, same as the loader has always
  worked.
- **`key=value` lines**: `HEADER`, `SOLVERPARAMS`, and a `COMBINATION`
  section's `FreedomCase=`/`Terms=` lines use simple `key=value`, not
  tabular rows (`COMBINATION`'s `Terms=DL:1.2,LL:1.6` packs a load-case-id
  list into one line rather than one row per term, since a combination's
  term list is usually short).
- **Numbers**: plain decimal or scientific notation (`210e9`, `2.1E+11`),
  `.` decimal point always (locale-independent, like everything else in
  this suite). A numeric field that isn't empty/`-` but fails to parse
  (`abc`, a stray letter, a typo) is a hard load-time error naming the
  line, section, and field — never silently treated as `0`. Note that
  this only catches text that fails to parse as a number at all: the
  literal text `nan` or `inf` parses successfully as a NaN/Infinity
  double (that's how the underlying float parser works), so those are
  caught separately, by `fem_validate`'s explicit finite-value checks on
  the fields that matter (coordinates, material/section properties,
  freedom-case and load values), not by the parser.

## Where this fits

Every solver's CLI argument is a `.fem` file (or `-` for stdin) — solvers
never parse anything else, per the Unix-philosophy goal of keeping each
one small and format-agnostic beyond its one canonical input (see
`docs/adaptors.md`). JSON is no longer read directly by any solver;
`adapt_json` converts an existing JSON model into this format:

```
adapt_json old_model.json > model.fem
linstatic model.fem
```

`fem_native_model.pas` (the parser) and `fem_native_writer.pas` (the
writer, used by `adapt_json`) share the exact same `LoadModelFromStream`
/ `LoadModelFromFile` / `LoadModelFromStdin` function signatures as the
JSON loader did — a solver switches between formats by changing one
line in its `uses` clause, nothing else.

## Solver parameters

`[SOLVERPARAMS]` is a plain `key=value` section; every key is optional.

| Key | Default | Meaning |
|---|---|---|
| `Tolerance` | `1e-9` | Convergence tolerance for `linsparse`'s PCG iteration; also scales the equilibrium self-check in verbose output. `linstatic` factorizes directly and `modal` uses a Jacobi eigensolver; neither reads this. |
| `PivotTolerance` | `1e-10` | `linstatic` only. A pivot smaller than `PivotTolerance` × (largest original diagonal) is reported as a singular system. Must be strictly between 0 and 1. Lower it only for a legitimately extreme model — e.g. a shell thinner than about 0.03 mm in SI metres, where the rotational-vs-translational stiffness ratio itself falls below the default. Don't go much below `1e-13`: a genuine mechanism produces pivots around `1e-16` relative, and lowering the threshold too far lets one through as a "solved" system. |
| `Verbose` | `1` | `1`/`true`/`yes` or `0`/`false`/`no`. See "Verbose output" below. |
| `BeamDivisions` | `4` | Whole number 1–200. Each beam is cut into this many equal segments for element-force output, giving `BeamDivisions + 1` stations (both ends included). Same idea as Strand7's beam divisions. `linstatic` and `linsparse` only. |
| `ElementResults` | `1` | `1`/`true`/`yes` or `0`/`false`/`no`. `0` skips element forces and stresses entirely (nodal results only). See "Element forces and stresses" below. |
| `ResultsFile` | *(stdout)* | See "Results file" below. |

## Verbose output

By default every solver prints explanatory narrative alongside its
results: what the solver is doing and why, a summary of the model, the
constraints and loads it actually applied, a human-readable results
table, and a self-check that the answer is physically consistent
(`linstatic`/`linsparse`: global force equilibrium; `modal`: mode
mass-orthonormality; `linsparse` also reports PCG iterations and
tolerance). Every narrative line starts with `#`, so the plain
`key=value` result lines are unchanged and still trivial to scrape
(`grep -v '^#'`; `fem_regress` already does this). Set `Verbose=0` to
get only the terse machine-readable output.

## Element forces and stresses

After each load case and combination, `linstatic` and `linsparse` recover
the forces inside every truss and beam from the solved displacements and
print them as `ELEM.<id>.…` lines (plus a readable table when
`Verbose=1`). Combinations are recovered from the *combined*
displacements, so stresses and von Mises/Tresca are computed from the
combined state, not by combining the individual cases' von Mises values.

| Element | Keys (all within the case's normal key prefix) |
|---|---|
| truss | `ELEM.<id>.N` (tension +), `.SIGMA`, `.VM`, `.TRESCA` |
| beam | `ELEM.<id>.S<k>.` then `POS` (distance from node 1); `N`, `VY`, `VZ`, `T`, `MY`, `MZ` (member-local axes); `GFX`, `GFY`, `GFZ`, `GMX`, `GMY`, `GMZ` (same resultants on global axes); `SIGAX`, `SIGMAX`, `SIGMIN`, `TAU`, `VM`, `TRESCA` — `k` runs `0` (node 1) to `BeamDivisions` (node 2) |

**Sign convention.** Beam resultants are the forces on the section's
*positive* face (the face looking toward node 2): `N` is tension-positive,
moments follow the right-hand rule, and the extreme-fibre stress at
section point (y, z) is `N/A − Mz·y/Iz + My·z/Iy`. A downward load on a
horizontal cantilever therefore gives `Mz < 0` at the support, with
tension on the upper (+y) fibre.

**Principal vs. geometric axes.** A beam section is entered as `Iy` and
`Iz` about its own local axes with no product of inertia, so those local
axes are both the geometric and the principal axes of the section; the
member-local values are the principal-axes values. The `G…` keys give
the same resultants on the global X/Y/Z axes.

**Stresses need section dimensions.** `A`, `Iy`, `Iz` and `J` alone do not
say how far the extreme fibres are from the centroid, so bending stress
needs two optional extra property fields:

- `Cy`, `Cz` — distance from the centroid to the extreme fibre along local
  y and local z (give both or neither). With them, `SIGMAX`/`SIGMIN` are the
  largest and smallest axial+bending stress over the four section corners
  (±Cy, ±Cz), and `VM`/`TRESCA` are the worst corner.
- `Rt` — outer-fibre radius for torsional shear, `TAU = T·Rt/J` (exact for
  a circular section, an estimate for others).

Without `Cy`/`Cz` the stresses are axial only (`N/A`); without `Rt` there
is no torsional shear. Von Mises is `√(σ² + 3τ²)` and Tresca `√(σ² + 4τ²)`.
Transverse (flexural) shear stress is not included — it depends on the
section shape, which is not described here.

## Results file

`[SOLVERPARAMS].ResultsFile=<path>` tells a solver to write its results
there instead of stdout (a short confirmation line is still printed to
stdout in that case). Omit it and results go to stdout as before,
redirectable in the usual way.
