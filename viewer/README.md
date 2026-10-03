# FEM results viewer

A browser viewer for the FEM suite's results. **Plain HTML5, CSS3 and JavaScript — no
framework, no library, no build step, nothing to install.** Open `index.html`.

It is deliberately *dumb*: it displays what is in a **model file** (`.fem`) and in the
**solver's output** for it, and nothing else. It never solves, never edits, and it
refuses to draw results that do not belong to the model it was given (see
[Results must match the model](#results-must-match-the-model)).

## Using it

1. Open `index.html` in a browser (straight from disk is fine), then **Open…** and pick the
   model and the solver output together — or drop both on the page, or try an **Example**.
2. Produce the output with a solver: `linstatic model.fem > results.txt`
   (`linsparse` works too; or set `ResultsFile` in `[SOLVERPARAMS]`).
3. **Case** chooses a load case / combination; **Colour by** chooses what to contour.
   **Deformed** and the slider scale the displacements (the number beside it is the real
   magnification).
4. **Click an element** to see its forces and stresses in the side panel; click a node for
   its displacements, reactions and applied load.

Mouse: drag = orbit · right-drag or Shift-drag = pan · wheel = zoom. Keys (with the view
focused): `F` fit · `1`–`4` iso/top/front/side · `N` nodes · `M` node numbers · `E` element
numbers · `Esc` deselect. Touch: one finger orbits, two fingers pinch and pan.

The **Nodes**, **Node #** and **Elem #** buttons in the toolbar switch the node markers and the
number overlays on and off (nodes start on for models of up to 400 nodes, off for bigger ones, until
you choose for yourself). On a dense mesh the numbers that would overlap are left out and
fill in as you zoom; the number of the selected node or element is always shown.

### Why forces are in a panel and not drawn on the structure

Force diagrams drawn along members in a perspective view overlap and hide each other and are
hard to read. Instead, selecting an element puts its diagrams in the panel, in 2-D:

* **Beam** — N, Vy, Vz, T, My, Mz along the member (a toggle switches between the member's own
  axes — which are also its principal axes — and the global axes), the normal / von Mises /
  Tresca / torsional-shear stress along it, a **section view** at any station (drag the slider)
  showing the linear stress distribution, its four corner values and the neutral axis, and the
  station table (copy as CSV).
* **Shell** — a sketch of the element with the chosen quantity at the centre and corners, the
  force / moment tables, the stress tables for the top and bottom faces, **Mohr's circle** for
  each face and the stress through the thickness.
* **Truss** — axial force and stress.

The 3-D view contours the same quantities over the whole structure, and curved beams are drawn
with their real (cubic) deflected shape.

## Results must match the model

A solver prints `MODEL.FINGERPRINT=…` before its results: the SHA-256 of the model file's
canonical text (the rule is in `docs/native_format.md`; comments, blank lines, indentation and
line endings do not count). The viewer recomputes it from the model file it was given and
compares:

| | meaning | what you see |
|---|---|---|
| ✓ match | computed from exactly this model | results shown; green tick in the status bar |
| ✗ mismatch | the model has changed since the solve, or these are another model's results | red banner, **geometry only**; "Show the results anyway" is an explicit opt-in |
| ? not verified | results from an older solver with no fingerprint | amber notice, results shown |
| ✗ incompatible | structure disagrees (a node or element missing, an element of the wrong kind, wrong number of beam stations…) | as mismatch |

The structural checks run even when the fingerprint matches or is absent. The hash is computed
in plain JavaScript rather than with `crypto.subtle`, which browsers withhold from pages served
over plain `http` (for example from another machine).

## Files

| | |
|---|---|
| `index.html`, `css/viewer.css` | the page |
| `js/femparse.js` | reads `.fem` models and solver output |
| `js/femhash.js` | SHA-256 and the model fingerprint |
| `js/femcheck.js` | are these results for this model? |
| `js/femscene.js` | model + results → drawable geometry, colour fields, curved beams |
| `js/render3d.js` | Canvas 2-D renderer (painter's algorithm) and picking |
| `js/panels.js` | the element / node panel (inline SVG) |
| `js/app.js` | the only file that touches the page |
| `js/examples_data.js` | generated: the built-in examples (`node tools/embed_examples.js`) |
| `examples/` | models with the solver's real output |
| `test/` | tests (below) |

Everything except `app.js` is free of the DOM and runs under node, which is how it is tested.

## Serving it

Opening the file from disk needs nothing. Over `http` (for instance from vdrx) the page also
accepts `?model=URL&results=URL`, fetching both. Solving from the browser — posting a model to
a vdrx route that runs the solver and returns its output — is not built yet; the viewer would
need no change except a button.

## Tests

```
node test/run_tests.js                 # parsers, SHA-256 + fingerprint vs the Pascal solver's, the
                                       # results-vs-model checks, curved-beam shape vs beam theory,
                                       # drawing/picking, panels. Needs only node.
npm install --prefix /tmp/njs jsdom @napi-rs/canvas      # test-time only
node test/app_smoke.js /tmp/out        # the real page in jsdom: load, pick, toggle, refuse stale results
node test/render_png.js frame3d vm ultimate. /tmp/out/f.png
node test/render_panel.js plate_q8 12 "" /tmp/out/p.png  # draw a view / a panel to a PNG
```

`examples/*/results.txt` are real solver output; regenerate with
`linstatic examples/NAME/model.fem > examples/NAME/results.txt` then `node tools/embed_examples.js`.

## Not done

* Browsers other than what jsdom emulates have not been driven by a real user here: touch
  gestures, the wheel and window resizing are written but untested; the drawing and the page logic
  are tested.
* Painter's-algorithm ordering is per element, so intersecting shells can show the wrong overlap.
* Shell values are drawn per element (not averaged across neighbours), exactly as the solver
  reports them.
* JSON models and `modal` output are not read yet.
