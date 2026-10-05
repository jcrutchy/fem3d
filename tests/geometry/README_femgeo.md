# Geometry regression fixtures

`good/` contains geometry that the checker should accept.
`borked/` contains deliberately invalid `.fgeo` files that the checker must reject.

The existing `fem_regress` harness is solver-oriented, so the intended next
small change is a geometry-case mode using the same manifest/hash conventions:
`Status=VERIFIED|BORKED`, `Input=...`, `ExpectedExitCode=...`, and optional
`ExpectedErrorContains=...`.
