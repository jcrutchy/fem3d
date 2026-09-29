# Tutorial 1: A single truss bar

The smallest possible finite element model: one bar, one load, one
degree of freedom that actually moves. Everything here you can check
with a calculator in under a minute — which is the point. Before trusting
this package on a problem you *can't* check by hand, it's worth seeing
it get one exactly right where you can.

**You'll need:** `linstatic` built (see the main `README.md`).

## The problem

```
      steel bar, L = 2 m, A = 0.001 m^2, E = 210 GPa
      |=================================================>  P = 1000 N
     (1)                                                  (2)
    fixed                                              free, axial
```

A straight steel bar, node 1 fixed, node 2 pulled with 1000 N along the
bar's own axis. Nothing else — no bending, no transverse load, node 2
can only move along `x`.

## The theory

A truss element carries axial load only (`fem_elements.TrussStiffness3D`
— no bending stiffness, same as a pin-jointed bar in a real truss). For
a bar of length `L`, cross-sectional area `A`, and Young's modulus `E`,
the axial stiffness is

```
k = EA / L
```

— force per unit extension, same idea as a spring constant. For this
bar:

```
k = (210e9 Pa)(0.001 m^2) / (2 m) = 1.05e8 N/m
```

Static equilibrium at the free end, `F = k*u`, gives the extension
directly:

```
u = F/k = PL/(AE) = (1000 N)(2 m) / [(0.001 m^2)(210e9 Pa)]
        = 9.523809523809524e-6 m   (about 9.5 micrometres)
```

and, since nothing else is holding the bar up, the fixed end must be
pulling back with exactly `-P`:

```
R = -1000 N
```

That's the entire hand calculation. `tests/regression/001_single_bar/`
carries exactly this derivation as its manifest's `Verification` field —
worth reading alongside this tutorial, since it's the same reasoning in
the form `fem_regress` actually checks against.

## The model file

`tests/regression/001_single_bar/model.fem`:

```
[NODES]
# id, x, y, z
1, 0, 0, 0
2, 2, 0, 0

[MATERIALS]
# id, E, nu, rho
1, 210000000000, -, -

[PROPERTIES]
# id, type, material, area[, Iy, Iz, J]
1, truss, 1, 0.001

[ELEMENTS]
# id, type, node1, node2, property[, refX, refY, refZ]
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
```

Line by line:

- **`[NODES]`** — node 1 at the origin, node 2 two metres away along `x`.
  That distance is where the `L = 2 m` in the hand calc comes from; it's
  never written explicitly anywhere in the model, only implied by the
  two nodes' coordinates.
- **`[MATERIALS]`** — `E = 210000000000` Pa (210 GPa, ordinary
  structural steel). `nu` and `rho` are both `-` (not specified):
  a truss element needs neither — no Poisson coupling in a 1D axial bar,
  and no solver in this model needs density (that's `modal`'s job — see
  `docs/modal.md`).
- **`[PROPERTIES]`** — property 1 is a `truss` section, material 1,
  area 0.001 m² (1000 mm², a modest bar).
- **`[ELEMENTS]`** — one truss element, node 1 to node 2, using
  property 1.
- **`[FREEDOMCASE default]`** — every constraint is `0` (fully fixed).
  Node 1 is pinned in all three directions; node 2 is only pinned
  sideways (`y`, `z`) — free to move along `x`, which is the one degree
  of freedom this whole model actually has anything to solve for.
- **`[LOADCASE default]`** — 1000 N at node 2, along `x`. Matches `P` in
  the hand calc directly.

Six degrees of freedom total (two nodes × three translational dof each —
a truss node has no rotational dof, since a pin-jointed bar can't resist
one), five of them constrained, one free.

## Running it

```
./bin/linstatic tests/regression/001_single_bar/model.fem
```

