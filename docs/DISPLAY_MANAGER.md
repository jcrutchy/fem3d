
## v0.16 implementation boundary

`src/FEMDisplayManager.pas` is the first concrete implementation of this subsystem. It owns presentation-only hidden/isolated entity state. The renderer queries it before drawing elements and nodes. No display state is passed to the solver executables.

Current GUI operations:

- Hide / Show / Isolate by element type
- Hide / Show / Isolate by material
- Hide / Show / Isolate by section
- Hide / Show / Isolate by group
- Restore isolation
- Show All

The current implementation intentionally favours simple, auditable state transitions over a more complicated rule engine. Composable predicates, saved display states, selection-driven isolation and colour modes remain subsequent increments.

