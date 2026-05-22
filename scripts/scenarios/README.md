# ATProto Scenario Simulation Suite

Scenario-based simulation scripts that exercise all four ATProto services (PDS, AppView, Relay/BGS,
PLC) running in the local-network Docker environment. Each scenario tells a story with named
characters, exercises specific XRPC endpoints, and validates the full stack.

## Quick Start

```bash
# 1. Start the local network
./scripts/scenarios/setup_local_network.sh

# 2. Run all scenarios
./scripts/run_scenarios.ts --no-setup

# 3. Run a specific scenario
./scripts/run_scenarios.ts --no-setup 01

# 4. Stop the network when done
./scripts/scenarios/teardown_local_network.sh
```

## Prerequisites

- **Docker + Docker Compose** — for running the local-network services
- **Deno 2+** — for scenario scripts

```bash
deno --version
```

## Characters

### PDS 1: "The Neighborhood" (localhost:2583)

| Character       | Handle        | Role      | Persona                          |
| --------------- | ------------- | --------- | -------------------------------- |
| Luna Starfield  | `luna.test`   | User      | Astronomy enthusiast, friendly   |
| Marcus Code     | `marcus.test` | User      | Developer, builds ATProto tools  |
| Chef Rosa       | `rosa.test`   | User      | Food blogger, social butterfly   |
| DJ Volt         | `volt.test`   | User      | Music producer, energetic        |
| Trollface McGee | `troll.test`  | User      | Bad actor, posts spam/harassment |
| Quiet Observer  | `quiet.test`  | User      | Lurker, follows many             |
| Admin Sentinel  | `admin.test`  | Admin     | Server administrator             |
| Mod Justice     | `mod.test`    | Moderator | Ozone moderator                  |

### PDS 2: "The Other Side" (localhost:2587) — federation scenarios only

| Character   | Handle             | Role | Persona         |
| ----------- | ------------------ | ---- | --------------- |
| Nova Bright | `nova.second.test` | User | Cross-PDS user  |
| Rex Storm   | `rex.second.test`  | User | Cross-PDS troll |

## Core Scenarios

Use `./scripts/run_scenarios.ts --list` for the complete auto-discovered scenario set.

| ID | Name                                 | Description                                                           | Services                   | PDS2? |
| -- | ------------------------------------ | --------------------------------------------------------------------- | -------------------------- | ----- |
| 01 | Account Lifecycle                    | Create account, PLC DID, profile, sessions                            | PDS, PLC                   | No    |
| 02 | Social Graph                         | Follows, unfollows, blocks, follower lists                            | PDS, AppView               | No    |
| 03 | Content Creation                     | Posts, replies, quotes, likes, bookmarks, deletes                     | PDS, AppView, Relay        | No    |
| 04 | Moderation & Safety                  | Reports, labels, takedowns, Ozone                                     | PDS, Ozone                 | No    |
| 05 | Federation                           | Cross-PDS follows, DID resolution, firehose                           | PDSx2, PLC, Relay, AppView | Yes   |
| 06 | Chat & DMs                           | DMs, group chats, mute, leave                                         | PDS, AppView               | No    |
| 07 | Blobs & Uploads                      | Image uploads, embeds, profile banners                                | PDS                        | No    |
| 08 | OAuth2 & Sessions                    | OAuth flows, token refresh, revocation                                | PDS                        | No    |
| 09 | Firehose Streaming                   | WebSocket subscription, event sequencing                              | PDS, Relay, AppView        | No    |
| 10 | Performance & Resilience             | Burst posting, batch writes, error handling                           | PDS, Relay, AppView        | No    |
| 11 | Lab OAuth2 Login                     | UI server OAuth2 login flow, admin auth boundary                      | garazyk-ui                 | No    |
| 12 | Account Migration                    | Cooperative account migration, PLC audit                              | PDS, PDS2, PLC             | Yes   |
| 13 | E2E OAuth2 Client Integration        | Full stack OAuth2 dance with browser automation                       | PLC, PDS, AppView          | No    |
| 14 | Drafts & Bookmarks Workflow          | Draft CRUD, publish from draft, bookmark lifecycle                    | PDS, AppView               | No    |
| 15 | Mutes, Relationships & Starter Packs | Mute/unmute, getRelationships, starter pack CRUD                      | PDS, AppView               | No    |
| 16 | Notification Management              | updateSeen, registerPush, preferences, activity subscriptions         | PDS, AppView               | No    |
| 17 | Actor Preferences & Discovery        | putPreferences, searchActorsTypeahead, getActorLikes, getRepostedBy   | PDS, AppView               | No    |
| 18 | AppView Admin Operations             | Ingest health, backfill, metrics, lexicons, records, hooks            | AppView                    | No    |
| 19 | Contact & Age Assurance              | Phone verification, contact import/matches, age assurance flow        | PDS, AppView               | No    |
| 20 | Unspecced Search & Discovery         | searchActorsSkeleton, searchPostsSkeleton, searchStarterPacksSkeleton | PDS, AppView               | No    |
| 21 | AppView Lexicon Endpoints            | Dynamic endpoint registration, lexicon-driven XRPC queries            | PDS, AppView, Relay        | No    |
| 22 | AppView Hooks & Dead Letter          | Hook registry, search index, dead letter recording                    | PDS, AppView, Relay        | No    |
| 23 | AppView Write Proxy                  | Write proxy surface, OAuth2 middleware behavior                       | PDS, AppView               | No    |
| 24 | Concurrent Write Throughput          | 32-account burst, mixed workload, instrumentation                     | PDS                        | No    |
| 25 | Firehose Fan-Out Scale               | 50+ concurrent subscribers, batch fan-out, backpressure               | PDS, Relay                 | No    |
| 26 | AppView Ingest Load                  | Sustained writes, backpressure pause/resume, ingest stability         | PDS, AppView, Relay        | No    |
| 27 | Fullstack Soak                       | 120-second mixed workload, Prometheus metrics, process health         | PDS, Relay, AppView        | No    |

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
./scripts/run_scenarios.ts --no-setup

