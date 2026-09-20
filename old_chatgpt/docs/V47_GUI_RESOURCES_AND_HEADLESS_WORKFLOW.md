# FEM3D v0.47 — GUI resources and headless workflow

## GUI resources

This increment restores Lazarus form resources that were omitted from the v0.46 full source package:

- `src/MainUnit.lfm`
- `src/FEMAnalysisManagerForm.lfm`
- `src/FEMAnalysisConfigForm.lfm`

The analysis manager/configuration forms are designer-managed. The main form now has an LFM resource as well; its existing `BuildUI` routine remains responsible for the current runtime layout so this resource restoration does not introduce a large unverified GUI rewrite in one step.

The next GUI increment can migrate the main shell's persistent controls from `BuildUI` into the designer resource in smaller, testable stages.

## Headless authoring

`examples/headless_cantilever.fem3d` demonstrates the intended workflow principle: a model file can be authored as plain text without using the GUI. It uses the **current v0.46 native parser syntax**, deliberately rather than pretending the future INI-style format has already been implemented.

A useful long-term contract is:

1. the native model format remains complete and deterministic;
2. the GUI is one authoring/editing client, not the authority;
3. command-line validation and solving operate directly on model files;
4. spreadsheet/macros/scripts can generate model files;
5. import/export adapters translate external formats at the boundary;
6. solver executables remain completely form-agnostic.

The native format will be versioned and improved separately from the GUI migration. Backward compatibility and explicit format validation should be part of that work.
