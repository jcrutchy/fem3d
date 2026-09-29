# Tutorials

A graduated series of worked examples, aimed at someone who knows the
underlying structural theory (or is learning it) but hasn't used *this*
package, or maybe any FEA package, before. Each one takes an existing,
hand-verified (or independently cross-checked) model from
`tests/regression/`, walks through the theory behind its expected
answer, annotates the model file line by line, and reads the solver's
actual verbose output against that hand calculation — real output,
copy-pasted from a real run, not retyped or paraphrased.

Every tutorial's model is a real regression case: run it yourself, and
you're running the exact thing `fem_regress` checks on every change to
this codebase, not a simplified stand-in.

1. **[A single truss bar](01_single_truss_bar.md)** — the smallest
   possible model. Axial stiffness, one degree of freedom, and how to
   read the verbose output for the first time: the constraint listing,
   the results table, the equilibrium self-check.
2. **[A cantilever beam](02_cantilever_beam.md)** — bending stiffness,
   rotational degrees of freedom, and a fixed-end moment reaction —
   plus a first look at what the equilibrium check does and doesn't
   cover.
3. **[A portal frame](03_portal_frame.md)** — multiple elements sharing
   nodes, static indeterminacy, and why verifying a model too complex
   for hand calculation needs a genuinely independent second method, not
   just a bigger version of the same check.

## Still to come

- A flat plate/shell tutorial (`shellq4`, then `shellq8`), building on
  the membrane patch-test models already in
  `tests/regression/016_shellq4_membrane_patch` and
  `017_shellq8_membrane_patch` — same worked-example treatment as above,
  covering membrane action, the drilling-dof stopgap, and (for
  `shellq8`) the thick-vs-thin shear-deformable formulation.
- A `modal` tutorial — natural frequency of a simple lumped-mass system,
  hand-checked against `omega = sqrt(k/m)`, and reading the mode
  mass-orthonormality self-check.
- A `linsparse` tutorial — the same model as one of the direct-solver
  tutorials above, re-run through the iterative PCG solver, comparing
  its convergence reporting against `linstatic`'s exact factorization.
- A load-combination tutorial, building on
  `tests/regression/009_load_case_combination`.

If you're looking for a worked example that isn't here yet, the
regression suite (`tests/regression/`, indexed in
`docs/regression_testing.md`) already has hand-verified or
independently-cross-checked models covering most of what this package
can do — every one of them is fair game to read the same way these
tutorials do, even before a tutorial gets written around it.
