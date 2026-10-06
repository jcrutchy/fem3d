# Tutorial 4: Natural frequencies of a two-mass chain

Tutorials 1-3 were all *static*: apply a load, find the displacement.
This one asks a different question — if you pluck the structure and let
go, how does it vibrate? `modal` answers that by finding the structure's
**natural frequencies** and **mode shapes**. Same approach as before: a
problem small enough to solve exactly by hand, then the solver's real
output read against it.

**You'll need:** Tutorial 1 (the truss bar and its stiffness `EA/L`), and
a rough idea of what "mass" and "frequency" mean. No prior vibration
theory is assumed; the few facts needed are derived below.

## The problem

```
   (1)=====bar 1=====(2)=====bar 2=====(3)  --> x
  fixed      L=1.5 m        L=1.5 m     free end
```

Two identical steel bars joined end to end. Node 1 is fixed to a wall;
nodes 2 and 3 can only move along `x`. Nothing is loaded — in modal
analysis the structure just vibrates freely.

This is regression case `tests/regression/006_modal_two_dof_chain`,
which `fem_regress` re-checks on every change to the codebase.

## The theory

**Stiffness.** Each bar is a spring of stiffness `k = EA/L` (Tutorial 1).
For `E = 210 GPa`, `A = 0.0008 m^2`, `L = 1.5 m`:

```
k = 210e9 * 0.0008 / 1.5 = 112,000,000 N/m
```

**Mass.** `modal` uses a *lumped* mass matrix: each bar's mass
`rho*A*L` is split equally between its two end nodes. With
`rho = 7850 kg/m^3`, one bar's mass is

```
m = 7850 * 0.0008 * 1.5 = 9.42 kg
```

Node 1 is fixed, so its share doesn't matter. Node 2 touches both bars
and gets `m/2 + m/2 = m = 9.42 kg`. Node 3 touches only bar 2 and gets
`m/2 = 4.71 kg`.

**Equations of motion.** With `u2`, `u3` the free displacements, the
stiffness and mass matrices for the two free dof are

```
K = [  2k  -k ]        M = [ m   0  ]
    [ -k    k ]            [ 0  m/2 ]
```

Free vibration at angular frequency `omega` means `u(t) = phi *
sin(omega t)`, which turns Newton's law into the **generalized eigenproblem**

```
K phi = omega^2 M phi
```

Non-trivial solutions need `det(K - omega^2 M) = 0`. Writing
`lambda = omega^2` and expanding:

```
(2k - lambda m)(k - lambda m/2) - k^2 = 0
   =>   (m^2/2) lambda^2 - 2 k m lambda + k^2 = 0
   =>   lambda = (k/m) (2 -/+ sqrt 2)
```

With `k/m = 112e6 / 9.42 = 11,889,596.6`:

```
lambda1 = 11,889,596.6 * (2 - 1.41421356) =  6,964,764.4   omega1 = 2639.084 rad/s
lambda2 = 11,889,596.6 * (2 + 1.41421356) = 40,593,622.0   omega2 = 6371.312 rad/s
```

Dividing by `2*pi` gives frequencies in hertz: **420.02 Hz** and
**1014.03 Hz**.

**Mode shapes.** Substituting each `lambda` back into the first row,
`(2k - lambda m) u2 = k u3`, gives the *ratio* `u3/u2`:

```
mode 1:  u3/u2 = 2 - (2 - sqrt 2) = +sqrt 2 = +1.414   (both move the same way)
mode 2:  u3/u2 = 2 - (2 + sqrt 2) = -sqrt 2 = -1.414   (they move oppositely)
```

A mode shape only has a direction, not a size, so solvers *normalize*
it. `modal` uses **mass normalization**: scale `phi` so that
`phi^T M phi = 1`. Here that is `m u2^2 + (m/2) u3^2 = 2 m u2^2 = 1`, so

```
u2 = 1 / sqrt(2 * 9.42) = 0.230388        u3 = +/- sqrt 2 * u2 = +/- 0.325818
```

(The overall sign of a mode is arbitrary — `phi` and `-phi` are the same
vibration.)

## The model file

```
[NODES]
1, 0, 0, 0
2, 1.5, 0, 0
3, 3, 0, 0

[MATERIALS]
# id, E, nu, rho
1, 210000000000, -, 7850        <- rho (density) is what modal adds

[PROPERTIES]
1, truss, 1, 0.0008             <- area A

[ELEMENTS]
1, truss, 1, 2, 1
2, truss, 2, 3, 1

[FREEDOMCASE default]
1, x, 0
1, y, 0
1, z, 0                         <- node 1 fully fixed
2, y, 0
2, z, 0
3, y, 0
3, z, 0                         <- nodes 2 and 3 free to move along x only
```

