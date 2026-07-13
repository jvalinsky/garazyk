---
title: Embedded Runtime and Deferred Products
status: active
last_verified: 2026-07-12
---

# Embedded Runtime and Deferred Products

## E1. Rebuild the WASM capability baseline

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

## E3. Decide incomplete product surfaces

The source tree advertises or exposes incomplete behavior:

- SMTP delivery always fails;
- cloud blob copy/delete paths return 501;
- STAR reconstruction from CAR blocks is incomplete;
- Skylab has incomplete repost and Germ E2EE integration;
- some scenario-dashboard process metadata remains a TODO.

For each surface choose support, explicit experimental status, or removal.
Implementation plans require a user-visible contract, owner, and integration
test. Configuration must not promise a feature that always returns
`NotImplemented`.

## E4. Deferred AppView pooling

ADR 0002 remains authoritative. Revisit pooling only after:

- numbered migration safety is complete;
- concurrent read/write characterization exists;
- production measurements show serialized access is a bottleneck;
- rollback can restore the serial manager without schema changes.
