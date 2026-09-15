FEM3D test models v1
====================

These are deliberately small models intended to exercise the complete current
workflow: open/import -> inspect constraints -> inspect/assign properties ->
loads -> linear static solve -> load results -> deformed/contour/result viewing.

1. Cantilever_Beam.fem3d
   - One BEAM3D, fixed at node 1.
   - 1000 N downward Y load at node 2.
   - Aluminium material and rectangular section.
   - Useful for checking constraints, load direction, beam properties,
     displacement, reaction and recovered end forces.
   - Approximate analytical tip displacement in Y:
       delta = P L^3 / (3 E Iz)
     = -0.0238095238 m for the supplied properties.

2. Portal_Frame.fem3d
   - Four nodes, two fixed bases, two columns and a top beam.
   - 5000 N horizontal X load at node 3.
   - Uses two sections so property inspection/reassignment can be exercised.
   - Good for multi-element selection, property assignment, reactions,
     deformed shape and member-force result diagrams.

3. Airframe_Stick.fem3d
   - Small two-stringer/three-bay stick idealisation.
   - Two different sections and multiple groups.
   - Downward resultant split between the two free-end nodes.
   - Useful for selection/filtering, group display, property assignment,
     result inspection and basic airframe-style model navigation.

4. Import_Stick_Model.dxf
   - Tiny DXF wireframe matching the basic portal/frame geometry.
   - Intended to exercise the current DXF wireframe importer before assigning
     FEM properties and constraints.

Suggested play sequence
-----------------------
A. Open Cantilever_Beam.fem3d.
B. Inspect node 1 restraints and node 2 load.
C. Inspect the beam material/section.
D. Solve linear static case 1.
E. Load the generated results.
F. Try deformed shape, displacement contour, node/element picking and
   recovered beam forces.
G. Change the section or material, solve again, and compare results.
H. Try assigning properties to the Portal_Frame selection and undo/redo.
I. Import Import_Stick_Model.dxf, assign properties, add restraints/loads,
   and solve after completing the model.

These models are development exercises, not certification allowables or
production aerospace substantiation models.
