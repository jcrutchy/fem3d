FEM3D numerical solvers
=======================

Solvers are deliberately independent command-line executables.

Contract
--------

FEM3D_LinStatic.exe receives exactly one argument:

  FEM3D_LinStatic.exe model.fem3d

All solver parameters are read from the selected Linear Static analysis case
inside the model. The result is written beside the model as model.fem3dres.

There is no GUI, LCL, OpenGL, plugin or web code in the solver.
