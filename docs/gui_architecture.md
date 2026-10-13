# FEM3D native GUI modules — architecture and plan

Status: **first module built** (`femsecedit`: viewer, live properties, drawing tools, presets, undo/redo, save). This replaces the
web-first plan in `docs/cad_architecture.md`, which is kept only for the
material that still applies (geometry scope, command/undo design, `femrun`).

## 1. Decision

The suite's graphical front ends are **native Lazarus programs**, one small
executable per job, sitting on the same units and command-line tools as
everything else. The browser is used for **one thing only**: the existing
results viewer, which stays a self-contained, optional module that needs
nothing from the native side.

Why: the CLI tools already are the modular layer. A native GUI can call the
shared units directly (no bridge, no localhost server, no browser security
model, no second language), is tested in the same language and harness as the
rest, and keeps the zero-dependency, single-exe style. The web path cost a
gateway (`femrun`), a security analysis and Windows pipe work just to let a
page start a process.

`femrun` is finished and tested but is now **optional**: use it if you want a
page to trigger a solve; nothing in the native modules depends on it.

## 2. Principles

1. **Shared logic lives in `src/common`, which never uses the LCL.** A test
   enforces it (`run_guicore_test`: "no unit in src/common uses an LCL unit").
   So every shared unit works from the CLI tools and is testable headlessly.
2. **GUI modules are thin.** A module's own units hold windows and painting;
   anything worth testing (maths, document model, formatting) goes in a
   common unit with a test.
3. **Same code as the CLI.** The section editor computes with exactly the
   units `femsection` uses (through `fem_sectiondoc`), so the two cannot
   disagree.
4. **Text files are the interface** between modules (`.fgeo`, `.femref`,
   `.fem`, `.prop`). Modules are separate executables that read and write
   them; they never share memory.
5. **Designer-editable.** Window layouts are `.lfm` files, so they can be
   adjusted visually in the Lazarus designer. Custom-painted controls that
   are not registered components are created in code inside a placeholder
   panel (see the section editor).
6. **Every module has its own `.lpi`**, so any one of them opens directly in
   Lazarus and builds there.
7. **Nothing is silently dropped.** Files that fail to load or validate show
   the reason and the geometry diagnostics (GEO codes), never a blank window.

## 3. Layout

```
src/common/          shared units, no LCL
  fem_viewport2d.pas   world<->screen transform, pan, zoom-at-cursor, fit, grid step
  fem_proprows.pas     section properties -> display rows (checked against the .prop file)
  fem_sectiondoc.pas   one .fgeo (or an in-memory model) validated + analysed, as femsection does
  fem_sketch.pas       editable section sketch (lines, arcs, circles; solid/hole), edits,
                       undo/redo history, conversion to/from the FEM3DGEO model
  fem_snap2d.pas       snapping (vertex, centre, quadrant, midpoint, grid) and ortho
  fem_sectionpresets.pas  parametric shapes (rect, CHS, RHS, I/H, channel, angle, tee)
src/gui/<module>/    one folder per GUI module
  <module>.lpr / .lpi        program + Lazarus project (open this in Lazarus)
  <module>_main.pas / .lfm   main form (layout editable in the designer)
  <module>_view.pas          custom drawing control(s)
src/tools/patch_test/run_guicore_test.lpr    headless tests: view maths, property rows, section doc, no-LCL rule
src/tools/patch_test/run_sketch_test.lpr     headless tests: sketch model, snapping, presets
src/tools/patch_test/run_gui_script_test.lpr end-to-end: drives femsecedit with tests/gui/*.script
tests/gui/*.script                           scripted editing sessions with built-in assertions
```

