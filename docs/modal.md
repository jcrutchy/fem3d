# `modal` — lumped-mass modal analysis

Natural frequencies and mode shapes for the same model format everything
else uses, via a lumped mass matrix and a from-scratch Jacobi eigensolver
(`fem_eigen.pas`) over the free-free system.

```
modal model.json
modal model.json > modes.txt
adapt_x in.txt | modal -
```

## What it computes

For each free dof, an equal-and-opposite half of each connected element's
mass is lumped onto its two end nodes' **translational** dofs (`x`,`y`,`z`)
only. No rotary inertia is modeled, so a beam's free rotational dofs have
**zero mass**. They are *not* fixed and *not* refused: they are eliminated
exactly by static condensation before the eigensolve.

Split the free dofs into `t` (carry mass) and `r` (massless). Then
`K*phi = omega^2*M*phi` with `M = [Mtt 0; 0 0]` is exactly equivalent to

```
(Ktt - Ktr * Krr^-1 * Krt) * phi_t = omega^2 * Mtt * phi_t
phi_r = -Krr^-1 * Krt * phi_t
```

This is *not* an approximation (unlike Guyan reduction, which eliminates
dofs that do carry mass): a dof with no inertia is slaved statically to
the others, so the reduced problem has exactly the same eigenvalues as the
full one. `Krr` is factored by a dense Cholesky; the massless-dof values of
each mode shape are then recovered from `phi_t`. Verified against an
independent NumPy reference that never forms the condensed matrix
(regression case 035, agreement ~1e-15).

With the condensed stiffness `Kc` and `Mtt` diagonal and positive, the
problem reduces to a standard symmetric one (`Kmass = D^-1 Kc D^-1`, `D =
diag(sqrt(Mtt))`), which `fem_eigen`'s Jacobi solver handles directly,
giving the full spectrum (one mode per **massed** dof, ascending) at once
-- there's no "how many modes do you want" flag, because for the dense,
modest-sized systems this suite targets, computing all of them costs about
the same as computing a few and is more honest about what's actually
available.

Consequence of having no rotary inertia: **torsion about a beam's own axis
has no polar inertia**, so pure torsional vibration modes do not appear
(the torsional dof is condensed out like any other rotation). Bending and
axial modes are unaffected, and bending frequencies converge to the
analytical values as the beam is meshed finer.

## Requirements beyond the shared validator

Two checks are specific to this solver and deliberately live in
`modal.lpr`, not in `fem_validate` (see `docs/model_format.md` for why
that split exists):

- Every material actually used by an element must specify `rho` (density)
  -- `linstatic` never needs mass, so this isn't a blanket requirement on
  every model.
- Every constraint must be a fixed support (`value: 0.0`). A non-zero
  prescribed displacement is a static-analysis concept (`linstatic` folds
  it into the load vector); there's no equivalent for an eigenvalue
  extraction.

And, discovered when the free dofs are split into massed and massless:

- A model in which **no** free dof carries mass is refused (nothing can
  vibrate -- usually a missing density or everything restrained).
- A massless free dof that **no stiffness restrains** (for example a node
  that no element touches, or a mechanism among the massless dofs) makes
  `Krr` singular. It is refused by name (node + dof) instead of producing
  NaN frequencies. Case 923 checks this.

## Freedom cases

Like `linstatic`, `modal` solves every freedom case in the model (see
`docs/model_format.md`'s "Load cases, freedom cases, and combinations").
It has no load cases of its own -- the eigenproblem is homogeneous, there's
nothing to apply a load case's forces to -- so only the freedom-case
prefixing rule applies to its output: bare `MODE.<n>...` keys for a
model with exactly one freedom case, `<freedomCaseId>.MODE.<n>...`
otherwise. The two modal-specific checks (rho required, constraints must
be zero) run against every freedom case in the model.

## Output

Same KV convention as `linstatic`, extended with a mode index:

```
MODE.<n>.omega=<rad/s>
MODE.<n>.freq=<Hz>
MODE.<n>.DISP.<nodeId>.<dof>=<mode shape component>
```

Mode shapes are mass-normalized (`phi^T M phi = 1`, the standard modal
convention) and, as with any eigenvector, correct up to an arbitrary
overall sign -- don't expect the sign of a given mode to match between
runs of a formally-identical model built two different ways, only its
magnitude and relative pattern.

## Exit codes

Same convention as every solver (see `docs/model_format.md`): 1=usage,
2=load error, 3=model not suitable for this solver (validation, or one of
the modal-specific checks above), 4=solver-level numerical failure (a
negative eigenvalue -- i.e. the free-free stiffness isn't positive
semi-definite, which for a valid structure shouldn't happen).

## Known limitations

- Dense Jacobi eigensolve: fine for the small models this suite targets,
  not suited to a large system (no sparsity exploited, unlike
  `linstatic`'s skyline solve). A sparse/iterative approach (subspace
  iteration, Lanczos) would be the natural upgrade if that ever matters.
- No rotary inertia for beam elements (see above). Free rotations are
  condensed out exactly, which is correct for the model as defined, but a
  structure whose rotary inertia matters (a very stocky beam at high
  frequency, or torsional modes) is not represented.
- No mass matrix for `shellq4` or `shellq8` -- a model containing one is rejected
  outright (by element type, not silently mishandled) rather than run
  with a wrong or missing mass contribution.
