# femsecedit — native section viewer/analyser

```
femsecedit [section.fgeo] [--screenshot out.png] [--size WxH]
```

Opens a FEM3DGEO section file, draws it, and shows all section properties.
It uses the same code as `femsection`, so the numbers are identical to the
command-line tool's `.prop` output.

| Action | How |
|---|---|
| Open a file | File > Open (Ctrl+O), or give the file on the command line |
| Reload | File > Reload (F5); also automatic, see below |
| Save the properties | File > Export .prop (Ctrl+E) — same file `femsection` writes |
| Zoom / pan | mouse wheel (about the cursor) / drag |
| Fit to window | View > Fit (F) |
| Grid, principal axes, bounding box | View menu (G toggles the grid) |
| Copy a property | select its row, Ctrl+C |

**Auto-reload.** With View > Auto-reload on (the default) the window reloads
whenever the file changes on disk, so you can edit the section elsewhere (the
web section editor's export, a text editor, a script) and watch the
properties update.

**Torsion constant J.** Everything except the numerical torsion constant is
computed immediately. J is solved a moment later and shows "solving..." until
it is ready.

**Problems with the file.** If the file cannot be read, or is not a usable
section, the reason is shown in the drawing area and the geometry
diagnostics (GEO codes) are listed in the panel below.

**Screenshots.** `--screenshot out.png` loads the file, saves a picture of
the window and exits; `--size 1400x900` sets the window size. Handy for
documentation.