`build.bat` builds every `.lpi` (so the GUI modules go to `bin\` with the CLI
tools); `test.bat` runs the GUI core tests and a GUI smoke test.

## 4. Conventions for a GUI module

- **Unit names:** `<module>_main` (form), `<module>_view` (drawing control).
  The form class is `T<Module>Form` with a global of the same name, so the
  `.lpr` is the standard `Application.CreateForm(...)`.
- **Event handlers** are published methods named after the component
  (`miOpenClick`, `TimerCalcTimer`) so the designer wires them.
- **Command line:** `module [file] [--screenshot out.png] [--size WxH]`.
  `--screenshot` loads the file, renders the window to a PNG and exits. It is
  used for the smoke test, for documentation images and for quick visual
  checks on any machine.
- **Output:** the executable goes to `bin/` with no extension in the `.lpi`
  (Lazarus adds `.exe` on Windows and nothing on Linux).
- **Units/paths:** the `.lpi` adds `..\..\common` to the unit path and uses
  `..\..\lib\$(TargetCPU)-$(TargetOS)` for compiled units.
- **Platforms:** Windows 64-bit is the primary target; the same project opens
  and builds on Linux (tested here with Lazarus 3.0 / GTK2 under a virtual
  display). Keep to LCL features present in Lazarus 2.2 (Debian stable) and
  later.
- **Manifest/theming on Windows:** the projects do not carry an application
  manifest yet. In Lazarus: Project > Project Options > Application > tick
  "Use manifest resource to enable themes" and save; then commit the `.lpi`.

## 5. Modules

| Module | State | Purpose |
|---|---|---|
| `femsecedit` | slice 1 built | Section viewer/analyser: loads a `.fgeo`, draws it, shows every section property live; later also the editor |
| `femgeoedit` | planned | 2D geometry/sketch editor on `.fgeo`; later 3D |
| `femsetup` | planned | Loads, constraints, section/material assignment -> `.femref` |
| results viewer | exists (web) | Stays a self-contained optional web module |
| `femrun` | done, optional | Lets a web page run whitelisted CLI tools |

### 5.1 femsecedit

Built (see `docs/femsecedit.md` for usage): open or draw a section, with
rectangle, polygon and circle tools, selection with move and corner-drag,
snapping, orthogonal mode, automatic hole detection, parametric shapes, undo and
redo, save as `.fgeo`, export `.prop`, auto-reload of the open file, live
properties and diagnostics, and a script mode for automated tests.

Design decisions worth knowing:

- **The sketch is the editable model, the FEM3DGEO model is derived from it.**
  `fem_sketch` holds closed profiles (a chain of line/three-point-arc segments,
  or a circle) flagged solid or hole. Each edit rebuilds the FEM3DGEO model
  (`SketchToGeo`), which then goes through the same validator, section builder
  and calculator as the CLI. A hole is assigned to the smallest solid containing
  it when the model is built, so the user never manages faces and loops.
- **Undo is snapshot-based**, not per-command do/undo objects: sketches are
  tiny, a deep copy per edit is cheap, and it removes a whole class of
  undo-inverse bugs. (`SketchCopy` is deliberate: dynamic arrays inside records
  are shared by plain assignment.) A drag is one history step.
- **Model coordinates are rounded to the 15 digits the file stores**
  (`Canon`), so the in-memory model is bit-identical to the same model saved
  and reloaded, and the editor and the CLI tessellate arcs identically.
- **Tools are driven through public methods** (`ClickAt`, `MoveCursorTo`,
  `ScriptDrag`...), which the mouse handlers call, so the scripts exercise the
  real code.
- The preset dialog is built in code because its fields depend on the shape.

Next: numeric entry for selected shapes (radius, corner coordinates), more
snaps (intersections, perpendicular), copy/mirror/array, arc segments drawn by
hand, and comparison against the Liberty catalogue.

### 5.2 femgeoedit, femsetup

Same structure. `femgeoedit` reuses the viewport, snapping and command/undo
units from slice 2 and the geometry model and validator already in
`src/common`. 3D viewing would use `TOpenGLControl`; general solid modelling
remains out of scope (see `docs/cad_architecture.md`, section 8). `femsetup`
edits the load/constraint side and writes `.femref`, so models resolve and
solve through the existing CLI chain.

## 6. Testing

1. `run_guicore_test` (headless): viewport maths, value formatting, the property
   rows against what `femsection` writes to a `.prop`, the section document,
   and the no-LCL-in-common rule.
2. `run_sketch_test` (headless, 148 checks): sketch to model conversion checked
   against closed-form properties; import/export round trips of the real
   example files (arcs included); undo/redo isolation; snapping; every preset
   against its closed-form area, inertia and centroid; refusal of impossible
   dimensions; and that the editor's model tessellates identically to the saved
   and reloaded one.
3. `run_gui_script_test` (end to end): runs `femsecedit` on each
   `tests/gui/*.script`. Scripts drive tools, snapping, undo, redo and mouse
   drags and carry their own `expect` assertions; the test then checks the saved
   files with `femgeocheck` and `femsection`, that the exported `.prop` equals
   `femsection`'s area, and that deliberately faulty scripts fail with exit code 3.
   It briefly opens windows. On Linux it needs `DISPLAY` and, on a headless
   machine, a window manager as well (Xvfb alone makes GTK2 spin its layout
   loop; Xvfb + openbox works). Without `DISPLAY` it reports SKIPPED.
4. Visual checks: `--screenshot` images when changing a layout.

## 7. Build and run

Windows: `build.bat` (all projects) or open
`src\gui\femsecedit\femsecedit.lpi` in Lazarus. Linux: install Lazarus
(`lazarus` package), open the same `.lpi`, build. The CLI tools' `.lpi` files
name their output `*.exe`; on Linux that produces files with an `.exe`
suffix. Removing the `.exe` from their target names fixes that without
affecting Windows builds.

## 8. Open decisions

1. Application manifest/theming for the Windows builds (section 4).
2. Whether `femsetup` and `femgeoedit` are one program or two.
3. Torsion-solve threading in `femsecedit` for very large sections (it is
   debounced on the main thread today and has been instant on every section tried).
4. Whether to drop `.exe` from the CLI projects' target names for Linux.
5. Whether the section builder's arc subdivision should be made robust at exact
   multiples of its step (`Ceil(sweep/step)` flips by one piece; effect ~1e-8,
   but changing it would alter committed regression numbers).