```
# FreePascal FEM Suite - linstatic (skyline linear-static solver)
# model=tests/regression/001_single_bar/model.fem
# nodes=2 elements=1 freedom_cases=1 load_cases=1 combinations=0
#
# linstatic solves Ku=F for one or more static load cases: assembles the
# global stiffness matrix K from every element, applies each freedom
# case's constraints (removing restrained dof, folding any prescribed
# nonzero displacement into the right-hand side), and solves the resulting
# reduced system directly (skyline Cholesky/LDL, no iteration -- exact up
# to floating-point round-off, not an approximate/converged solution).
# 1 material(s), 1 propert(y/ies), solver tolerance 1E-9.
# Element types in this model: 1 truss, 0 beam, 0 shellq4, 0 shellq8.
# (Verbose=1 is the default -- every line above and below starting with
# '#' is explanatory narrative, not data; set Verbose=0 in this model's
# [SOLVERPARAMS] section for plain key=value output only.)
#
# Freedom case "default": 2 node(s), 6 degree(s) of freedom total, 5 constrained, 1 free -- the free ones are what this solve is for.
#   Constrained dof (node.dof = prescribed value; 0 = fully restrained):
#     node 1, x = 0
#     node 1, y = 0
#     node 1, z = 0
#     node 2, y = 0
#     node 2, z = 0
# Load case "default": 1 applied load(s):
#   node 2, x = 1000
DISP.1.x=0.0000000000000000E+000
DISP.1.y=0.0000000000000000E+000
DISP.1.z=0.0000000000000000E+000
DISP.2.x=9.5238095238095231E-006
DISP.2.y=0.0000000000000000E+000
DISP.2.z=0.0000000000000000E+000
REACT.1.x=-9.9999999999999989E+002
REACT.1.y=0.0000000000000000E+000
REACT.1.z=0.0000000000000000E+000
REACT.2.y=0.0000000000000000E+000
REACT.2.z=0.0000000000000000E+000
# Results for freedom case "default", load case "default" (displacement / rotation, then reaction where restrained):
#   node 1: x=0 (react -1000), y=0 (react 0), z=0 (react 0)
#   node 2: x=9.52380952380952E-6, y=0 (react 0), z=0 (react 0)
# Equilibrium check for freedom case "default", load case "default" (sum of all external forces should be ~0):
#   sum Fx=1.13686837721616E-13, sum Fy=0, sum Fz=0 -- OK
```

That's every line the solver prints, unedited. Reading it against the
hand calc:

- **`DISP.2.x=9.5238095238095231E-006`** — `9.5238095238095231e-6` m.
  Compare to the hand calc's `9.523809523809524e-6` m: matches to 15
  significant figures, the two differing only in the last couple of
  digits of ordinary double-precision floating-point round-off. This is
  what "exact up to floating-point round-off, not an approximate/
  converged solution" (in the solver's own intro, printed above) means
  in practice — `linstatic` isn't iterating toward this answer, it's
  factorizing the system directly, so there's no convergence tolerance
  to worry about tightening.
- **`REACT.1.x=-9.9999999999999989E+002`** — `-999.99999999999989` N, the
  same `-1000` N from the hand calc, again to floating-point precision.
  Note `REACT.2.x` doesn't appear at all: node 2's `x` dof was *free*,
  not constrained, so it has a displacement but no reaction — a reaction
  force only exists at a dof the model is holding fixed. The
  human-readable table below repeats this same information — displacement
  *and* reaction together, one line per node — for exactly this reason:
  it's easy to lose track of which of a node's numbers is which when
  they're split across separate `DISP.`/`REACT.` blocks above.
- **The equilibrium check** — `sum Fx=1.13686837721616E-13`. Physically
  this should be *exactly* zero: the 1000 N pulling on node 2 and the
  1000 N (well, `999.99999999999989`) pushing back at node 1 are the
  only two external forces on this bar, and a body in static equilibrium
  has zero net external force by definition. `1.1e-13` isn't a modeling
  error, it's the same floating-point round-off as above, thirteen
  orders of magnitude smaller than the 1000 N forces involved — that's
  what "OK" means here. If you ever see this check fail with a residual
  that's a meaningful *fraction* of the applied load, that's a real bug
  worth reporting, not a rounding artifact — see `docs/native_format.md`
  ("Verbose output") for exactly what this check does and doesn't cover.

## Try it yourself

A few small changes, each with a hand calc you can redo in the margin,
before moving on to a model with more than one degree of freedom:

1. **Halve the area** (`0.0005` instead of `0.001`). Stiffness is
   proportional to `A`, so the extension should exactly double —
   `1.9047619...e-5` m.
2. **Double the length** (move node 2 to `4, 0, 0`). Extension doubles
   again, same reasoning (`u` is proportional to `L`).
3. **Change the load's sign** (`2, x, -1000`). Now the bar is in
   compression — extension and reaction both flip sign, same magnitude.
   (A real compression member can buckle; this element doesn't model
   that — it's happy to report a negative-length answer for an
   arbitrarily slender bar. Worth keeping in mind for anything you build
   with this later.)
4. **Set `Verbose=0`** in a new `[SOLVERPARAMS]` section. You'll get only
   the `DISP.`/`REACT.` lines — the same numbers, none of the narrative.
   Useful once you're comfortable enough with a model type that you just
   want the answer; `fem_regress` itself always sees the terse form
   embedded in the verbose output, since its parser only reads
   `key=value` lines and ignores everything else (see
   `docs/regression_testing.md`).

## Next

[Tutorial 2: a cantilever beam](02_cantilever_beam.md) — the same idea,
but with a bending stiffness matrix instead of a purely axial one, and
more than one degree of freedom actually being solved for.