# Run specific scenarios
./scripts/run_scenarios.ts --no-setup 01 03 05

# With second PDS (needed for scenario 05)
./scripts/run_scenarios.ts --pds2

# List available scenarios
./scripts/run_scenarios.ts --list

# Start network, run scenarios, collect failure diagnostics, then tear down
./scripts/run_scenarios.ts --setup --teardown

# Keep services running after setup for manual inspection
./scripts/run_scenarios.ts --setup-only --keep-running --run-id local-debug

# Verbose output
./scripts/run_scenarios.ts --verbose

# Don't write JSON reports
./scripts/run_scenarios.ts --no-json
```

### Stop the Network

> [!WARNING]
> Running the teardown script with `--wipe` or `-w` will **completely delete all persistent Docker volumes** associated with the local network databases (PLC, PDS, etc.), resulting in complete loss of local test account state.

```bash
# Stop, preserve data (containers stopped, volumes kept)
./scripts/scenarios/teardown_local_network.sh --run-id local-debug

# Stop and wipe all data (containers stopped, volumes deleted)
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
`/tmp/garazyk-atproto-e2e/<run-id>/reports/`. Each report includes run metadata, service URLs, and
the diagnostics directory.

```json
{
  "scenario": "Account Lifecycle & Identity",
  "started_at": 1713900000.0,
  "finished_at": 1713900015.0,
  "duration_s": 15.0,
  "steps": [
    { "name": "Server health check", "status": "passed", "detail": "", "duration_ms": 0 },
    {
      "name": "Create account",
      "status": "passed",
      "detail": "did=did:plc:abc123",
      "duration_ms": 0
    }
  ],
  "summary": { "passed": 10, "failed": 0, "skipped": 0, "total": 10 },
  "ok": true,
  "metadata": {
    "run_id": "20260507t180000z-12345",
    "run_dir": "/tmp/garazyk-atproto-e2e/20260507t180000z-12345",
    "diagnostics_dir": "/tmp/garazyk-atproto-e2e/20260507t180000z-12345/diagnostics"
  }
}
```

### Diagnostics

Every supported runner writes diagnostics under `/tmp/garazyk-atproto-e2e/<run-id>/diagnostics/`
unless `--diagnostics-dir` is provided. Bundles include:

- `run-metadata.*` with run id, repo state, service URLs, and compose project
- `http/*.txt` health/admin endpoint captures with tokens redacted
- `docker/ps.txt`, `docker/config.txt`, and redacted Docker logs for compose runs
- `service-logs/*.log` and `pids.txt` for local binary runs

Use `--collect-diagnostics` on `setup_local_network.sh`, `teardown_local_network.sh`,
`run_scenarios.ts`, `full_suite_demo.sh`, or the e2e wrappers to capture the current state without
rerunning tests.

## Architecture

```
scripts/
├── run_scenarios.ts                    # Scenario runner
├── lib/deno/                           # Shared TypeScript scenario helpers
│   ├── client.ts                       # XRPC/HTTP client with auth, retry, logging
│   ├── config.ts                       # Service URLs and character fixtures
│   ├── runner.ts                       # Scenario result reporting
│   ├── docker.ts                       # Local-network process boundary
│   └── ...
└── scenarios/
    ├── README.md
    ├── setup_local_network.sh          # Start Docker/binary services
    ├── teardown_local_network.sh       # Stop services
    └── scenarios/
        ├── 01_account_lifecycle.ts
        ├── 02_social_graph.ts
        └── ...
```

