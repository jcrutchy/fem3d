# Tutorial 3: A portal frame

Tutorials 1 and 2 had exact hand calculations because each was
*statically determinate* — few enough unknowns that equilibrium alone
pins them down. This one isn't. Three beams, two fixed bases, one
lateral load: more restraint than the equations of statics can resolve
by themselves. It's still not a hard problem, and it's still solved
exactly — the same way, by the same solver, with the same kind of
verbose output — but *checking* the answer needs a different approach
than a calculator and five minutes.

**You'll need:** Tutorials 1 and 2 first.

## The problem

```
   y
   ^
   |     P = 1000 N
   |    -------->
   |   (2)========(3)
   |    |          |
   |    |          |
   |    |          |
   |   (1)        (4)
   |  fixed       fixed
   +-------------------------> x
```

A rectangular portal frame: two vertical columns (node 1 to node 2, and
node 4 to node 3, each 3 m), one horizontal beam across the top (node 2
to node 3, 5 m), both bases fixed rigidly into the ground. 1000 N pushes
sideways at node 2.

## Why there's no hand calculation this time

Count the unknowns: each fixed base can push back with a horizontal
force, a vertical force, and a moment — 3 reaction components per
support, 2 supports, **6 unknown reactions**. Plane-frame statics gives
exactly 3 independent equilibrium equations (sum of forces in `x`, sum
of forces in `y`, sum of moments). `6 - 3 = 3`: this frame is **3 times
statically indeterminate**. Equilibrium alone can't solve for those 6
reactions — there are more unknowns than equations, full stop, no
amount of algebra fixes that.

Classical structural analysis has hand methods for this (moment
distribution, the force method, slope-deflection) — but they exist
*because* this problem is hard by hand, not because it's hard for a
computer. The stiffness method — the thing every solver in this package
actually does — doesn't care about determinacy at all. It doesn't solve
equilibrium equations directly; it solves for the *displacements* that
satisfy both equilibrium and the structure's own stiffness everywhere at
once (`Ku=F`, same equation as Tutorials 1 and 2 — nothing about the
solver's process changes here). Extra redundancy just means a few more
rows and columns in `K`, not a different algorithm. That's arguably the
single biggest practical advantage FEA has over classical hand methods:
indeterminacy, which is the whole difficulty in a hand calculation,
isn't a special case here at all.

## How this one was actually verified

If you can't check the answer with algebra, you need a second, genuinely
independent way to get the same answer — not just eyeballing that it
"looks reasonable." `tests/regression/008_portal_frame/manifest.ini`
explains how: the expected values were computed with an *independent*
NumPy assembly of the same (separately-validated) beam stiffness
formulation — different code, same underlying element math already
proven correct in Tutorial 2's determinate case — and cross-checked
against this solver's output to full precision. Global equilibrium (the
overall sum of reactions balancing the applied load) was checked
separately too, as a sanity check on the *NumPy replica itself*, not on
this solver.

That two-implementation approach — verify the element formulation once,
on a problem simple enough to check by hand, then trust that same
formulation in an independent assembly for anything too complex to
check directly — is the same idea behind this project's `run_q8_*_test`
patch tests, if you've looked at those: build confidence in a small,
checkable piece, then let that piece carry weight in a bigger model
where a direct check isn't available.

## The model file

`tests/regression/008_portal_frame/model.fem`:

```
[NODES]
# id, x, y, z
1, 0, 0, 0
2, 0, 3, 0
3, 5, 3, 0
4, 5, 0, 0

[MATERIALS]
# id, E, nu, rho
1, 200000000000, 0.3, -

[PROPERTIES]
# id, type, material, area[, Iy, Iz, J]
1, beam, 1, 0.006, 0.00005, 0.00009, 0.00003

[ELEMENTS]
# id, type, node1, node2, property[, refX, refY, refZ]
1, beam, 1, 2, 1
2, beam, 2, 3, 1
3, beam, 3, 4, 1

[FREEDOMCASE default]
# node, dof, value
1, x, 0
1, y, 0
1, z, 0
1, rx, 0
1, ry, 0
1, rz, 0
4, x, 0
4, y, 0
4, z, 0
4, rx, 0
4, ry, 0
4, rz, 0

[LOADCASE default]
# node, dof, value
2, x, 1000
```

Nothing here is a new concept from Tutorial 2 — the only thing that's
new is *more of it*: 4 nodes instead of 2, 3 beam elements sharing nodes
2 and 3 instead of 1 element in isolation, 2 fixed bases instead of 1.
Node 2 and node 3 aren't constrained at all — they're where the frame
actually deforms, same role node 2 played in Tutorial 2.

## Running it

```
./bin/linstatic tests/regression/008_portal_frame/model.fem
```

