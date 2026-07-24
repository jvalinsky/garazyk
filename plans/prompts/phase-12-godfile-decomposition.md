---
phase: 12
title: Objective-C god-file decomposition
status: complete
agent: worker
depends_on: [6]
---

# Phase 12: Objective-C god-file decomposition

## Mission

Execute mega-plan Phase 4 item 3 / workstream 02 A3: decompose the priority
god files behind characterization tests and seam maps. Start with XRPC route
ownership, then OAuth, then the PDS services. Depends on phase 6 because the
NSID-constant sweep and CLI/lifecycle adoption already reshaped the
registration and binary entry surfaces this phase cuts along.

## Read first

- `docs/plans/workstreams/02-core-architecture-and-reliability.md` (A3 —
  authoritative targets and rules)
- `.agents/skills/better-code-objc` and `.agents/skills/garazyk-testing`
  (characterization/registration patterns; new XCTest suites need cmake
  reconfigure plus registration in `test_main.m`)
- `.agents/skills/gnustep-compat` — GNUstep category loading must be proven
  before splitting implementations into categories (A3 rule)

## Scope and order

1. **Route packs**: `AppViewXRpcRoutePack.m`, `XrpcRepoPack.m`,
   `XrpcAdminPack.m`, `XrpcServerPack.m` — split by route ownership. The
   generated NSID constants and the registration drift/lint checks
   (`e212288bd`, Narzedzia literal guard) must stay green after every slice.
2. **`OAuth2Handler.m`** — characterize the full grant/consent/DPoP flows
   first (scenario 93/94 regressions guard the consent form; do not weaken
   them).
3. **`PDSRecordService.m`, `PDSRepositoryService.m`, and the migration
   manager** — coordinate with phase 11: never decompose a file in the same
   slice that a phase-11 lane is rewriting.

Out of scope: `UIServerRuntime.m` and `UIBackendClient.m` belong to phase 8
(workstream 04 U6) — do not touch them here.

## Rules (from A3)

- No contract fixes and god-file decomposition in the same module at the
  same time; decompose only after characterization tests and a seam map.
- Keep MST and STAR cohesive unless a measured seam appears.
- No public API removals without caller proof (mega-plan Phase 4 exit gate).
- One coherent decomposition slice per commit, each verified with targeted
  tests plus the global gates.

## Acceptance gate

- Every decomposed module has a characterization suite that passed before
  and after the split, registered and running (not silently skipped).
- Linux Docker gate for anything touching Compat, Network, or binary
  entrypoints; global gates pass.

## On completion

Update workstream 02 A3 and mega-plan Phase 4 item 3; set
`status: complete` here.