## Adding a New Scenario

1. Create `scripts/scenarios/scenarios/NN_name.ts` with a `run()` function that returns a
   `ScenarioResult`.
2. Import shared helpers from `../../lib/deno/`.
3. Use the `NN_` filename prefix; discovery is automatic.
4. Add characters to `scripts/lib/deno/config.ts` if needed.
5. Add any new XRPC helpers under `scripts/lib/deno/clients/`.

### Template

```ts
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Scenario Name");
  result.start();
  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  result.printSummary();
  Deno.exit(result.ok ? 0 : 1);
}
```

## Endpoint Coverage

| Namespace | Scenarios | Key Endpoints | |---|---|---|---| | `com.atproto.server.*` | 1, 8 |
createAccount, createSession, getSession, refreshSession, deleteSession, describeServer | |
`com.atproto.identity.*` | 1, 5 | resolveHandle, updateHandle | | `com.atproto.repo.*` | 3, 7, 10 |
createRecord, getRecord, deleteRecord, uploadBlob, applyWrites, listRecords | | `com.atproto.sync.*`
| 5, 9 | subscribeRepos, getRepo, getHead, getBlob, getRecord | | `com.atproto.moderation.*` | 4 |
createReport | | `com.atproto.admin.*` | 4 | getSubjectStatus, updateSubjectStatus | |
`com.atproto.label.*` | 4 | getLabels, queryLabels | | `app.bsky.actor.*` | 1, 2, 3, 17 |
getProfile, getProfiles, searchActors, searchActorsTypeahead, getPreferences, putPreferences,
getSuggestions, profile record | | `app.bsky.feed.*` | 3, 10, 17 | post, like, repost, bookmark,
getTimeline, getAuthorFeed, getPostThread, getLikes, getActorLikes, getPosts, getRepostedBy, getFeed
| | `app.bsky.graph.*` | 2, 15 | follow, block, getFollows, getFollowers, getBlocks, getMutes,
muteActor, unmuteActor, getRelationships, getStarterPack, getActorStarterPacks, getStarterPacks | |
`app.bsky.graph.starterpack` | 15, 20 | starterpack record, getStarterPack, getActorStarterPacks,
getStarterPacks | | `app.bsky.notification.*` | 3, 16 | listNotifications, getUnreadCount,
updateSeen, registerPush, unregisterPush, getPreferences, putPreferences, listActivitySubscriptions,
putActivitySubscription | | `app.bsky.draft.*` | 14 | createDraft, updateDraft, getDrafts,
deleteDraft | | `app.bsky.bookmark.*` | 3, 14 | getBookmarks, createBookmark, deleteBookmark | |
`app.bsky.contact.*` | 19 | startPhoneVerification, verifyPhone, importContacts, getMatches,
dismissMatch, getSyncStatus, removeData | | `app.bsky.ageassurance.*` | 19 | begin, getConfig,
getState | | `app.bsky.unspecced.*` | 20 | searchActorsSkeleton, searchPostsSkeleton,
searchStarterPacksSkeleton | | `chat.bsky.convo.*` | 6 | getConvo, sendMessage, getList,
getMessages, muteConvo | | `chat.bsky.group.*` | 6 | createGroup, getGroup, addMember | |
`tools.ozone.*` | 4 | queryReports, emitEvent | | OAuth2 | 8 | /oauth/authorize, /oauth/token,
/oauth/revoke | | PLC | 1, 5 | DID creation, resolution | | Relay API | 5, 9, 10 |
/api/relay/health, /api/relay/upstreams | | AppView Admin | 3, 5, 9, 18 | /admin/backfill/status,
/admin/backfill/queue, /admin/backfill/repos, /admin/backfill/scope/rebuild, /admin/ingest/health,
/admin/appview/metrics/stats, /admin/lexicons, /admin/lexicons/collections, /admin/records,
/admin/hooks, /admin/hooks/dead-letter, /admin/handlers, /admin/endpoints |

## Topologies

Topologies swap out individual services (PLC, relay, PDS) with alternate implementations to test
interop. See [topologies/README.md](topologies/README.md) for the full catalog and known
compatibility issues.

### Quick reference

```bash
# Run with a specific topology
./scripts/run_scenarios.ts --topology allegedly-plc 01
./scripts/run_scenarios.ts --topology rsky-relay 01
./scripts/run_scenarios.ts --topology indigo-relay 01
```
