# v0.48 Headless Contract

The FEM3D model file is an engineering interface, not a GUI-private serialization format.

A valid model may be authored by:

- the FEM3D GUI;
- a text editor;
- Excel/VBA or another spreadsheet automation system;
- an external preprocessor;
- a future web client;
- another FEA package through an import adapter.

The solver receives only the model filename. Solver settings belong to the analysis case persisted in that model.

The headless CLI provides validation, model inspection, result inspection and solver orchestration without LCL, Forms or OpenGL dependencies.

This is deliberately separate from the numerical solver executable. `FEM3D_LinStatic.exe` remains a CLI-only numerical process.

## Important boundary

The GUI may make authoring convenient, but it must never become authoritative over engineering data. The model file and result file remain the durable interchange and audit boundary.
