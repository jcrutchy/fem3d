# `.femref` and `femresolve` — models that refer to data kept elsewhere

## Why

A real model reuses data that already exists somewhere else: a catalogue
section (`150 UC 30.0`), a section file `femsection` wrote, eventually a
materials library. Copying the numbers into the model by hand is error-prone;
letting a solver read the other file would let the answer change when that file
changes, with no trace in the model.

So the two jobs are kept apart, following the rule in `docs/adaptors.md`:

```
model.femref  --femresolve-->  model.fem  --linstatic-->  results
 (references)                 (every number inside)
```

- A **`.femref`** is what an editor saves. It may contain references.
- **`femresolve`** is an adaptor. It copies every referenced value into the
  model and writes a plain native `.fem`. It does not validate engineering
  sense (the solver's `fem_validate` does that).
- **Solvers never read references.** A `.femref` handed straight to a solver
  stops at `[REFERENCES]` with "unknown section", which is the point.

Because the numbers are in the `.fem`, `MODEL.FINGERPRINT` covers them: if the
catalogue changes, resolving again gives a different model with a different
fingerprint, and old results are recognised as stale.

```
femresolve model.femref > model.fem
femresolve model.femref | linstatic -
```

## Syntax

A `.femref` is a `.fem` file (`docs/native_format.md`) with one extra section
and one extra field form. A file with no references is a valid `.femref`, and
resolving it changes nothing but adds comment lines.

```
[REFERENCES]
# name, kind, source[, designation]
col,   section, liberty_db.json, 200 UB 25.4
brace, section, brace.prop

[PROPERTIES]
# id, type, material, @name
1, beam,  1, @col
2, truss, 1, @brace
```

- **`[REFERENCES]`** rows are `name, kind, source` and, for a catalogue,
  a fourth field `designation`. `name` may use letters, digits, `_`, `-`, `.`
  and is case-insensitive. At most one `[REFERENCES]` section; it is removed
  from the output.
- **`kind`** is `section` today. `material` is reserved for a future materials
  library and is refused with a clear message until it exists.
- **`source`** is a path, relative to the folder of the `.femref` (or to
  `--base`), or absolute. By extension:
  - `.prop` — a section file written by `femsection`. No designation.
  - `.json` — a section catalogue such as `prop/liberty_db.json`; the
    designation picks the entry.
- **Using a reference.** Only as the **fourth field of a `[PROPERTIES]` row**,
  written `@name`. The row must be exactly `id, type, material, @name`.
  - `beam` receives `area, Iy, Iz, J, Cy, Cz, Rt`.
  - `truss` receives `area`.
  - Any other type (a shell) is refused: a section does not give a thickness.
  A `@` anywhere else is an error, never passed through.
- **Comments** (`#` or `;` at the start of a line) are copied through.

## What a section reference returns

- **`.prop` file** — the numbers on its `Property=` line, which `femsection`
  writes about the section's principal axes. Any rotation note above that line
  is copied into the output as a comment.
- **Catalogue entry** — the outline is built from the entry's printed
  dimensions (`d, bf, tf, tw, r1`, depth along local y) and the properties are
  *computed* by the same code as `femsection` (`fem_section_db` +
  `fem_section_calc`), so `Cy`, `Cz`, `Rt` and `J` are available, not only the
  catalogue's printed `A`, `Ix`, `Iy`. They agree with the printed catalogue to
  about 1% (J to 2.5% for I-sections, 6% for channels, whose printed J uses a
  different method) — see "Tests" below.

Buildable today: universal beams, universal columns, universal bearing piles,
parallel flange channels. **Refused, with the reason:** tapered flange beams
(the catalogue does not record the flange slope) and angles (it gives no root
or toe radii). Nothing is guessed.

Matching a designation ignores case, spaces and a trailing `.0`, so
`200 UB 25.4`, `200ub25.4` and `150 UC 30` (for `150 UC 30.0`) all work. An
unknown designation lists nearby entries.

## Units

Section data has its own length unit (`mm` for the catalogue, `LengthUnit=` in
a `.prop`). The model's length unit is read from `[HEADER] Units=`: it must
name exactly one of `mm, cm, m, in, ft` as a word (`SI (N, m, Pa, rad)` →
`m`; `N, mm, MPa` → `mm`). If it does not, pass `--length-unit` or fix the
header; femresolve never guesses. Areas are scaled by the square of the ratio,
`Iy, Iz, J` by the fourth power, `Cy, Cz, Rt` by the first.

## Output and provenance

The output starts with comment lines naming the `.femref` and the SHA-256 of
each referenced file, and each expanded row is preceded by a comment saying
what it came from and what conversion was applied. Comments are ignored by the
fingerprint, so provenance is auditable without making the fingerprint depend
on file names. Output is deterministic: the same inputs give identical text.

## Options and exit codes

```
femresolve <model.femref | -> [--base DIR] [--length-unit mm|cm|m|in|ft]
```

`--base DIR` sets the folder relative sources are taken from (default: the
folder of the input file, or the current folder for stdin).

| Code | Meaning |
|---|---|
| 0 | resolved; warnings (for example an unused reference) go to stderr |
| 1 | a reference could not be resolved — message starts with the line number |
| 2 | usage error |
| 3 | the input could not be read |

Every failure is a hard error with no output used: an undefined or duplicate
reference, an unknown or unsupported designation, a missing or invalid source,
a reference in the wrong place or with the wrong number of fields, an unreadable
length unit, a catalogue with unexpected units. There is no fallback to a
default.

## Tests

`run_resolve_test` (wired into `test_all`) has three groups:

1. **Catalogue.** Every buildable entry of `prop/liberty_db.json` is rebuilt and
   compared with the catalogue's printed `Ag, Ix, Iy, Zx, Sx, Zy, Sy, J` (and
   `XL` for channels). `prop/tests/liberty/manifest.ini` pins the SHA-256 of
   the database and of the manifest itself (the same rule `fem_regress` uses),
   the expected counts, and the tolerances. Editing the database or loosening a
   tolerance fails the run until you re-verify and run
   `run_resolve_test --update-hashes`.
2. **Resolver.** Values and units, designation matching, `.prop` sources,
   determinism, comment-only provenance, and each refusal above.
3. **Committed model.** `tests/regression/036_beam_liberty_section/model.fem`
   must equal what its `model.femref` resolves to now; `fem_regress` then checks
   the solver's answer for it against a closed form.

## Not done yet

- Material references (`kind = material`).
- A model editor that writes `.femref`.
- Catalogue values as an alternative to computed ones (useful for angles).
