# ATProto Scenario Simulation Suite

Scenario-based simulation scripts that exercise all four ATProto services (PDS, AppView, Relay/BGS, PLC) running in the local-network Docker environment. Each scenario tells a story with named characters, exercises specific XRPC endpoints, and validates the full stack.

## Quick Start

```bash
# 1. Start the local network
./scripts/scenarios/setup_local_network.sh

# 2. Run all scenarios
python scripts/scenarios/run_scenario.py

# 3. Run a specific scenario
python scripts/scenarios/run_scenario.py 01

# 4. Stop the network when done
./scripts/scenarios/teardown_local_network.sh
```

## Prerequisites

- **Docker + Docker Compose** — for running the local-network services
- **Python 3.10+** — for scenario scripts
- **pip packages**: `requests` (required), `websockets` (optional, for firehose scenarios)

```bash
pip install requests websockets
```

## Characters

### PDS 1: "The Neighborhood" (localhost:2583)

| Character | Handle | Role | Persona |
|---|---|---|---|
| Luna Starfield | `luna.test` | User | Astronomy enthusiast, friendly |
| Marcus Code | `marcus.test` | User | Developer, builds ATProto tools |
| Chef Rosa | `rosa.test` | User | Food blogger, social butterfly |
| DJ Volt | `volt.test` | User | Music producer, energetic |
| Trollface McGee | `troll.test` | User | Bad actor, posts spam/harassment |
| Quiet Observer | `quiet.test` | User | Lurker, follows many |
| Admin Sentinel | `admin.test` | Admin | Server administrator |
| Mod Justice | `mod.test` | Moderator | Ozone moderator |

### PDS 2: "The Other Side" (localhost:2585) — federation scenarios only

| Character | Handle | Role | Persona |
|---|---|---|---|
| Nova Bright | `nova.second.test` | User | Cross-PDS user |
| Rex Storm | `rex.second.test` | User | Cross-PDS troll |

## Scenarios

| ID | Name | Description | Services | PDS2? |
|---|---|---|---|---|
| 01 | Account Lifecycle | Create account, PLC DID, profile, sessions | PDS, PLC | No |
| 02 | Social Graph | Follows, unfollows, blocks, follower lists | PDS, AppView | No |
| 03 | Content Creation | Posts, replies, quotes, likes, bookmarks, deletes | PDS, AppView, Relay | No |
| 04 | Moderation & Safety | Reports, labels, takedowns, Ozone | PDS, Ozone | No |
| 05 | Federation | Cross-PDS follows, DID resolution, firehose | PDSx2, PLC, Relay, AppView | Yes |
| 06 | Chat & DMs | DMs, group chats, mute, leave | PDS, AppView | No |
| 07 | Blobs & Uploads | Image uploads, embeds, profile banners | PDS | No |
| 08 | OAuth2 & Sessions | OAuth flows, token refresh, revocation | PDS | No |
| 09 | Firehose Streaming | WebSocket subscription, event sequencing | PDS, Relay, AppView | No |
| 10 | Performance & Resilience | Burst posting, batch writes, error handling | PDS, Relay, AppView | No |

## Running Scenarios

### Start the Network

```bash
# Basic: PLC + PDS + Relay + AppView
./scripts/scenarios/setup_local_network.sh

# Give a run an explicit id so setup, diagnostics, and teardown target the same stack
./scripts/scenarios/setup_local_network.sh --run-id local-debug

# With second PDS for federation scenarios
./scripts/scenarios/setup_local_network.sh --pds2

# Just wait for an already-running network
./scripts/scenarios/setup_local_network.sh --wait-only

# Collect diagnostics without changing service state
./scripts/scenarios/setup_local_network.sh --collect-diagnostics --run-id local-debug
```

### Run Scenarios

```bash
# Run all scenarios (excludes PDS2 scenarios unless --pds2 is set)
python scripts/scenarios/run_scenario.py

# Run specific scenarios
python scripts/scenarios/run_scenario.py 01 03 05

# With second PDS (needed for scenario 05)
python scripts/scenarios/run_scenario.py --pds2

# List available scenarios
python scripts/scenarios/run_scenario.py --list

# Start network, run scenarios, collect failure diagnostics, then tear down
python scripts/scenarios/run_scenario.py --setup --teardown

# Keep services running after setup for manual inspection
python scripts/scenarios/run_scenario.py --setup-only --keep-running --run-id local-debug

# Verbose output
python scripts/scenarios/run_scenario.py --verbose

# Don't write JSON reports
python scripts/scenarios/run_scenario.py --no-json
```

### Stop the Network

```bash
# Stop, preserve data
./scripts/scenarios/teardown_local_network.sh --run-id local-debug

# Stop and wipe all data
./scripts/scenarios/teardown_local_network.sh --wipe --run-id local-debug

# Capture diagnostics before teardown
./scripts/scenarios/teardown_local_network.sh --collect-diagnostics --run-id local-debug
```

## Output

### Terminal Output

Each scenario prints a colored PASS/FAIL/SKIP table:

```
============================================================
  Scenario: Account Lifecycle & Identity
============================================================
  PASS Server health check
  PASS Describe server — domains=['.test']
  PASS Create account — did=did:plc:abc123
  PASS Get session — did=did:plc:abc123
  PASS Resolve handle — did=did:plc:abc123
  PASS PLC DID resolution — method=...
  PASS Create profile — uri=at://did:plc:abc123/...
  PASS Get profile — displayName=Luna Starfield
  PASS Refresh session
  PASS Invalid login rejected
  PASS Delete session (logout)
------------------------------------------------------------
  10 passed, 0 failed, 0 skipped (10 total)
  RESULT: ALL PASSED
============================================================
```