Two things differ from the static tutorials: the material has a density
(`modal` rejects a model without one — regression case
`904_modal_missing_rho_borked` checks that), and the `[LOADCASE]` is
empty, because free vibration has no applied load.

The two free dof (`u2` and `u3`) are why there are exactly two modes:
`modal` finds one mode per free dof that carries mass.

## Running it

```
modal tests/regression/006_modal_two_dof_chain/model.fem
```

The verbose preamble (excerpt) confirms the setup:

```
# 1 material(s), 1 propert(y/ies). Element types: 2 truss, 0 beam.
# Freedom case "default": 3 node(s), 9 degree(s) of freedom total, 7 fixed, 2 free -- modal analysis finds one mode per free dof that carries mass.
```

9 dof, 7 fixed, 2 free: matches the hand model above. Next comes the
self-check, which is worth understanding:

```
# Mode mass-orthonormality check for freedom case "default" (should be near-exact regardless of model):
#   max |phi_i^T M phi_j|, i<>j = 0; max |phi_i^T M phi_i - 1| = 0 -- OK
```

Mass-normalized modes must satisfy `phi_i^T M phi_j = 0` for `i <> j`
(the modes are *orthogonal* with respect to mass) and `= 1` for `i = j`
(that is the normalization). This is a genuine solver check, not just a
teaching aid: a non-zero value here would indicate a real eigensolver
bug. It passes exactly here, as it should for a 2x2 system.

Then the modes themselves (zero-valued `y`/`z`/node-1 lines trimmed):

```
# Mode 1: omega=2639.0840151227 rad/s, freq=420.023266241584 Hz, period=0.00238082049346484 s
MODE.1.omega=2.6390840151227003E+003
MODE.1.freq=4.2002326624158400E+002
MODE.1.DISP.2.x=2.3038783879204569E-001
MODE.1.DISP.3.x=3.2581760622553729E-001
# Mode 2: omega=6371.31242155127 rad/s, freq=1014.02586587268 Hz, period=0.00098616813796894 s
MODE.2.omega=6.3713124215512653E+003
MODE.2.freq=1.0140258658726775E+003
MODE.2.DISP.2.x=2.3038783879204575E-001
MODE.2.DISP.3.x=-3.2581760622553724E-001
```

## Reading it against the hand calculation

| Quantity | Hand calculation | `modal` output |
|---|---|---|
| omega 1 | 2639.084 rad/s | 2639.0840151227 |
| freq 1 | 420.02 Hz | 420.023266 Hz |
| omega 2 | 6371.312 rad/s | 6371.3124215512 |
| freq 2 | 1014.03 Hz | 1014.025866 Hz |
| mode 1, `u2`, `u3` | 0.230388, +0.325818 | 0.2303878, +0.3258176 |
| mode 2, `u2`, `u3` | 0.230388, -0.325818 | 0.2303878, -0.3258176 |

Everything agrees to every digit shown. Mode 1 has both masses moving
together (the lowest-energy way to deform the chain); mode 2 has them
moving against each other (stiffer, so higher frequency). The period is
simply `1/freq` — the time for one full cycle.

## Things worth noticing

- **The output is mass-normalized, not "unit amplitude".** The `0.2304`
  and `0.3258` are not displacements in metres — a mode shape has no
  physical size. Only the *ratio* `u3/u2 = 1.414`, and its sign, carry
  meaning.
- **Frequency does not depend on the mode's size,** so unlike static
  analysis there are no applied loads and no reactions to sum. The
  equilibrium self-check from Tutorials 1-3 is replaced by the
  orthonormality check above.
- **Lumped mass is a modelling choice.** Splitting each bar's mass
  between its end nodes is the simplest mass model, and the answer is
  only exact *for that model* — a real continuous bar vibrates at
  slightly different frequencies, and the difference shrinks as you
  add elements. See `docs/modal.md` for what `modal` does and does not
  model (for instance, rotary inertia is not modelled).
- **Try it yourself:** double the density in the model. Every frequency
  should drop by `sqrt(2)`, since `omega = sqrt(k/m)`. For a one-dof
  warm-up, `tests/regression/005_modal_single_dof` has the closed form
  `omega = sqrt(2E / (rho L^2))`, independent of the cross-section area
  because it cancels.

## What's next

Tutorial 3 verified a frame too big for hand calculation against an
independent NumPy solve; the same idea applies to larger modal models.
Case `006` itself was checked this way (`numpy.linalg.eigh` on the
mass-normalized system) — see its `Verification=` line in `manifest.ini`.
