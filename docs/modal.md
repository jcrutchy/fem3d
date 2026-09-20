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
only. This is exact enough for truss models (every mass-carrying dof is
translational anyway) and fine for a beam model too, *as long as its
rotational dofs end up fixed rather than free* -- proper rotary-inertia
lumping for beams needs section data (radius of gyration or similar) this
suite doesn't model yet, so a free rotational dof with no mass is refused
outright (see "What it refuses" below) rather than silently given zero or
approximate mass.

With M diagonal and positive on every free dof, the generalized
eigenproblem `K*phi = omega^2*M*phi` reduces cleanly to a standard
symmetric one (`Kmass = D^-1 K D^-1` where `D = diag(sqrt(M))`), which
`fem_eigen`'s Jacobi solver handles directly, giving the full spectrum
(all `NEQ` modes, ascending) at once -- there's no "how many modes do you
want" flag, because for the dense, modest-sized systems this suite
targets, computing all of them costs about the same as computing a few
and is more honest about what's actually available.

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

And, discovered during mass assembly rather than up front: any free dof
that ends up with zero lumped mass is refused by name (node + dof), not
silently dropped or given a fudge value -- in practice this means "a beam
model whose rotational dofs are free."

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
- No rotary inertia for beam elements (see above) -- a beam model only
  works here if its rotational dofs are fixed.
