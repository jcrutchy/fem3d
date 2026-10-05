# crackgrowth

A fatigue crack growth module — Paris, Walker, Forman, and NASGRO
growth-rate laws, working toward stress-intensity solutions for cracks
at open and loaded (bearing) fastener holes, with secondary bending and
multiple-site-damage (MSD) support, aimed at real damage-tolerance
analysis (e.g. a stiffened flange around a fuselage access-door opening,
a rivet row carrying shear flow, a crack growing from a fastener hole).

Sits alongside the femgeo units as a self-contained module using the same
project conventions (native key=value model format, `fem_regress`-style
regression manifests, verbose-by-default solver output) without being
folded into the FEA solver tree — this isn't a `Ku=F` solver, it doesn't
need a mesh.

See `docs/TODO_crackgrowth.md` for exactly what's built, what's deliberately
deferred, and why.

## Layout

```
src/common/fem_cg_types.pas, fem_cg_growthlaws.pas
src/tools/patch_test/run_growthlaw_test.lpr
docs/TODO_crackgrowth.md
```

(No regression cases yet -- they need a crack-growth model format first.)

## Building the patch test

```
fpc -MObjFPC -FE./bin -FU./bin -Fu./src/common src/tools/patch_test/run_growthlaw_test.lpr
./bin/run_growthlaw_test
```
