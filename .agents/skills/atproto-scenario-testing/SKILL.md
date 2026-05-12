---
name: atproto-scenario-testing
description: "Run scenario-based simulation scripts against local ATProto services (PDS, AppView, Relay, PLC). Covers account lifecycle, social graph, content creation, moderation, federation, chat, blobs, OAuth, firehose, and performance."
---

# ATProto Scenario Testing

Run narrative-driven simulation scripts against the local ATProto service network. Each scenario uses named characters to exercise specific XRPC endpoints and validate the full stack.

## Quick Start

1. **Start the local network:**
   ```bash
   ./scripts/scenarios/setup_local_network.sh
   # Or with second PDS for federation:
   ./scripts/scenarios/setup_local_network.sh --pds2
   ```

2. **Run scenarios:**
   ```bash
   ./scripts/run_scenarios.ts              # All scenarios
   ./scripts/run_scenarios.ts 01           # Single scenario
   ./scripts/run_scenarios.ts 01 03 05     # Specific scenarios
   ./scripts/run_scenarios.ts --list       # List available
   ```

3. **Review results and diagnostics:**
   - Terminal: colored PASS/FAIL/SKIP table per scenario
   - JSON: `/tmp/garazyk-atproto-e2e/<run-id>/reports/`
   - Diagnostics: `/tmp/garazyk-atproto-e2e/<run-id>/diagnostics/`

4. **Tear down:**
   ```bash
   ./scripts/run_scenarios.ts --teardown
   ```

## Scenarios

| ID | Name | What It Tests |
|---|---|---|
| 01-10 | Core ATProto | Account, Social, Content, Moderation, Federation, Chat, Blobs, OAuth, Firehose, Perf |
| 11-20 | UI & Identity | OAuth Login, Migration, Drafts, Boundaries, Notifications, Search |
| 21-30 | Scale & AppView | Lexicon Endpoints, Hooks, Proxy, Ingest Load, Soak, Formats, Depth, Monotonicity |
| 31-52 | Edge Cases | Rate Limits, Backpressure, Video, Germ E2EE, Group Chat, Reconnection |

## Characters

- **Luna Starfield** (`luna.test`) — Astronomy enthusiast
- **Marcus Code** (`marcus.test`) — Developer
- **Chef Rosa** (`rosa.test`) — Food blogger
- **DJ Volt** (`volt.test`) — Music producer
- **Trollface McGee** (`troll.test`) — Bad actor
- **Quiet Observer** (`quiet.test`) — Lurker
- **Admin Sentinel** (`admin.test`) — Server admin
- **Mod Justice** (`mod.test`) — Ozone moderator
- **Nova Bright** (`nova.second.test`) — Cross-PDS user (PDS 2)
- **Rex Storm** (`rex.second.test`) — Cross-PDS troll (PDS 2)

## Key Files

- **Runner**: `scripts/run_scenarios.ts`
- **Library**: `scripts/lib/deno/` (client, config, diagnostics, instrumentation, runner, transport)
- **Scenarios**: `scripts/scenarios/scenarios/*.ts`
- **Reports**: `/tmp/garazyk-atproto-e2e/<run-id>/reports/`

## Adding a New Scenario

1. Create `scripts/scenarios/scenarios/NN_name.ts` with a `run()` function returning `ScenarioResult`
2. Use `timedCall(result, "Step Name", async () => { ... })` for steps.
3. Import characters and clients from `../../lib/deno/`.

## Runner Options

```
./scripts/run_scenarios.ts [SCENARIO_IDS...] [OPTIONS]

Options:
  --list          List available scenarios
  --setup-only    Start network without running scenarios
  --teardown      Stop network
  --pds2          Start second PDS for federation
  --no-setup      Skip starting network (use existing)
```

## Dependencies

- Deno 2.x
- Docker + Docker Compose
