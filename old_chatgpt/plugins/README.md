# FEM3D Solver UI Plugin Boundary

The long-term GUI/plugin boundary is intended for Windows x64 and Lazarus/FreePascal. Solver-specific UI should be loadable independently of the numerical solver executable.

The plugin owns:

- solver name/version/capabilities presented to the user;
- analysis-specific settings pages;
- settings validation;
- conversion of UI state to the persisted FEM3D analysis-definition text.

The plugin must **not** own the numerical solver. The numerical solver remains a separate EXE launched by FEM3D or directly from a command line.

## ABI direction

For the eventual DLL ABI, prefer a small C-compatible exported interface rather than passing Lazarus classes or strings across the DLL boundary. This keeps the plugin contract less sensitive to compiler/package/runtime changes.

The first implementation will remain built into FEM3D while the interface is stabilised. A DLL loader should only be added once the analysis-definition format and plugin ABI have enough test coverage to make the boundary worthwhile.
