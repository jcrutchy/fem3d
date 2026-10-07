# FEM3D geometry app ("cad") — web architecture (SUPERSEDED)

> **Superseded by `docs/gui_architecture.md`.** The graphical front ends are
> now native Lazarus modules; the web part is limited to the existing results
> viewer. This document is kept because several parts still apply: the
> geometry scope (section 8), the command/undo design (sections 6-7), the
> reserved constraint hooks (section 9), the UX notes (section 10) and the
> `femrun` gateway (section 4, `docs/femrun.md`), which remains available as an
> optional way for a web page to run the CLI tools. Sections about the web
> build, testing and milestones are no longer the plan.

## 1. Purpose and non-goals

A browser app for **creating and editing model geometry** (and later
attaching loads/constraints, driving meshing, and viewing results), whose
output is the files the rest of the suite already consumes: `.fgeo`
(`docs/FEM3DGEO.md`), `.femref` (`docs/femref.md`), and through
`femresolve`, a native `.fem`.

It is meant to feel familiar to people who know AutoCAD, Inventor or
SolidWorks, to be configurable where that is cheap, and to be built so a
new tool, entity type, importer or whole workbench can be bolted on later
without touching the core.

Non-goals (for now):

- A general B-rep solid modeller (booleans, fillets, shelling). See 8.
- Parametric/constraint-driven sketching. Hooks are reserved (9), the
  solver is not built.
- Replacing the command-line tools. The app is a front end to them.

## 2. Principles (inherited from the rest of the project)

1. **Zero third-party dependencies.** Vanilla JS, HTML5, CSS3 in the
   browser; FreePascal for CLIs. No frameworks, bundlers or npm packages.
2. **Text formats everywhere**, diffable and hashable. Nothing in the app's
   saved state is opaque.
3. **CLI first, UI dumb.** Anything that can be a stdin/stdout tool is one.
   The UI collects intent, shows results, and holds no authoritative logic
   that a CLI could hold instead (exception: interactive feedback, see 5).
4. **Swappable front ends.** The browser UI is one client of a headless core
   and a tool runner. A test page, a scripted harness, or a future Lazarus UI
   can drive the same pieces.
5. **Nothing is silently discarded** (the FEM3DGEO rule, extended): an
   operation that cannot honour its input reports an error with a code,
   never a quiet approximation.
6. **Deterministic output.** Canonical writers, stable ordering, so
   regression tests and SHA-256 staleness fingerprints keep working.
7. **Everything has a test**, headless, in the same style as `fem_regress`
   and `viewer/test`.

## 3. System overview

```
 +---------------------------- browser (one page) ---------------------------+
 |  UI layer      toolbar/ribbon, model tree, properties, command line,       |
 |                viewports (Canvas2D sketch, WebGL 3D), dialogs              |
 |       |  commands / events                                                 |
 |  Core (headless: no DOM, so a test page can drive it)                       |
 |     Document | Commands+History | Selection | Snap | Registry | Settings  |
 |     FGEO reader/writer/validator (JS)                                      |
 |       |  Runner interface:  run(tool, args, files) -> {exit,stdout,stderr} |
 +-------+-----------------------+----------------------+---------------------+
         |                       |                      |
   BridgeRunner            FolderRunner           MockRunner (tests)
   HTTP, same origin       File System Access     canned replies
         |                 API + manual steps           |
   vdrx cli_bridges                                     |
         |                                              |
     femrun.exe  ----->  femgeocheck, dxf2femgeo, fgeoop, femmesh,
     (whitelist)         femresolve, linstatic, modal, ... (existing + new)
```

The Core never talks to the DOM and never knows which Runner it has.

## 4. Can a browser run a CLI program?

Not directly, by design: a web page cannot launch executables. There are
two honest options (plus a test double), and the app should support them
all behind one `Runner` interface:

