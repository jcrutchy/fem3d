# Verified regression corpus

Each subdirectory is a deliberately small engineering benchmark. It contains:

- `model.fem3d` — the exact model supplied to the current CLI pipeline.
- `expected.fem3dres` — a manually derived reference result containing the quantities that must remain correct.
- `manifest.ini` — case name and comparison tolerance.

`VERIFIED.INDEX` records FNV-1a-64 fingerprints of all three files. The normal regression runner refuses to run a changed verified case until it has been explicitly re-frozen.

## Adding a verified case

1. Create a new directory under `tests/verified/`.
2. Add `model.fem3d`, `expected.fem3dres` and `manifest.ini`.
3. Independently hand-calculate the expected result and review the model/result files.
4. Run `FEM3D_TestRunner.exe --freeze-verified` to record the new fingerprints.
5. Commit the case and updated `VERIFIED.INDEX` to source control.

The index is intended as accidental-change/tamper evidence, not as a cryptographic signature. Git history remains the authoritative review trail for changes to the verified corpus.
