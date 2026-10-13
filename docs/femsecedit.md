# femsecedit — native section editor and analyser

```
femsecedit [section.fgeo] [--script file] [--screenshot out.png] [--size WxH]
```

Draw a cross-section or open a `.fgeo`; every section property updates as you
edit. The numbers come from the same code as the `femsection` command-line
tool, and the files it saves are ordinary `.fgeo` files (written by the same
canonical writer and accepted by `femgeocheck`).

## Drawing

| Tool | Key | How |
|---|---|---|
| Select | Esc | click a shape; drag it to move it; drag a square corner handle to move a corner |
| Rectangle | R | click two opposite corners |
| Polygon | P | click the corners; Enter or a click on the first point closes it; Backspace removes the last point |
| Circle | C | click the centre, then a point on the circle |

- A shape drawn **inside a solid** becomes a **hole**; drawn inside a hole it is
  solid again (an island), and so on. **H** (or the Hole button) toggles the
  selected shape between solid and hole.
- **Delete** removes the selected shape. **Ctrl+Z / Ctrl+Y** undo and redo (a
  whole drag is one undo step).
- **Snapping** (View menu): to vertices, circle centres and quadrant points,
  segment midpoints, and optionally to the grid. **O** toggles orthogonal
  drawing (lines stay horizontal or vertical). A marker shows what you will
  snap to.
- **Shapes menu**: rectangle, circular and rectangular hollow sections,
  I/H beam with root fillets, parallel-flange channel, angle, tee. Each asks
  for its dimensions (in the current units) and refuses impossible ones with a
  message. If something is already drawn you choose Replace or Add alongside.
- **Units** (View menu): mm, cm, m, in. This only changes the unit label the
  file carries; it does not rescale the drawing.

## Properties and diagnostics

The panel on the right lists every property in groups (geometry, second
moments, radii of gyration, moduli, torsion, beam-property values). Everything
except the numerical torsion constant J updates immediately; J is solved a
moment after the last edit and reads "solving..." until then. Ctrl+C copies the
selected row. Below the drawing, the geometry diagnostics (GEO codes) are listed,
including a warning for any hole that lies outside every solid (it would be
left out of the saved file).

## Files

| Action | How |
|---|---|
| New | Ctrl+N |
| Open | Ctrl+O, or give the file on the command line |
| Save / Save as | Ctrl+S / Ctrl+Shift+S: writes the `.fgeo` |
| Export properties | Ctrl+E: writes the `.prop` exactly as `femsection` would |
| Reload | F5 |

Opening a file imports its faces as editable shapes (lines, three-point arcs
and circles; planar faces parallel to XY). A file that cannot be edited (other
curve types, faces not in the XY plane) is shown **read-only** with the
reason; you can still read its properties.

**Auto-reload** (View menu, on by default) re-reads the file when it changes on
disk, so edits made elsewhere (a text editor, the web section editor's export)
appear immediately. It is paused while you have unsaved changes.

## Scripts and screenshots

`--screenshot out.png` loads the file, saves a picture of the window and exits;
`--size 1400x900` sets the window size. `--script file` runs a list of commands
first, through the same code the mouse uses; a failed command or `expect` stops
the program with exit code 3 and a message on stderr. This is how the editor is
tested (`tests/gui/*.script`, run by `run_gui_script_test`).

```
# comments start with #; a token starting with $ is an environment variable
new [unit]                 open PATH          save PATH       export PATH
unit mm|cm|m|in            fit
tool select|rect|polygon|circle
click X Y                  move X Y           drag X0 Y0 X1 Y1
finish                     cancel             undo            redo
delete                     hole               select N        (1-based)
snap objects|grid|both|none                   ortho on|off
preset ID v1 v2 ...        (rect, chs, rhs, ibeam, channel, angle, tee)
expect profiles N          expect area VALUE [REL]
expect dirty yes|no        expect selected N
```

## Notes

- Values the editor shows are computed from the model rounded to the 15
  significant digits the `.fgeo` file stores, so what you see equals what the
  command-line tools compute from the file you save. For an older file written
  with more digits, the first reading can differ from the command-line tools'
  reading of the original by about 1e-8 (the section builder splits an arc into
  a whole number of pieces, which can flip by one piece at an exact multiple).
- The program needs a window manager only for the automated tests on a headless
  Linux machine (see `docs/gui_architecture.md`); normal desktop use has none of
  that to worry about.