| Runner | How | Needs | Use |
|---|---|---|---|
| **BridgeRunner** | Page POSTs to `/fem/run/<tool>` on the same vdrx site that served it; `femrun` spawns the whitelisted CLI and returns stdout/stderr/exit code | vdrx + `femrun.exe` (**built**, `docs/femrun.md`) | The normal mode: validate, mesh, solve from the page |
| **FolderRunner** | Page reads/writes a user-chosen project folder via the File System Access API (Chromium); the user runs `run.bat` (or a watcher) between steps | nothing running | No-server fallback; also good for offline use |
| **MockRunner** | Returns canned replies recorded from the real tools | nothing | Browser-side tests of everything that consumes a Runner |

A fourth idea, a custom URL protocol handler (`fem3d://...`) that launches
an exe, is rejected: it is a security hole and awkward on every OS.
WebAssembly builds of the Pascal tools are a possible later replacement for
BridgeRunner (FPC's wasm target is not in 3.2.2), not a starting point.

### 4.1 Using vdrx for the bridge -- built

vdrx's `cli_bridges` with `"protocol": "bus"` spawns a program per request,
writes **one JSON request line** to its stdin
(`{"method","path","prefix","sub_path","query","headers","body"}`), and reads
**one JSON reply line** from stdout (`{"status","body"}`). **`femrun`**
(`src/tools/femrun`) is that program: it looks the tool name up in a
whitelist (`femrun.ini`), runs it with no shell and an argument array under
size/output/time limits, feeds the request body to its stdin, and returns
`{"tool","exit","stdout","stderr","truncated","ms"}`.

It is done and tested (31 checks in `run_femrun_test`, plus a manual
curl -> vdrx -> femrun -> femgeocheck run). Everything about its routes,
config, limits and security is in **`docs/femrun.md`**; it also solves the
viewer's open "solve from the browser through a vdrx route" TODO.

Two input modes are planned; only the first exists:

1. **Stream mode** (built): text in via stdin, text out via stdout. Covers
   `femgeocheck`, `dxf2femgeo`, `linstatic` and the rest of the suite, all
   of which already accept `-` for stdin.
2. **Workspace mode** (not built): for tools needing several files, e.g.
   `femresolve` with `db/liberty_db.json`. The page `PUT`s files by plain
   name (`[A-Za-z0-9._-]+`, no paths) into `sandbox/<session>/`, then runs a
   tool with that as its working directory. No client-supplied path ever
   reaches the filesystem.

Long jobs (meshing, large solves) need start/poll semantics:
`POST /fem/job/<tool>` returns an id, `GET /fem/job/<id>` returns status and
output so far. That rides on vdrx's `bus-daemon` flavour; until then long
jobs just use a long `TimeoutMs`.

### 4.2 Security of the bridge -- what was found

Checked against vdrx's source (not assumed):

- vdrx listens on **all interfaces** (`0.0.0.0`); there is no bind-address
  option and the request line does not carry the caller's address.
- vdrx does no Host/Origin checking. It does forward all request headers, so
  `femrun` does the checks (Host whitelist against DNS rebinding, Origin
  whitelist, and Origin-or-token on every POST).
- vdrx's per-site `cors` option sends `Access-Control-Allow-Origin: *`. It is
  off by default and **must stay off** for this site.

Consequences for the design:

- The app must be **served from the same vdrx site** that hosts the API
  (same origin, no CORS). A page opened from `file://` cannot call the
  bridge; that is what FolderRunner is for.
- Browser-based attacks are stopped by `femrun`. A *different machine* on
  the network can still reach the port and hand-craft a request, so the port
  needs a firewall rule (or a small vdrx change adding a per-site `bind`
  address, listed under open decisions) and, on shared networks, the token.
- Tools are whitelisted by name with exact-match flag lists; no shell; input,
  output and time limits; no client-supplied path ever reaches the filesystem.

### 4.3 FolderRunner details

`showDirectoryPicker()` gives read/write access to one project folder. The
app writes `model.fgeo`, `setup.femref`, etc. there and reads back
results. A `run.bat` in the folder (generated by the app, or shipped in the
repo) performs the CLI steps. It is slower and manual but needs no
processes and is a good test that the file formats really are the
interface.

## 5. Where logic lives (the rule that prevents duplicate bugs)

- **Authoritative = CLI.** Validation (`femgeocheck`), import (`dxf2femgeo`,
  later IGES/STEP), batch geometry ops (`fgeoop`), meshing (`femmesh`),
  resolve/solve. Their behaviour is defined by regression fixtures.
- **Interactive = JS.** Things that must respond at mouse speed: picking,
  snapping, rubber-band preview, camera, and the *construction* of simple
  sketch entities (line, arc, circle, polyline) and their basic edits
  (move, copy, rotate, mirror, trim, offset).
- **Any operation implemented on both sides must have a parity test**: the
  same input fixtures run through the JS implementation and the CLI, outputs
  compared via the canonical writer. If an operation has no parity test, it
  may exist on only one side.
- The JS `.fgeo` reader, writer and validator exist so the page can work
  offline and give instant feedback; `femgeocheck` stays the reference. The
  shared `tests/geometry/{good,borked}` fixtures run through both and must
  agree on accept/reject **and** on the GEO diagnostic codes.

## 6. The project (saved state)

A project is a **folder of text files**; nothing proprietary:

```
myplate/
  project.ini        names the files below, units, tolerance, tool versions
  model.fgeo         geometry (canonical writer output)
  recipe.fcmd        ordered, replayable edit history (see 6.1)
  setup.femref       loads, constraints, section/material references
  mesh.fem           generated by femmesh (derived, regenerable)
  results/           solver output, fingerprinted against mesh.fem
```

- `model.fgeo` is the source of truth for geometry; `recipe.fcmd` is the
  history that produced it (matches FEM3DGEO's non-destructive-recipe
  intent) and is what undo/redo and "replay from here" operate on.
- Derived files (`mesh.fem`, `results/`) carry a SHA-256 of their inputs,
  reusing the `MODEL.FINGERPRINT` idea: the app shows "stale" instead of
  silently displaying results for an edited model.
- `project.ini` records the units once. The app converts at the edge only;
  stored geometry is in one unit system, as FEM3DGEO already requires.

### 6.1 recipe.fcmd

One command per line, same style as `.fgeo` (keyword + numbers, `#`
comments), IDs explicit and stable:

```
# create a rectangle outline in sketch 1
SKETCH 1 PLANE xy ORIGIN 0 0 0
LINE 1 0 0  100 0
LINE 2 100 0  100 50
...
EXTRUDE 1 SKETCH 1 DIST 10
```

Each UI action is exactly one logged command (so undo = pop, redo = push,
"history" panel = the file). A headless `fgeoop recipe.fcmd > model.fgeo`
(or the JS core driven from a test page) can regenerate the geometry with
no UI at all.

## 7. Core architecture (JS)

### 7.1 Conventions

- Plain scripts, **UMD wrapper like `viewer/js/femmath.js`**
  (`root.X = factory()`), so every module loads with a `<script src>` tag --
  which works from `file://` and from vdrx alike -- and can also be loaded by
  a test page.
- One global namespace: `FEM3D.CAD`. No other globals.
- **One manifest, `cad/js/manifest.js`,** lists every script in dependency
  order as a plain array literal, one path per line. `index.html` and
  `test/index.html` each load it and inject the scripts with `document.write`
  (synchronous, so order is guaranteed, and fine under `file://`). The
  single-file bundler reads the same manifest, so there is exactly one list.
- A tiny FreePascal tool (`src/tools/jsbundle`) concatenates the manifest's
  scripts and the CSS into one `dist/cad.html`. No Node, no npm.
- No ES modules, no `import`, no `fetch` of local files; nothing that
  breaks under `file://`.
- The viewer's existing Node-based tests are left alone; the CAD app simply
  does not depend on Node.

### 7.2 Modules

```
cad/
  index.html
  css/cad.css
  js/
    core/
      ns.js            FEM3D.CAD namespace, version, module registration
      events.js        tiny event bus (on/off/emit), synchronous, ordered
      registry.js      generic registries: tools, entities, importers,
                       exporters, panels, keymaps, workbenches
      settings.js      load/save settings JSON (keymap, snaps, units, theme)
      document.js      the Document: entities by ID, sketches, groups,
                       units, dirty state, fingerprint
      commands.js      command objects: {name, params, do(doc), undo(doc),
                       serialize()}; the only way to change a Document
      history.js       undo/redo stack, recipe.fcmd read/write
      selection.js     selection sets, filters, window/crossing logic
      snap.js          snap engine (see 10.3), returns snap candidates
      units.js         parse/format lengths, angles; one internal unit
    geo/
      vec.js  mat.js   2D/3D vectors, transforms (shared with viewer where
                       practical)
      curves.js        line/arc/circle evaluation, intersection, closest
                       point, tangent, trim/offset primitives
      fgeo_io.js       .fgeo reader + canonical writer
      fgeo_check.js    validator mirroring GEO001-010
    run/
      runner.js        Runner interface + capability probe
      bridge_runner.js folder_runner.js mock_runner.js
    ui/
      app.js           wiring, workbench switching
      viewport2d.js    Canvas2D sketch view (pan/zoom, grid, snaps)
      viewport3d.js    WebGL view (raw GL, no libraries)
      camera.js        orbit/pan/zoom, mouse presets
      cmdline.js       AutoCAD-style command line + aliases + history
      ribbon.js tree.js props.js dialogs.js statusbar.js
    tools/             one file per tool; each registers itself
      line.js arc.js circle.js polyline.js move.js copy.js rotate.js
      mirror.js trim.js offset.js erase.js ...
    workbenches/
      geometry.js  mesh.js  loads.js  results.js    (later: mesh/loads/results)
```

### 7.3 Extension API (what "bolt-on" means)

A tool is a self-contained object registered at load time:

```js
FEM3D.CAD.registry.tool.add({
  id: 'line',
  aliases: ['L'],
  label: 'Line',
  icon: 'line',
  workbench: 'geometry',
  // a tiny state machine: each step says what input it expects
  steps: [
    { prompt: 'First point',  expect: 'point' },
    { prompt: 'Next point or [Undo]', expect: 'point', repeat: true }
  ],
  // called when the steps complete (or per repeat); returns Commands
  build: function (inputs, ctx) { return [ctx.cmd('LINE', {...})]; }
});
```

The same mechanism registers entity types (with their draw, snap-point,
serialize and validate functions), importers/exporters (`id`, file
extensions, `toFgeo(text)`), side panels, and keymap presets. Core code
never names a concrete tool; removing a script tag removes a feature.

Tools never mutate the Document: they return Commands, so undo/redo,
recipe logging and headless replay are automatic.

## 8. Geometry scope and the 3D question

FEA needs far less than a full CAD kernel:

| Model kind | Needs | Phase |
|---|---|---|
| Truss / frame | points, lines, section assignment | early |
| Plane stress/strain, plates | planar faces with holes, extrusion thickness | early |
| Shells | surfaces (planar first, then extruded/revolved) | middle |
| Solids (prismatic, axisymmetric) | extrude/revolve of closed profiles | middle |
| General solids | B-rep booleans, fillets, healing | **only if needed** |

General B-rep modelling from scratch with no dependencies is a multi-year
project by itself. The plan is to deliver a lot of value earlier by doing
sketch -> extrude/revolve -> surface/line models first, importing
complex solids from other CAD tools through STEP/IGES adaptors (still to be
written), and revisiting a kernel only when a real model demands it.
`cad/cad.htm` is treated as a **prototype to salvage ideas from** (command
aliases, snap logic, DXF export), not extended in place; it stays until the
new app overtakes it.

## 9. Reserved hooks for parametric sketching (not built)

- Sketch entities carry stable IDs; the recipe may later contain
  `CONSTRAIN <type> <id> <id> [value]` and `DIM <id> <value>` lines.
- Documents expose a `constraints` list that is empty and ignored for now.
- A later `sketchsolve` module (Newton/Levenberg-Marquardt over the entity
  parameters) would be a registered module, optionally a CLI as well.

## 10. UX specification

### 10.1 Layout

Top: workbench tabs (Geometry | Mesh | Loads & Constraints | Results) over a
ribbon/toolbar. Left: model tree (sketches, bodies, groups, sections,
loads). Centre: viewport(s). Right: properties panel for the selection.
Bottom: **command line** with history/prompt plus a status bar (coordinates,
snap/ortho/polar/grid toggles, units, bridge status indicator, stale-result
warning).

### 10.2 Familiar workflows

- **AutoCAD-style:** type or click a command (`L`, `C`, `A`, `PL`, `M`,
  `CO`, `RO`, `MI`, `TR`, `O`, `E`, `Z`, `U`...); prompts at the command
  line; Enter/Space repeats the last command; direct distance entry;
  `@dx,dy` relative and `<angle` polar input; window (left-to-right) vs
  crossing (right-to-left) selection; Esc cancels.
- **Inventor/SolidWorks-style:** pick a plane -> *Start sketch* -> draw ->
  *Finish sketch* -> *Extrude/Revolve*; the feature appears in the tree
  and can be edited (re-running the recipe from that point).
- Both share one engine; the difference is presentation and defaults.

### 10.3 Snaps and input aids

Endpoint, midpoint, centre, quadrant, intersection, perpendicular,
tangent, nearest, grid; ortho and polar tracking; snap markers and tooltips
as in AutoCAD. Snap candidates come from `core/snap.js`, so they work the
same in the 2D and 3D viewports.

### 10.4 Configurability

- **Keymap/alias presets** (AutoCAD, SolidWorks, Inventor) as data:

```json
{
  "preset": "autocad",
  "aliases": { "L": "line", "C": "circle", "TR": "trim" },
  "keys": { "F3": "toggle:osnap", "F8": "toggle:ortho", "Escape": "cancel" },
  "mouse3d": { "orbit": "middle+shift", "pan": "middle", "zoom": "wheel" }
}
```

- Settings (snap set, units, theme, grid, selection colours) live in one
  JSON file the user can edit or the app can write.
- Mouse presets for 3D navigation are separate from tool behaviour.
- Everything the UI can do is also reachable from the command line, which
  keeps keyboard-driven power users and scripts happy and makes the UI
  testable.

## 11. Testing (no Node)

1. **Browser test page** `cad/test/index.html`: loads the manifest's scripts
   plus a test script, runs every test, prints PASS/FAIL lines into the page
   and sets a final marker (`CAD-TESTS: ALL PASSED` or `FAILED`). Open it in
   a browser to see results; it needs no server.
2. **Headless run for `test.bat`:** Edge ships with Windows 11, so
   `msedge --headless --dump-dom file:///.../cad/test/index.html` prints the
   finished DOM and `test.bat` looks for the marker. If no browser is found
   the step is reported as **SKIPPED**, loudly -- never as a pass.
3. **Pascal produces the golden data.** A small tool (`genfixtures`) runs
   the real Pascal reader, canonical writer and validator over
   `tests/geometry` and writes `cad/test/fixtures_data.js` (same idea as the
   viewer's `examples_data.js`). The JS tests must reproduce those results:
   same accept/reject, same GEO codes, byte-identical canonical writes. That
   *is* the JS-vs-CLI parity test (5), with the CLI as the oracle and no
   process spawning needed at test time.
4. **Recipe replay:** `recipe.fcmd` -> `.fgeo` must equal the committed
   golden file (generated the same way once `fgeoop` exists).
5. **Runner tests:** the bridge side is already covered in Pascal
   (`run_femrun_test`). Browser-side code is tested against `MockRunner`
   with replies recorded from the real tools.
6. **UI smoke test only:** page loads, registries are populated, a scripted
   line command produces the expected entity.
7. Wired into `test.bat` like the other suites; `run.bat` stays one-click.

## 12. Open decisions

1. **Bridge host: DECIDED** -- vdrx + `femrun` (built). Still open: whether
   to add a per-site `bind` address option to vdrx (a few lines; closes the
   all-interfaces gap in 4.2) or rely on the firewall alone.
2. **Recipe interpreter:** JS (driven from the test page) or Pascal `fgeoop`
   as the headless replayer? Recommendation: both, with parity tests, once
   there is more than sketching to replay.
3. **Validator duplication:** keep a JS `fgeo_check.js` (instant feedback,
   offline) with parity tests (recommended), or call `femgeocheck` through
   the Runner only.
4. **Meshing:** which element types and algorithms first (2D triangle/
   quad meshing of faces with holes is the natural start; surface meshing
   for shells next). Lives in a Pascal CLI `femmesh`; not designed here.
5. **3D renderer:** raw WebGL (recommended) vs the software renderer in
   `viewer/js/render3d.js`. Can share camera/maths code either way.
6. **Where it lives in the repo:** extend `cad/` (replacing `cad.htm`
   when ready) vs new `app/`. Recommendation: `cad/`.
7. **Unit handling at the UI edge:** one stored unit per project with
   conversion on input/output (recommended), vs per-entity units.

## 13. Risks

- **Scope creep into a CAD kernel** — mitigated by section 8 and by
  treating STEP/IGES import as the route for complex solids.
- **Two implementations drifting apart** — mitigated by the authority rule
  and mandatory parity fixtures (5).
- **Localhost bridge as an attack surface** — mitigated by 4.2; treat any
  shortcut there as a bug.
- **Browser API variance** (File System Access is Chromium-only) — the
  BridgeRunner is the primary path; FolderRunner is a fallback, not a
  requirement.
- **Solo-developer time** — milestones below are ordered so each one leaves
  something useful and testable.

## 14. Milestones and acceptance tests

| # | Deliverable | Acceptance |
|---|---|---|
| M0 | Core skeleton: namespace, events, registry, Document, Commands, History; `fgeo_io.js`; manifest + test page; `genfixtures` | Test page green (also headless via `test.bat`): all `tests/geometry/good` fixtures read and re-written canonically, byte-identical to the Pascal writer's output; `index.html` loads with no console errors |
| M1 | `fgeo_check.js` validator + parity harness | Every `borked` fixture rejected with the same GEO code as `femgeocheck`; all `good` accepted |
| M2 | 2D viewport + sketch tools (line, arc, circle, polyline, erase, move, copy) with snaps, ortho, command line | A scripted session reproduces `tests/geometry/good/001_rectangle.fgeo`; `flange.dxf` imported (via `dxf2femgeo`) displays correctly |
| M3 | Runner interface; MockRunner; BridgeRunner (`femrun` + vdrx route are **already built**); FolderRunner | "Validate" button, served from the vdrx site, calls `femgeocheck` through the bridge and shows GEO diagnostics; gateway rejections already covered by `run_femrun_test` |
| M4 | Recipe log, undo/redo, project folder save/load, stale fingerprints | Save -> reload -> replay equals original `.fgeo`; editing the model marks results stale |
| M5 | Edit tools: rotate, mirror, trim, offset, array; DXF export | Golden-file tests per tool; round trip DXF -> fgeo -> DXF |
| M6 | 3D viewport (raw WebGL), orbit/pan/zoom presets, sketch planes, `fgeoop` extrude/revolve | An extruded plate with a hole checks clean (`femgeocheck`) and displays; JS/CLI parity on extrude |
| M7 | Loads & Constraints workbench: named groups, section/material assignment, `.femref` output | Output resolves via `femresolve` and solves; result equals an existing regression case's expected values |
| M8 | Mesh workbench (needs `femmesh`), then Results workbench (embed/reuse the viewer modules) | A meshed plate solves and displays; viewer rejects stale results |

M0-M2 deliver a usable 2D tool without any server; M3 makes it a real
front end for the CLI suite; M6 is the first genuinely 3D step and the
point to reassess how much solid modelling is really needed.

## 15. Immediate next steps

1. Settle the remaining open decisions in section 12 (the vdrx `bind`
   question, and items 2-3).
2. Create the `cad/` skeleton: `index.html`, `js/manifest.js`, `ns.js`,
   `events.js`, `registry.js`, `document.js`, `commands.js`, and
   `test/index.html`.
3. Write `genfixtures` (Pascal) and port the `.fgeo` reader/writer to JS;
   get M0's acceptance test green in the browser.