### JSON Reports

Machine-readable reports are written to the run directory by default:
`/tmp/garazyk-atproto-e2e/<run-id>/reports/`. Each report includes run
metadata, service URLs, and the diagnostics directory.

```json
{
  "scenario": "Account Lifecycle & Identity",
  "started_at": 1713900000.0,
  "finished_at": 1713900015.0,
  "duration_s": 15.0,
  "steps": [
    {"name": "Server health check", "status": "passed", "detail": "", "duration_ms": 0},
    {"name": "Create account", "status": "passed", "detail": "did=did:plc:abc123", "duration_ms": 0}
  ],
  "summary": {"passed": 10, "failed": 0, "skipped": 0, "total": 10},
  "ok": true,
  "metadata": {
    "run_id": "20260507t180000z-12345",
    "run_dir": "/tmp/garazyk-atproto-e2e/20260507t180000z-12345",
    "diagnostics_dir": "/tmp/garazyk-atproto-e2e/20260507t180000z-12345/diagnostics"
  }
}
```

### Diagnostics

Every supported runner writes diagnostics under
`/tmp/garazyk-atproto-e2e/<run-id>/diagnostics/` unless
`--diagnostics-dir` is provided. Bundles include:

- `run-metadata.*` with run id, repo state, service URLs, and compose project
- `http/*.txt` health/admin endpoint captures with tokens redacted
- `docker/ps.txt`, `docker/config.txt`, and redacted Docker logs for compose runs
- `service-logs/*.log` and `pids.txt` for local binary runs

Use `--collect-diagnostics` on `setup_local_network.sh`,
`teardown_local_network.sh`, `run_scenario.py`, `full_suite_demo.sh`, or
the e2e wrappers to capture the current state without rerunning tests.

## Architecture

```
scripts/scenarios/
├── README.md                          # This file
├── lib/                               # Shared Python library
│   ├── __init__.py
│   ├── client.py                      # XRPC/HTTP client with auth, retry, logging
│   ├── characters.py                  # Character definitions
│   ├── docker.py                      # Docker compose helpers
│   ├── assertions.py                  # Test assertion helpers
│   ├── firehose.py                    # WebSocket firehose subscriber
│   └── report.py                      # Scenario result reporting
├── scenarios/
│   ├── __init__.py
│   ├── 01_account_lifecycle.py
│   ├── 02_social_graph.py
│   ├── 03_content_creation.py
│   ├── 04_moderation_safety.py
│   ├── 05_federation.py
│   ├── 06_chat_dms.py
│   ├── 07_blobs_uploads.py
│   ├── 08_oauth_sessions.py
│   ├── 09_firehose_streaming.py
│   └── 10_performance_resilience.py
├── reports/                           # JSON report output (gitignored)
├── run_scenario.py                    # Scenario runner
├── setup_local_network.sh             # Start Docker services
└── teardown_local_network.sh          # Stop Docker services
```

## Adding a New Scenario

1. Create `scenarios/NN_name.py` with a `run()` function that returns a `ScenarioResult`
2. Import the shared library: `from lib.client import XrpcClient`, `from lib.characters import get_character`, etc.
3. Register it in `run_scenario.py`'s `SCENARIO_REGISTRY`
4. Add characters to `lib/characters.py` if needed
5. Add any new XRPC helpers to `lib/client.py`

### Template

```python
"""Scenario NN: "Name" — Description

What happens and what we're testing.

Services: PDS, AppView
"""

from __future__ import annotations
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Scenario Name")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ... your scenario steps ...

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
```

## Endpoint Coverage

| Namespace | Scenarios | Key Endpoints |
|---|---|---|
| `com.atproto.server.*` | 1, 8 | createAccount, createSession, getSession, refreshSession, deleteSession, describeServer |
| `com.atproto.identity.*` | 1, 5 | resolveHandle, updateHandle |
| `com.atproto.repo.*` | 3, 7, 10 | createRecord, getRecord, deleteRecord, uploadBlob, applyWrites, listRecords |
| `com.atproto.sync.*` | 5, 9 | subscribeRepos, getRepo, getHead, getBlob, getRecord |
| `com.atproto.moderation.*` | 4 | createReport |
| `com.atproto.admin.*` | 4 | getSubjectStatus, updateSubjectStatus |
| `com.atproto.label.*` | 4 | getLabels, queryLabels |
| `app.bsky.actor.*` | 1, 2, 3 | getProfile, getProfiles, searchActors, profile record |
| `app.bsky.feed.*` | 3, 10 | post, like, repost, bookmark, getTimeline, getAuthorFeed, getPostThread, getLikes |
| `app.bsky.graph.*` | 2 | follow, block, getFollows, getFollowers, getBlocks |
| `app.bsky.notification.*` | 3 | listNotifications, getUnreadCount |
| `chat.bsky.convo.*` | 6 | getConvo, sendMessage, getList, getMessages, muteConvo |
| `chat.bsky.group.*` | 6 | createGroup, getGroup, addMember |
| `tools.ozone.*` | 4 | queryReports, emitEvent |
| OAuth2 | 8 | /oauth/authorize, /oauth/token, /oauth/revoke |
| PLC | 1, 5 | DID creation, resolution |
| Relay API | 5, 9, 10 | /api/relay/health, /api/relay/upstreams |
| AppView Admin | 3, 5, 9 | /admin/backfill/status |
