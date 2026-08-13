---
phase: 34
title: Deno @dasl/tiles package and live Admin UI tile embed
status: pending
agent: worker
depends_on: []
---

# Phase 34: Deno tiles package + live Admin UI embed

## Mission

Close WS10 Phase 11 remainders: a Deno tiles protocol package and a live
Admin UI path that embeds an arbitrary tile (unique-origin host + mothership).
Do **not** claim a full browser tile-host product unless scope is explicitly
expanded. **Do not publish JSR** unless Phase 5 publication deferral is lifted.

## Read first

- [`docs/plans/workstreams/10-dasl-conformance.md`](../workstreams/10-dasl-conformance.md)
  — Phase 11
- `Garazyk/Sources/AdminUIServer/UITileDataProtocol.*`
- `Garazyk/Sources/AdminUIServer/UITileExecutionPolicy.*`
- `Garazyk/Sources/AdminUIServer/UITileLoadingHost.*`
- `Garazyk/Sources/Repository/ATProtoWebTileMothership.*`
- `Garazyk/Sources/Core/ATProtoWebTile.*` / `Repository/ATProtoWebTile+CAR.*`
- `.agents/skills/garazyk-admin-ui`
- Existing Deno package layout under `packages/` (e.g. `tui`, `gruszka`)

## What is already correct — do not redo

- Reserved `/.well-known/web-tiles/` routes, CSP/isolation policy, load-host 303
- CAR load + path resolve + mothership resolve-path + getBlob (ObjC)
- Trusted-origin postMessage helpers

## Slices

### A — Deno package

#### Slice 1 — Scaffold

Add `packages/tiles` (name `@garazyk/tiles` or `@dasl/tiles` per WS10 wording —
match plan language; prefer in-tree `@garazyk/tiles` if `@dasl/tiles` would
imply upstream ownership). Wire workspace `deno.json`, SPDX, README.

**Acceptance:** `deno task check` / `lint` include the package.

#### Slice 2 — Protocol client

Implement tiles-protocol message actions matching ObjC `UITileDataProtocol`
(`tiles-protocol-up-data-ready`, `…-up-data-payload`, `…-down-data-payload`).

**Acceptance:** Deno unit tests against recorded message shapes.

#### Slice 3 — resolve-path client

Worker-side client that requests path resolution from a mothership stub/HTTP
surface compatible with `ATProtoWebTileMothership`.

**Acceptance:** stub integration test.

#### Slice 4 — Fixture load

Load a MASL/CAR tile fixture; resolve `/` and at least one nested path.

**Acceptance:** golden fixture in `packages/tiles` or shared test fixtures.

#### Slice 5 — Package docs

Document relationship to ObjC host; state JSR publish is out of scope while
Phase 5 remains blocked.

### B — Live Admin UI embed

#### Slice 6 — Embed route

Admin UI route that iframes a unique-origin tile for a chosen CAR/CID using
existing loading-host + CSP.

**Acceptance:** HTTP/runtime test + short manual smoke note in WS10.

#### Slice 7 — Mothership wiring

Register mothership in the Admin UI / pack service bag so resolve-path works
in-process (no AdminUI→Storage boundary violation — mothership stays in
Repository; Admin UI talks via an injected protocol/HTTP boundary already
established).

**Acceptance:** boundary script green; end-to-end resolve evidence.

#### Slice 8 — Live postMessage

Prove trusted-origin data protocol on the live embed path (not only unit
policy tests).

#### Slice 9 — Demo tile asset

One static CAR/tile under resources or fixtures + scripted smoke.

#### Slice 10 — Plan evidence

Update WS10 Phase 11 + mega-plan; do not over-claim “full tile host product”.

## Out of scope

- JSR publication
- Arbitrary remote tile execution without policy
- S2PA / iroh work

## Acceptance gate

```bash
deno task check && deno task lint && deno task test
./scripts/dev/check_module_boundaries.sh .
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoWebTileMothershipTests' --gated=run
./build/tests/AllTests -XCTest 'UITileLoadingHostTests' --gated=run
# plus any new Admin UI tile embed tests registered in test_main.m
```
