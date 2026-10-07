# FEM3D native GUI modules — architecture and plan

Status: **first module built** (`femsecedit`, slice 1). This replaces the
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
  fem_sectiondoc.pas   one .fgeo loaded + validated + analysed, as femsection does
src/gui/<module>/    one folder per GUI module
  <module>.lpr / .lpi        program + Lazarus project (open this in Lazarus)
  <module>_main.pas / .lfm   main form (layout editable in the designer)
  <module>_view.pas          custom drawing control(s)
src/tools/patch_test/run_guicore_test.lpr   headless tests of the shared GUI units
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

Slice 1 (built): open a `.fgeo` (File > Open or on the command line); the
section is drawn with grid, axes, centroid and principal axes (wheel zooms
about the cursor, drag pans, F fits, G toggles the grid); a property table
shows all properties in groups (geometry, second moments, radii of gyration,
moduli, torsion, beam-property values), with the numerical torsion constant
J filled in a moment after the rest; geometry diagnostics (GEO codes) are
listed underneath; **File > Export .prop** writes exactly what `femsection`
would. **Auto-reload** (View menu, on by default) re-reads the file when it
changes on disk, so a section saved from the web section editor, a text
editor or another tool updates the properties immediately. Ctrl+C copies the
selected property row.

Slice 2 (next): drawing and editing tools (line, rectangle, circle, arc,
polygon, move/copy/delete), snaps, undo/redo, section presets with
parameters, writing `.fgeo` through the canonical writer. Design:

- an editable document model over `TFEMGeometryModel` in a common unit, with
  every edit a command object (do/undo), so undo/redo, a history list and a
  replayable log come for free and are unit-tested without a GUI;
- snapping and hit-testing in a common unit built on `fem_viewport2d`;
- live properties already work through `fem_sectiondoc`; the quick pass runs
  on every edit and the torsion solve is debounced (it moves to a worker
  thread if it ever feels slow on large sections).

Slice 3: compare against the Liberty catalogue (pick a designation, overlay,
show differences), batch/export helpers.

### 5.2 femgeoedit, femsetup

Same structure. `femgeoedit` reuses the viewport, snapping and command/undo
units from slice 2 and the geometry model and validator already in
`src/common`. 3D viewing would use `TOpenGLControl`; general solid modelling
remains out of scope (see `docs/cad_architecture.md`, section 8). `femsetup`
edits the load/constraint side and writes `.femref`, so models resolve and
solve through the existing CLI chain.

## 6. Testing

1. `run_guicore_test` (headless, Pascal): viewport maths, value formatting,
   the property rows against what `femsection` writes to a `.prop` (every key
   and value), the section document (load, quick/full pass, errors,
   diagnostics), and the no-LCL-in-common rule.
2. `femsecedit --screenshot` smoke test in `test.bat`: loads an example,
   draws the real window and checks a PNG was produced. This catches `.lfm`
   or form-wiring mistakes that a compile alone would not.
3. Visual checks: take `--screenshot` images when changing a layout.

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
3. Torsion-solve threading in `femsecedit` once editing makes it run often.
4. Whether to drop `.exe` from the CLI projects' target names for Linux.