```
# FreePascal FEM Suite - linstatic (skyline linear-static solver)
# model=tests/regression/008_portal_frame/model.fem
# nodes=4 elements=3 freedom_cases=1 load_cases=1 combinations=0
#
# linstatic solves Ku=F for one or more static load cases: assembles the
# global stiffness matrix K from every element, applies each freedom
# case's constraints (removing restrained dof, folding any prescribed
# nonzero displacement into the right-hand side), and solves the resulting
# reduced system directly (skyline Cholesky/LDL, no iteration -- exact up
# to floating-point round-off, not an approximate/converged solution).
# 1 material(s), 1 propert(y/ies), solver tolerance 1E-9.
# Element types in this model: 0 truss, 3 beam, 0 shellq4, 0 shellq8.
# (Verbose=1 is the default -- every line above and below starting with
# '#' is explanatory narrative, not data; set Verbose=0 in this model's
# [SOLVERPARAMS] section for plain key=value output only.)
#
# Freedom case "default": 4 node(s), 24 degree(s) of freedom total, 12 constrained, 12 free -- the free ones are what this solve is for.
#   Constrained dof (node.dof = prescribed value; 0 = fully restrained):
#     node 1, x = 0
#     node 1, y = 0
#     node 1, z = 0
#     node 1, rx = 0
#     node 1, ry = 0
#     node 1, rz = 0
#     node 4, x = 0
#     node 4, y = 0
#     node 4, z = 0
#     node 4, rx = 0
#     node 4, ry = 0
#     node 4, rz = 0
# Load case "default": 1 applied load(s):
#   node 2, x = 1000
DISP.1.x=0.0000000000000000E+000
...
DISP.2.x=1.0457034023759534E-004
DISP.2.y=5.8585613109290445E-007
...
DISP.3.x=1.0250159421595307E-004
DISP.3.y=-5.8585613109290467E-007
...
REACT.1.x=-5.0350095480585679E+002
REACT.1.y=-2.3434245243716177E+002
REACT.1.rz=9.2178231575623818E+002
REACT.4.x=-4.9649904519414451E+002
REACT.4.y=2.3434245243716185E+002
REACT.4.rz=9.0650542205795682E+002
# Results for freedom case "default", load case "default" (displacement / rotation, then reaction where restrained):
#   node 1: x=0 (react -503.500954805857), y=0 (react -234.342452437162), z=0 (react 0), rx=0 (react 0), ry=0 (react 0), rz=0 (react 921.782315756238)
#   node 2: x=0.000104570340237595, y=5.85856131092904E-7, z=0, rx=0, ry=0, rz=-0.0000277551472579088
#   node 3: x=0.000102501594215953, y=-5.85856131092905E-7, z=0, rx=0, ry=0, rz=-0.0000269594757111233
#   node 4: x=0 (react -496.499045194145), y=0 (react 234.342452437162), z=0 (react 0), rx=0 (react 0), ry=0 (react 0), rz=0 (react 906.505422057957)
# Equilibrium check for freedom case "default", load case "default" (sum of all external forces should be ~0):
#   sum Fx=-1.30739863379858E-12, sum Fy=8.5265128291212E-14, sum Fz=0 -- OK
```

(The full run has one `DISP.`/`REACT.` line per node per dof — trimmed
with `...` above to the interesting ones; run it yourself for the
complete, unedited output.)

A few things worth noticing that Tutorials 1 and 2 couldn't show:

- **The load splits unevenly between the two bases.** `REACT.1.x`
  ≈ `-503.5` N and `REACT.4.x` ≈ `-496.5` N — they don't split the 1000 N
  load 50/50, even though the frame looks symmetric at a glance. It
  isn't quite: the load is applied at node 2 (the *left* column's top),
  not centred on the beam, so the two columns don't see identical
  conditions. This kind of "obviously symmetric until you look closer"
  result is exactly the kind of thing that's easy to get wrong by
  hand-waving and hard to get wrong once it's actually assembled and
  solved.
- **Both moment reactions are large and similar** (`REACT.1.rz` ≈
  `921.8` N·m, `REACT.4.rz` ≈ `906.5` N·m) — the fixed bases are doing
  real work resisting rotation, which is exactly the redundancy that
  made this problem indeterminate in the first place. A pinned-base
  version of this same frame (remove `rx, ry, rz` from both supports'
  constraints) would have zero moment reactions and only 2 indeterminate
  degrees instead of 3 — worth trying, and worth predicting first which
  numbers should change and which shouldn't.
- **The equilibrium check passes, and it's worth being precise about
  what that does and doesn't confirm here.** `sum Fx` and `sum Fy` both
  come out at machine-precision noise, confirming the horizontal and
  vertical force reactions genuinely balance the applied load — real,
  useful evidence. But as flagged in Tutorial 2: it says nothing about
  whether the *individual* reactions, or the split between the two
  bases, or the moments, are each individually correct — only that
  their translational sum is. That gap between "checked" and "verified"
  is exactly why this case leans on the independent NumPy cross-check
  above instead of resting on this self-check alone.

## Try it yourself

1. **Predict, then check, the pinned-base version** (drop `rx, ry, rz`
   from both freedom-case entries for nodes 1 and 4). Moment reactions
   should vanish entirely; the horizontal reactions should still sum to
   `-1000` N between them (global equilibrium doesn't care how the
   frame is supported), but the split between the two bases will change.
2. **Move the load to node 3 instead of node 2** (`3, x, 1000`, remove
   the `2, x, 1000` line). By the frame's left-right symmetry, this
   should give the *mirror image* of the original run — node 3's
   displacement should match node 2's original displacement, and vice
   versa, with the two base reactions swapping which one carries more.
3. **Add a vertical load too**, e.g. `2, y, -500` in the same load case
   as the existing `2, x, 1000`. Nothing about the model or the process
   changes — just another line in `[LOADCASE default]` — which is worth
   sitting with for a moment: the difficulty of a hand method usually
   scales badly as a structure gets more complicated, and here it
   didn't scale at all.

## Next

The truss, beam, and shell (`shellq4`/`shellq8`) tutorials series
continues to grow — see `docs/tutorials/README.md` for what's covered so
far and what's still open (2D flat-plate bending is next, building
directly on the shell patch-test models already in
`tests/regression/016_shellq4_membrane_patch` and
`017_shellq8_membrane_patch`).
