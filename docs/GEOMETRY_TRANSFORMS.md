# Geometry Transforms

v0.33 introduces explicit geometry transforms above the FEM model layer.

## Rotate

Rotate selected nodes about a user-specified origin and global X/Y/Z axis. A selection of elements is converted to its unique connected nodes before transformation, so shared topology is preserved.

## Mirror

Mirror selected nodes about a plane whose normal is aligned with global X, Y or Z. The supplied origin point lies on the mirror plane.

## Copy

Copy selected elements by a translation vector. Nodes referenced by multiple selected elements are duplicated once and remapped consistently, preserving connectivity inside the copied set. Element material, section, group, thickness and coordinate-system references are copied unchanged.

All three operations are model-editor commands and therefore form single undo/redo transactions. Existing analysis results are invalidated after model edits.

The current UI intentionally uses explicit numeric dialogs. Interactive transform handles, graphical pivots and preview are future viewport work; keeping the underlying operation explicit first makes the later graphical tools easier to validate.
