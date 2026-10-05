# crackgrowth: status and TODO

## Done, and verified

- `src/common/fem_cg_types.pas` — `TCrackGrowthMaterial`: per-law
  constants (Paris, Walker, Forman, NASGRO), each gated by its own
  `HasXxx` flag so a material only needs constants for the laws it
  actually has data for.
- `src/common/fem_cg_growthlaws.pas` — the four rate laws, plus two
  law-SELECTION modes:
  - `ConservativeRate` — evaluates every law the material has data for
    and returns the fastest-growth (shortest-life) prediction, with
    `LawUsed` reporting which law won, so the choice is auditable
    rather than opaque.
  - `BestAvailableRate` — picks the single most physically complete law
    the material has full constants for (NASGRO > Forman > Walker >
    Paris), rather than the fastest-growth one.
- `src/tools/patch_test/run_growthlaw_test.lpr` — 18 checks: Paris
  against a hand calculation; Walker(Gamma=1) proven algebraically
  identical to Paris for several R, not just asserted; Forman against
  hand calculations and its Kc-exceeded case raising rather than
  returning a number; NASGRO cross-checked against an independently
  written Python reference to 1e-9 relative (see the note below on what
  this does and doesn't prove); both selection modes exercised
  including their no-usable-law error case.

## Not done yet, on purpose — scope was deliberately kept open

Discussed with Jared 2026-09-29: the K-solution and MSD scope for a
real analysis (a stiffened flange, a rivet row, bypass+bearing with
secondary bending, MSD critical-path search) is large enough that
trying to build all of it in one pass risked a shallow, unverified
result across the board rather than a solid foundation. Agreed: build
the growth-law engine solidly first (done, above), defer the rest here
rather than drop it.

### K-solution layer (not started)

Needed before this can predict growth for any real geometry:
- **Open-hole K**: a through-crack at an unloaded circular hole under
  remote (bypass) stress — a standard handbook solution (Bowie, or the
  equivalent tabulated/curve-fit form in Tada/Paris/Irwin's *Stress
  Analysis of Cracks Handbook*).
- **Loaded-hole (bearing) K**: a through-crack at a pin-loaded hole,
  superposed with the open-hole bypass K — the standard
  bypass-plus-bearing approach (see e.g. Grandt, *Fundamentals of
  Structural Integrity*, or Swift's original treatment) for a fastener
  actually transferring load, which is the case in Jared's flange
  example (a rivet row carrying shear flow), not just an open hole.
- **Secondary bending**: load-path eccentricity in a single-shear
  (non-symmetric) joint induces an additional local bending stress at
  the hole, on top of bypass+bearing. Jared wants this as an *option*:
  either take a user-supplied bending multiplier directly, or compute
  one from joint geometry (offset, skin thicknesses, relative
  stiffness) via a documented method (e.g. the approach in ESDU data
  sheets or Swift's papers) — the computed path is real additional
  scope, not a trivial extension of the superposition above.
- This layer needs `Smax/SigmaFlow`, the ratio NASGRO's closure model
  needs (see `fem_cg_growthlaws.NasgroRate`'s comment) — computing it
  requires exactly this layer (relating a remote stress back through
  the geometry factor), which is why `NasgroRate` currently hardcodes
  a placeholder `S=0.3` rather than taking it as a parameter. **This
  placeholder must be replaced with an explicit `SmaxOverSigma0`
  parameter before NASGRO predictions from this unit mean anything for
  a real crack.**

### MSD (multiple-site damage) (not started)

Jared wants the ability to find the CRITICAL crack path across a field
of fastener/open holes — not just grow one crack in isolation. That
needs:
- An interaction/interference factor on single-crack K for adjacent
  cracks approaching each other (or a periodic/finite-row K-solution
  treating the whole row at once).
- A linkup criterion (net-section yield, or a critical ligament
  stress) for when two crack tips are close enough to coalesce into one
  longer crack.
- A search over which combination of growing cracks in the hole field
  leads to the shortest overall life — genuinely more than a
  straightforward extension of single-crack growth, since it's a
  combinatorial question over which holes crack, in which order, and
  how they link.
- v2 suggestion (not agreed, just a reasonable next step): start with a
  SPECIFIC small case — two or three adjacent holes, symmetric loading,
  one interaction factor — verified against a published example, before
  attempting the fully general "arbitrary hole field, find the worst
  path" version.

### Load spectrum (constant amplitude only, for now)

Agreed to start constant-amplitude (a single, fixed `DeltaK`/`R` per
cycle, which is all the current growth-law engine needs). Jared wants,
eventually:
- **Rainflow cycle counting (RCC)** — turning a variable-amplitude
  stress-vs-time history into a set of discrete constant-amplitude
  cycles the existing growth-law engine could already consume one at a
  time.
- **PSD (power spectral density)** — random-vibration loading,
  presumably converted to an equivalent cycle count/severity via a
  standard method (e.g. Dirlik) before crack growth integration —
  meaningfully more machinery than RCC.
- **S-N (stress-life) based fatigue** — NOTE: this is a genuinely
  different fatigue methodology from everything else in this module
  (total-life / crack-initiation approach, not fracture-mechanics-based
  crack GROWTH) — worth being clear this isn't "one more input to the
  same engine," it's a different analysis approach entirely, likely
  wanting its own comparison/cross-check role against the crack-growth
  prediction rather than living inside `fem_cg_growthlaws` itself.

### NASGRO closure model — needs independent confirmation

`fem_cg_growthlaws.NewmanClosureF` implements the Newman
crack-opening-stress-ratio formula from memory of the documented form
(Newman 1984; the same form is in the NASGRO reference manual), and its
Pascal implementation is cross-checked against an independently written
Python implementation of the same remembered formula to 1e-9 relative
agreement. That confirms the two implementations agree with EACH
OTHER — it does **not** independently confirm the formula itself
matches what real published NASGRO material datasets assume, since both
implementations came from the same recollection. Before this closure
model is trusted for any real (especially certification-relevant) life
prediction, check it against the actual NASGRO reference manual or a
published worked example with known inputs and outputs.

### Everything else not yet built

- No crack-length integration loop yet (cycle-by-cycle or block-by-
  block accumulation of `da/dN` into a growth-vs-cycles history,
  stopping at a critical crack length or `Kmax=Kc`).
- No model file format yet for describing a crack-growth problem
  (geometry, material, loading) — needs designing once the K-solution
  layer's actual required inputs are known, following the same native
  key=value format conventions as the rest of this project.
- No CLI solver tool, no verbose output, no `fem_regress`-style
  regression cases yet — all follow once there's an actual problem this
  module can solve end to end.

## Closure-model edge cases (2026-10, external-review hardening)

- `NewmanClosureF` no longer raises for `R < -2`: the opening ratio is held
  at its `R = -2` value (`f = A0 - 2*A1`), so a spectrum with deep
  compressive excursions (ground-air-ground, gust, landing) integrates
  instead of aborting. **That branch is written from memory of the NASGRO
  documentation -- confirm it against the actual manual along with the rest
  of the closure form** (same open item as above).
- `NasgroRate`, `ConservativeRate` and `BestAvailableRate` return zero
  growth when `Kmax <= 0` (a fully compressive cycle never opens the
  crack). The K-solution/spectrum layer must still decide what `Kmax`
  means for a cycle that is compressive at the crack tip.
