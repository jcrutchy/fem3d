# Tutorial 2: A cantilever beam

Tutorial 1's bar could only stretch. A beam can also bend — which brings
in a second kind of stiffness, a second load case worth checking (a
transverse force instead of an axial one), and the first *rotational*
degree of freedom this series has dealt with. Same approach as before:
a problem simple enough to hand-calculate exactly, checked against what
the solver actually reports.

**You'll need:** Tutorial 1 first, if you haven't done it — this one
assumes you're comfortable reading a model file and the verbose output
without a line-by-line introduction to the format itself.

## The problem

```
                                y
                                ^
                                |
      steel beam, L = 3 m       |
      |==========================>|   x
     (1)                        (2)
    fixed                       free
    (all 6 dof = 0)                  P = 1000 N, downward (-y)
```

A steel beam, 3 m long, welded rigidly into a wall at node 1 (every
translation *and* rotation fixed there — a real cantilever support, not
just a pin) and free at node 2, loaded with 1000 N straight down.

## The theory

`fem_elements.BeamStiffness3D` is a 3D Euler-Bernoulli beam: axial
stiffness (the same `EA/L` as the truss), plus independent bending about
each local axis, plus torsion. This model only exercises bending about
one axis (local `z`, which resists deflection in the `x`-`y` plane — see
`docs/model_format.md` for the full local-axis convention), so that's
the only piece worth deriving by hand here.

For a cantilever — fixed at one end, a point load `P` at the free end,
length `L`, Young's modulus `E`, second moment of area `Iz` — classical
beam theory gives the tip deflection and tip rotation:

```
v      = P L^3 / (3 E Iz)     (deflection, at the tip, in the load direction)
theta  = P L^2 / (2 E Iz)     (rotation, at the tip, in radians)
```

and, since the wall has to carry the whole load in equilibrium, the
fixed-end reactions are just the applied load and the moment it creates
about the wall:

```
R_shear  = P
R_moment = P * L
```

For this model — `E = 200 GPa`, `Iz = 0.00008 m^4`, `L = 3 m`,
`P = 1000 N` (downward, so `-1000` in `y`):

```
v      = -1000 * 3^3 / (3 * 200e9 * 8e-5) = -5.625e-4 m
theta  = -1000 * 3^2 / (2 * 200e9 * 8e-5) = -2.8125e-4 rad
R_shear  = 1000 N        (upward, resisting the downward load)
R_moment = 1000 * 3 = 3000 N*m
```

`tests/regression/003_cantilever_beam_ybend/manifest.ini` carries this
same derivation.

## The model file

`tests/regression/003_cantilever_beam_ybend/model.fem`:

```
[NODES]
# id, x, y, z
1, 0, 0, 0
2, 3, 0, 0

[MATERIALS]
# id, E, nu, rho
1, 200000000000, 0.3, -

[PROPERTIES]
# id, type, material, area[, Iy, Iz, J]
1, beam, 1, 0.005, 0.00004, 0.00008, 0.00002

[ELEMENTS]
# id, type, node1, node2, property[, refX, refY, refZ]
1, beam, 1, 2, 1

[FREEDOMCASE default]
# node, dof, value
1, x, 0
1, y, 0
1, z, 0
1, rx, 0
1, ry, 0
1, rz, 0

[LOADCASE default]
# node, dof, value
2, y, -1000
```

What's different from Tutorial 1's truss:

