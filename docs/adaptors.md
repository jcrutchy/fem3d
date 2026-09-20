# Adaptors — bringing in other formats without compromising the solvers

## The rule

**Solvers only ever read the canonical model format** (JSON, as defined in
`model_format.md`), from a file or from stdin (`-`). That's it. A solver
never grows a flag for "oh also parse Strand7 files" -- that's exactly the
kind of scope creep that turns a small, auditable tool into another
monolith.

Every other ASCII format (Strand7 `.txt` exports, whatever comes next) is
handled by a separate **adaptor**: a small, standalone CLI program that
reads the foreign format and writes canonical JSON to stdout. Nothing
else. It doesn't validate engineering sense, doesn't solve anything,
doesn't know what a skyline matrix is.

```
adapt_strand7 old_job.txt > model.json
# or, piped straight into a solver:
adapt_strand7 old_job.txt | linstatic -
```

This is the same Unix pattern as the rest of the suite: small pieces,
each legible on its own, composed with pipes rather than fused into one
binary. It also means adding a new input format is purely additive --
it touches nothing in `src/common` or `src/solvers`.

## Adaptor responsibilities (and non-responsibilities)

An adaptor should:
- Parse its one source format.
- Map what it finds onto the canonical schema as faithfully as it can
  (units, node numbering, element types it recognizes).
- Emit clean JSON on stdout matching `model_format.md`.
- Exit non-zero with a clear stderr message if the source file uses a
  feature it doesn't yet support (element types, load types, etc.) --
  *refuse to silently drop or approximate something it can't represent.*
  A wrong model that runs is much more dangerous than a refusal.

An adaptor should *not*:
- Validate the resulting model beyond "did I produce syntactically valid
  JSON" -- that's `fem_validate`'s job, and it already runs inside every
  solver, so there's no need to duplicate it.
- Try to be a universal converter between arbitrary formats. One adaptor,
  one source format, one direction (foreign -> canonical).

## Suggested layout

```
src/adaptors/adapt_strand7/adapt_strand7.lpr
src/adaptors/adapt_<next-format>/...
```

Adaptors can share parsing helpers the same way solvers share
`fem_skyline` -- if a second adaptor needs, say, a generic fixed-width or
delimited-text tokenizer, that becomes a `src/common` unit rather than
being copy-pasted.

## Status

Not started, and low priority for now — the canonical JSON format itself
was the important part of this architecture, not any particular foreign
format. `adapt_strand7` would be the natural first one given your Strand7
background if/when you want another input format, but it's its own real
chunk of work (Strand7's `.txt` export isn't small) and separate from the
core suite.
