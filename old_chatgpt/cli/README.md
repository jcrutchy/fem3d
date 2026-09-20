# FEM3D headless command line client

`FEM3D_CLI.exe` is GUI-independent orchestration around the same model, validation and result contracts used by the desktop application.

Commands:

```text
FEM3D_CLI.exe validate model.fem3d
FEM3D_CLI.exe info model.fem3d
FEM3D_CLI.exe results result.fem3dres
FEM3D_CLI.exe solve model.fem3d
```

The `solve` command launches `FEM3D_LinStatic.exe` with exactly one argument: the model filename. The solver itself does not know that this CLI client, the Lazarus GUI, Excel, Notepad or any other producer exists.

The client searches for the solver beside itself and then in a `solver` subdirectory.

Build with Lazarus/FPC using `../src` as a unit search path.

## Verification

`FEM3D_CLI.exe verify` runs the native Pascal core verification set. The Windows `smoke_headless.bat` script builds and exercises the complete headless path.
