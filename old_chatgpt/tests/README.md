# FEM3D test and verification suite

FEM3D uses native FreePascal test programs and does not require Python or an external numerical library.

## Test layers

- `verify.exe` — in-process mathematical/formulation verification.
- `HeadlessContract.exe` — native model persistence/contract checks.
- `FEM3D_TestRunner.exe` — external end-to-end CLI regression harness.
- `verified/` — manually verified engineering benchmark corpus.
- `invalid/` — deliberately malformed/invalid input corpus.

The end-to-end runner invokes the actual `FEM3D_CLI.exe validate` and `FEM3D_CLI.exe solve` commands. It therefore exercises the same process boundary used by automation and production headless workflows.

## Normal regression run

Run:

    FEM3D_TestRunner.exe

A non-zero exit code means at least one regression failed.

## Freezing a verified corpus change

After independently reviewing and re-verifying a new or changed golden case:

    FEM3D_TestRunner.exe --freeze-verified

This updates `verified/VERIFIED.INDEX`. The normal runner never updates the index automatically.


## Invalid-result corpus

`invalid_results/` contains malformed `.fem3dres` files. These are exercised through `FEM3D_CLI.exe results`, ensuring result-file corruption is rejected at the same public boundary used by automation.
