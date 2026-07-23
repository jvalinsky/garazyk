---
title: Embedded Runtime and Deferred Products
status: active
last_verified: 2026-07-22
---

# Embedded Runtime and Deferred Products

## E1. Rebuild the WASM capability baseline — baseline complete (2026-07-22); subset choice open

**Items 1-5 complete (2026-07-22, phase 10 slice 2).**
`objc-jupyter-wasm/scripts/run-capability-baseline.sh` rejects a dirty
checkout, builds `kernel-wasm` twice, runs the smoke/runtime/notebook/
compatibility probes from one command, and regenerates the capability matrix
from test results (91/91 runtime probes, 22 demo notebooks with 138/152
executed cells and 14 explicit skips, 18/18 compatibility cases, passing
Chromium worker smoke). `kernel/PARSER_STATUS.md` and
`docs/runtime-gap-report.md` redirect to the generated matrix, so no
contradictory hand-maintained tables remain.

**Subset decided (2026-07-23, ADR 0010; operator delegated the
checkpoint).** The next supported subset is the two notebook-relevant
language gaps plus a parser-termination invariant: fix the `->`
infinite-loop hang and support `->` member access; support top-level C
function definitions with value-typed parameters; `@encode` and
`@synchronized` become intentionally unsupported with clean diagnostics
(consistent with the snippet policy's threading exclusion). The compiled
Emscripten cell plane and Jupyter UX features stay deferred. Acceptance:
the four skipped cases in `tests/test-runtime-gap-probes.mjs` become
active probes, the baseline runner regenerates the matrix, and the
notebooks plus compatibility corpus stay green. The implementation lane
is unscheduled P2 work; nothing else blocks on it.

The historical runtime plans say phases D-G are complete. The runtime feature
review and gap report still list loop, super-dispatch, protocol, and Foundation
failures, while `kernel/PARSER_STATUS.md` says 91 probes pass. No built kernel
artifact was present during this review.

1. Make the kernel build reproducible from a clean checkout.
2. Run smoke, notebook, compatibility, and runtime-gap probes from one command.
3. Generate one capability matrix from test results.
4. Keep supported, partial, stub, intentionally unsupported, and missing states
   distinct.
5. Delete or redirect contradictory hand-maintained status tables.

Only then choose the next subset. Favor language behavior required by the
notebooks and Garazyk compatibility corpus over broad Foundation imitation.

Rollback: new features remain behind probe fixtures. Revert one parser/runtime
slice without changing the capability generator.

## E2. TUI and capture ownership

The TUI corpus, semantic overlay, replay, and agent CLI plans have been
implemented. Their next work belongs in `garazyk-tui` or
`garazyk-atproto-testing` after the repository split. Garazyk keeps only the
compatibility smoke required by server development.

Do not reopen the completed 200-app corpus plan in this repository.

## E3. Decide incomplete product surfaces — complete, with one correction (2026-07-22)

The operator approved all six dispositions recommended in
[the Phase 10 product-surface decision brief](../phase-10-product-surface-decision-brief.md).
Five are implemented:

- SMTP delivery removed (`PDSEmailProviderFactory` now rejects `smtp`; use `resend` or `mock`).
- S3-compatible blob storage config now fails closed instead of silently not taking effect
  (`PDSBlobProviderFactory` rejects `"s3"`; `PDSCloudStorageBlobProvider` itself is left in place).
- Skylab repost button (non-functional, "coming soon") removed.
- Skylab Germ E2EE selector removed — it announced encryption but silently fell back to plaintext.
- Scenario-dashboard health checks now use the active run's resource manifest
  (`hostUrl`/`healthPath`) when available, falling back to the prior role-name heuristic.

The sixth — CAR→STAR reconstruction / public STAR negotiation — was **not** removed. Implementing
that disposition surfaced that the brief's evidence was stale: the flagged lossy converter
(`STARConverter.starL0DataFromCARData:`) has zero production callers, while the actual negotiated
public sync export path (`PDSRepositoryService.repoContentsSTARL0ChunkProducer:`) uses a separate,
correct `STARL0Writer` that genuinely walks the live MST. See the brief's "Correction: STAR
disposition not executed" section for the full evidence trail. STAR negotiation is unchanged and
remains supported.

## E4. Deferred AppView pooling

ADR 0002 remains authoritative. Revisit pooling only after:

- numbered migration safety is complete;
- concurrent read/write characterization exists;
- production measurements show serialized access is a bottleneck;
- rollback can restore the serial manager without schema changes.