- **`nu` is now required** — `0.3`, unlike the truss's `-`. A beam needs
  it to compute the shear modulus `G = E / (2(1+nu))` for its torsional
  stiffness, even though this particular load case never twists the
  beam. (Try deleting it — `fem_validate` catches it by name: "a beam
  material missing `nu`", not a bare crash somewhere downstream.)
- **`[PROPERTIES]` has three more numbers** — `Iy`, `Iz`, and `J`
  (`0.00004`, `0.00008`, `0.00002` m⁴) alongside `area`. A truss only
  needed cross-sectional area; a beam also needs to know how that area
  is *distributed* — the second moments of area about each local
  bending axis, plus the torsion constant. `Iz` (bending about local
  `z`, deflecting in the `x`-`y` plane) is the one this load case
  actually uses.
- **Every dof at node 1 is fixed, including the rotations** — `rx`,
  `ry`, `rz`, not just `x`, `y`, `z`. That's what makes this a
  *cantilever* rather than a pin: the wall doesn't let the beam's end
  rotate either, which is exactly what lets it develop the 3000 N·m
  fixed-end moment the hand calc predicts. A truss node has no
  rotational dof to fix in the first place — beams are the first
  element type in this series that has one.
- **The load is in `y`, not `x`** — transverse to the beam's axis this
  time, which is what puts the beam in bending rather than simple
  tension.

## Running it

```
./bin/linstatic tests/regression/003_cantilever_beam_ybend/model.fem
```

```
# FreePascal FEM Suite - linstatic (skyline linear-static solver)
# model=tests/regression/003_cantilever_beam_ybend/model.fem
# nodes=2 elements=1 freedom_cases=1 load_cases=1 combinations=0
#
# linstatic solves Ku=F for one or more static load cases: assembles the
# global stiffness matrix K from every element, applies each freedom
# case's constraints (removing restrained dof, folding any prescribed
# nonzero displacement into the right-hand side), and solves the resulting
# reduced system directly (skyline Cholesky/LDL, no iteration -- exact up
# to floating-point round-off, not an approximate/converged solution).
# 1 material(s), 1 propert(y/ies), solver tolerance 1E-9.
# Element types in this model: 0 truss, 1 beam, 0 shellq4, 0 shellq8.
# (Verbose=1 is the default -- every line above and below starting with
# '#' is explanatory narrative, not data; set Verbose=0 in this model's
# [SOLVERPARAMS] section for plain key=value output only.)
#
# Freedom case "default": 2 node(s), 12 degree(s) of freedom total, 6 constrained, 6 free -- the free ones are what this solve is for.
#   Constrained dof (node.dof = prescribed value; 0 = fully restrained):
#     node 1, x = 0
#     node 1, y = 0
#     node 1, z = 0
#     node 1, rx = 0
#     node 1, ry = 0
#     node 1, rz = 0
# Load case "default": 1 applied load(s):
#   node 2, y = -1000
DISP.1.x=0.0000000000000000E+000
DISP.1.y=0.0000000000000000E+000
DISP.1.z=0.0000000000000000E+000
DISP.1.rx=0.0000000000000000E+000
DISP.1.ry=0.0000000000000000E+000
DISP.1.rz=0.0000000000000000E+000
DISP.2.x=0.0000000000000000E+000
DISP.2.y=-5.6249999999999985E-004
DISP.2.z=0.0000000000000000E+000
DISP.2.rx=0.0000000000000000E+000
DISP.2.ry=0.0000000000000000E+000
DISP.2.rz=-2.8124999999999987E-004
REACT.1.x=0.0000000000000000E+000
REACT.1.y=1.0000000000000005E+003
REACT.1.z=0.0000000000000000E+000
REACT.1.rx=0.0000000000000000E+000
REACT.1.ry=0.0000000000000000E+000
REACT.1.rz=3.0000000000000000E+003
# Results for freedom case "default", load case "default" (displacement / rotation, then reaction where restrained):
#   node 1: x=0 (react 0), y=0 (react 1000), z=0 (react 0), rx=0 (react 0), ry=0 (react 0), rz=0 (react 3000)
#   node 2: x=0, y=-0.0005625, z=0, rx=0, ry=0, rz=-0.00028125
# Equilibrium check for freedom case "default", load case "default" (sum of all external forces should be ~0):
#   sum Fx=0, sum Fy=4.54747350886464E-13, sum Fz=0 -- OK
```

Against the hand calc:

- **`DISP.2.y=-5.6249999999999985E-004`** — `-5.625e-4` m, matching `v`
  above to floating-point round-off, same as Tutorial 1.
- **`DISP.2.rz=-2.8124999999999987E-004`** — `-2.8125e-4` **radians**
  (the beam's dof are always in SI radians, whatever length unit the
  rest of the model uses — see the `Units=SI (N, m, Pa, rad)` line in
  the model's own `[HEADER]`, just a comment for a human reader, not
  something the solver parses, but worth keeping consistent). Matches
  `theta` exactly.
- **`REACT.1.y=1.0000000000000005E+003`** and
  **`REACT.1.rz=3.0000000000000000E+003`** — `1000` N and `3000` N·m,
  matching `R_shear` and `R_moment`. This is the first model in this
  series with a *moment* reaction — a beam can resist rotation at a
  fixed end the way a truss never can, which is exactly why cantilever
  action (a fixed-free beam carrying a transverse load entirely as
  bending) is only possible with beam elements, not truss elements, no
  matter how you arrange the bars.
- **The equilibrium check passes, but only tells part of the story
  here.** `sum Fy=4.5e-13` confirms the vertical *forces* balance
  (1000 N applied, 1000 N reaction) — genuinely useful, same as
  Tutorial 1. But it does **not** check that the *moment* reaction
  (3000 N·m) is correct, only that the three translational-force sums
  are near zero — see the check's own description in
  `docs/native_format.md` ("Verbose output"). A model could have a
  wildly wrong moment reaction and this check would still print `OK`
  the same as this correct run does. Worth remembering as a boundary of
  what "OK" here actually promises: it's real evidence, not a
  guarantee.

## Reading the element forces

Everything above is about the *nodes*. A structure's real question is
usually what is happening *inside* the members — how much shear and
bending the beam is carrying, and where. After the displacement results,
`linstatic` also prints the internal forces it recovers from them, at
evenly spaced stations along each beam (the `BeamDivisions` setting in
`[SOLVERPARAMS]`, default 4 segments = 5 stations; try `BeamDivisions=10`
for a smoother diagram):

```
#   beam 1 (nodes 1-2), length 3, 4 division(s) = 5 stations:
#     forces on the +x face of the section, member-local (principal) axes:
#          s           N          Vy          Vz           T          My          Mz
#            0           0       -1000           0           0           0       -3000
#         0.75           0       -1000           0           0           0       -2250
#          1.5           0       -1000           0           0           0       -1500
#         2.25           0       -1000           0           0           0        -750
#            3           0       -1000           0           0           0           0
```

Compare with the hand calculation. For a tip load `P` the shear is the
same everywhere (`Vy = -P = -1000`, the whole load has to pass through
every section) and the bending moment falls linearly from the support to
nothing at the free end: `Mz(s) = -P (L - s)`, so `-3000` at the root,
`-1500` at mid-span, `0` at the tip — exactly the column above.

Two conventions to be clear about, because they decide every sign:

- **The forces are those on the section's positive face** — the face
  looking toward node 2 — i.e. what the part of the beam beyond the
  section does to the part before it. That is why the root moment reads
  `-3000` while the *reaction* in the nodal results reads `+3000`: the
  reaction is what the support does to the beam; the internal moment is
  what the rest of the beam does to the section. Same magnitude (that is
  moment equilibrium of the whole beam), opposite sign by definition.
- **"Principal axes" and "global axes".** The table above is in the
  beam's own local axes, which for this section are also its principal
  axes (the section is given as `Iy` and `Iz` with no product of inertia).
  The next table in the output resolves the same resultants on the global
  X/Y/Z axes. Here the two are identical because the beam lies along
  global X; tilt the beam (see regression case `022_beam_column_global_axes`,
  a column along Y) and they differ.

Stress needs more than forces. The stress table in this model's output
shows zeros for the same reason the section data is incomplete: `A`, `Iy`,
`Iz` and `J` don't say how far the top and bottom fibres are from the
centroid. Add the optional `Cy`, `Cz` (and `Rt` for torsion) to the
property line and the table fills in. Regression case
`020_beam_element_forces_cantilever` is this same beam with
`Cy = 0.1`, `Cz = 0.05`, and gives

```
#          s      sig_axial     sig_max     sig_min         tau   von Mises      Tresca
#            0           0      3.75E6     -3.75E6           0      3.75E6      3.75E6
#         1.5           0     1.875E6    -1.875E6           0     1.875E6     1.875E6
#            3           0           0           0           0           0           0
```

which is the textbook `sigma = M c / I = 3000 x 0.1 / 8e-5 = 3.75e6` Pa at
the root, tension on the top fibre and compression on the bottom, halving
at mid-span. Von Mises and Tresca both equal `|sigma|` here because
there is no torsion; give a beam a twist (case
`021_beam_axial_torsion_stress`) and the two start to differ.

## Try it yourself

1. **Change the load axis to `z` instead of `y`** (`2, z, -1000`). Now
   the beam bends about local `y` instead of local `z` — the hand calc
   is identical in form, but uses `Iy` (`0.00004`) instead of `Iz`
   (`0.00008`), so the deflection should come out *larger* (smaller `I`,
   same `L` and `P`, means a floppier beam) — worth predicting the exact
   number before running it.
2. **Pin node 1 instead of fixing it** (only `x, y, z` constrained, not
   `rx, ry, rz`). The model becomes an unstable mechanism — a beam
   that's free to rotate at its only support just spins around it under
   any transverse load, with nothing to resist the rotation. `linstatic`
   should refuse to solve it; read the error it gives and see which
   piece of `docs/model_format.md`'s validation list it's coming from.
3. **Add `BeamDivisions=8`** to `[SOLVERPARAMS]` and read how the moment
   table changes (it should stay on the same straight line, just with
   more points), then add `Cy` and `Cz` to the property line and watch
   the stress columns appear.
4. **Add a second load case** — a new `[LOADCASE ...]` section with a
   different value or axis, in the same model file. Both will solve
   against the same freedom case and the same factorized stiffness
   matrix (`linstatic` factorizes once per freedom case, then reuses it
   for every load case cheaply — see the `README.md` architecture
   section) and print as separate result blocks.

## Next

[Tutorial 3: a portal frame](03_portal_frame.md) — several beams meeting
at shared nodes, and what "statically indeterminate" looks like from a
finite-element model's point of view.
