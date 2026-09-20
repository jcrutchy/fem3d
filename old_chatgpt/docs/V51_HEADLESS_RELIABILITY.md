# v0.51 — Headless reliability hardening

This increment hardens the public CLI/model/result boundary and the regression harness.

## Model parser

The native FEM3D reader now:

- requires a valid `FEM3D <version>` header;
- reports source line numbers for parse errors;
- rejects malformed integers and floating-point values;
- rejects NaN and infinity;
- rejects duplicate node/material/section/group/load-case/load/element/analysis identifiers;
- rejects unknown model records and sections;
- rejects malformed analysis-case syntax;
- rejects unknown linear-static settings;
- rejects invalid persisted matrix-storage values;
- rejects invalid persisted numeric and boolean settings;
- detects unterminated analysis cases;
- permits forward references where semantic validation can safely handle them.

Semantic checks remain in `FEMValidation` rather than being mixed into lexical parsing.

## Result parser

`.fem3dres` files are parsed strictly. Missing status, malformed numbers, non-finite values, invalid vector indices, duplicate vector indices, inconsistent DOF counts, unknown sections and unknown top-level properties are rejected.

Sparse expected-result files remain supported: omitted vector entries mean zero for regression comparison.

## Regression harness

`FEM3D_TestRunner.exe` runs the public process boundary:

1. CLI `validate`;
2. CLI `solve`;
3. CLI `results`;
4. complete displacement/reaction numerical comparison.

Child processes have a finite ten-minute timeout.

The runner also executes the invalid model and invalid result corpora and the command-line contract checks.

## Verified corpus policy

Verified cases are frozen by `tests/verified/VERIFIED.INDEX`. The index currently uses FNV-1a-64 fingerprints as accidental-change evidence; it is not a cryptographic signature. Source control remains the authoritative history and review mechanism.

A changed verified case must be independently rechecked and explicitly re-frozen.
