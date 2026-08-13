---
phase: 34
title: Deno @dasl/tiles package and live Admin UI tile embed
status: complete
agent: worker
depends_on: []
---

## Progress

Completed 2026-08-13: `@garazyk/tiles` protocol + mothership client + demo
fixture; Admin UI `/lab/tiles/embed` + `/lab/tiles/mothership` with injectable
resolver (demo default); trustedOrigin data.js query; WS10 Phase 11 bounded
complete (not a full tile-host product; JSR still deferred).

# Phase 34: Deno tiles package + live Admin UI embed

## Mission

Close WS10 Phase 11 remainders: a Deno tiles protocol package and a live
Admin UI path that embeds an arbitrary tile (unique-origin host + mothership).
Do **not** claim a full browser tile-host product unless scope is explicitly
expanded. **Do not publish JSR** unless Phase 5 publication deferral is lifted.

## Acceptance gate (verified)

```bash
deno check packages/tiles/mod.ts packages/tiles/protocol_test.ts
deno test -A --no-check packages/tiles/
deno lint packages/tiles/
./scripts/dev/check_module_boundaries.sh .
./build/tests/AllTests -XCTest 'ATProtoWebTileMothershipTests' --gated=run
./build/tests/AllTests -XCTest 'UITileLoadingHostTests' --gated=run
# plus UIServerRuntimeTests lab tile routes
```
