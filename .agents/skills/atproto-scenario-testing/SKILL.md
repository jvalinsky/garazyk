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
   python scripts/scenarios/run_scenario.py              # All scenarios
   python scripts/scenarios/run_scenario.py 01           # Single scenario
   python scripts/scenarios/run_scenario.py 01 03 05     # Specific scenarios
   python scripts/scenarios/run_scenario.py --list       # List available
   ```

3. **Review results and diagnostics:**
   - Terminal: colored PASS/FAIL/SKIP table per scenario
   - JSON: `/tmp/garazyk-atproto-e2e/<run-id>/reports/<timestamp>-<scenario>.json`
   - Diagnostics: `/tmp/garazyk-atproto-e2e/<run-id>/diagnostics/`

4. **Tear down:**
   ```bash
   ./scripts/scenarios/teardown_local_network.sh --wipe
   ```

## Scenarios

| ID | Name | What It Tests | Services |
|---|---|---|---|
| 01 | Account Lifecycle | Account creation, PLC DID, profile, sessions | PDS, PLC |
| 02 | Social Graph | Follows, unfollows, blocks, follower lists | PDS, AppView |
| 03 | Content Creation | Posts, replies, quotes, likes, bookmarks, deletes | PDS, AppView, Relay |
| 04 | Moderation & Safety | Reports, labels, takedowns, Ozone events | PDS, Ozone |
| 05 | Federation | Cross-PDS follows, DID resolution, firehose | PDSx2, PLC, Relay, AppView |
| 06 | Chat & DMs | DMs, group chats, mute, leave | PDS, AppView |
| 07 | Blobs & Uploads | Image uploads, embeds, profile banners | PDS |
| 08 | OAuth2 & Sessions | OAuth flows, token refresh, revocation | PDS |
| 09 | Firehose Streaming | WebSocket subscription, event sequencing | PDS, Relay, AppView |
| 10 | Performance & Resilience | Burst posting, batch writes, error handling | PDS, Relay, AppView |

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

- **Runner**: `scripts/scenarios/run_scenario.py`
- **Shared library**: `scripts/scenarios/lib/` (client, characters, assertions, report, firehose, docker)
- **Scenarios**: `scripts/scenarios/scenarios/01_*.py` through `10_*.py`
- **Infrastructure**: `scripts/scenarios/setup_local_network.sh`, `teardown_local_network.sh`
- **Docker override**: `docker/local-network/docker-compose.scenarios.yml` (adds second PDS)
- **Reports**: `/tmp/garazyk-atproto-e2e/<run-id>/reports/` (JSON output)
- **Diagnostics**: `/tmp/garazyk-atproto-e2e/<run-id>/diagnostics/` (health, logs, compose status)
- **Documentation**: `scripts/scenarios/README.md`

## Adding a New Scenario

1. Create `scripts/scenarios/scenarios/NN_name.py` with a `run()` function returning `ScenarioResult`
2. Register in `SCENARIO_REGISTRY` in `run_scenario.py`
3. Add characters to `lib/characters.py` if needed
4. Add XRPC helpers to `lib/client.py` if needed

## Runner Options

```
python scripts/scenarios/run_scenario.py [SCENARIO_IDS...] [OPTIONS]

Options:
  --list          List available scenarios
  --setup-only    Start network without running scenarios
  --teardown      Stop network after running
  --pds2          Start second PDS for federation scenarios
  --verbose       Enable debug output
  --no-json       Don't write JSON report files
  --run-id ID     Reuse or name the shared e2e run directory
  --setup         Start the local network before running
  --keep-running  Leave services running after setup/run
  --collect-diagnostics
                  Capture diagnostics without running scenarios
```

## Exit Codes

- **0**: All scenarios passed (skips are OK)
- **1**: One or more scenarios failed

## Dependencies

- Python 3.10+
- `requests` (required)
- `websockets` (optional, for firehose scenario 09)
- Docker + Docker Compose
