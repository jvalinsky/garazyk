# Objective-C interpreter status

The current, test-generated support boundary is in
[the capability matrix](../docs/capability-matrix.md). Run
`bash objc-jupyter-wasm/scripts/run-capability-baseline.sh` to rebuild its evidence.

This file deliberately no longer carries a hand-maintained feature matrix or pass counts. Those
tables diverged from the runnable probes and notebooks, creating contradictory backlog claims.

The interpreter remains a constrained runtime for the validated smoke slice. It is not a substitute
for the planned Emscripten compiled-cell plane, full GNUstep Foundation, or general production
Objective-C execution.
