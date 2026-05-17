---
name: adding-scenario
description: "Add a new scenario to the Garazyk Deno/TypeScript scenario runner. Covers scenario file structure, the ScenarioResult/timedCall API, character/account setup, XRPC client usage, assertion patterns, PDS2 requirements, and standalone execution. Use when adding a new e2e scenario, writing scenario tests, or extending the scenario suite."
---

# Adding a Scenario

Workflow for creating a new end-to-end scenario in the Garazyk Deno/TypeScript runner.

## When to Use

- "Add a new scenario test"
- "Write a scenario for [feature]"
- "Extend the scenario suite"
- "Create an e2e test for [XRPC method]"

## Quick Start

```bash
# List existing scenarios
./scripts/run_scenarios.ts --list

# Run a specific scenario
./scripts/run_scenarios.ts 03

# Run with binary mode (no Docker)
./scripts/run_scenarios.ts --binary 03

# Run with PDS2 (federation scenarios)
./scripts/run_scenarios.ts --pds2 --binary 05

# Generate a scenario scaffold
.agents/skills/adding-scenario/scripts/scaffold-scenario.sh <number> <name>
# Example:
.agents/skills/adding-scenario/scripts/scaffold-scenario.sh 59 labeler_lifecycle
```

## Scenario File Contract

Every scenario **must**:

1. Live at `scripts/scenarios/scenarios/NN_name.ts`
2. Export `run(): Promise<ScenarioResult>`
3. Use `ScenarioResult` + `timedCall` for step tracking
4. Support standalone execution via `if (import.meta.main)`

Scenarios are **auto-discovered** by filename — no manual registration needed. The runner imports them dynamically at runtime.

### Naming Convention

- File: `NN_descriptive_name.ts` where `NN` is a zero-padded number
- `NN` determines sort order and is the ID used to run the scenario
- Use the next available number (check existing files)
- Name uses `snake_case` — the runner converts `_` to spaces for display

### PDS2 Requirement

If the scenario needs a second PDS instance (federation, migration, cross-PDS operations):

1. Add the scenario number to the `NEEDS_PDS2` set in `scripts/run_scenarios.ts`:
   ```typescript
   const NEEDS_PDS2 = new Set(["05", "12", "35", "NN"]);
   ```
2. The runner will automatically start PDS2 when this scenario is selected
3. Users must pass `--pds2` to include it in a full run

## Step-by-Step Checklist

### 1. Pick the Next Number

```bash
ls scripts/scenarios/scenarios/ | sort -t_ -k1 -n | tail -5
```

Use the next number after the highest existing one.

### 2. Create the Scenario File

Use the scaffold script or create manually. The file structure:

```typescript
import { XrpcClient } from "@garazyk/atproto-client";
import { PDS1, getCharacter } from "@garazyk/scenario-runner";
import { ScenarioResult, timedCall } from "@garazyk/scenario-runner";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Human-Readable Name");
  result.start();

  // 1. Health check
  // 2. Create/recover accounts
  // 3. Test steps with timedCall
  // 4. Assertions

  result.finish();
  return result;
}

// Standalone execution
if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
```

### 3. Health Check

Always start with a health check. Bail early if the service is down:

```typescript
await timedCall(
  result, "Server health check",
  async () => {
    const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
    if (!res.ok) throw new Error("Server not healthy");
  }
);

if (result.failed > 0) {
  result.finish();
  return result;
}
```

### 4. Create Accounts

Use the character system from `config.ts`:

```typescript
const luna = getCharacter("luna");
const session = await timedCall(
  result, `Create account: ${luna.name}`,
  async () => {
    try {
      const res = await client.agent.createAccount({
        handle: luna.handle,
        email: luna.email,
        password: luna.password,
      });
      return res.data;
    } catch (e: any) {
      // Account may already exist from a previous run
      if (e.message?.includes("already exists")) {
        const res = await client.agent.login({
          identifier: luna.handle,
          password: luna.password,
        });
        return res.data;
      }
      throw e;
    }
  },
  (s) => `did=${s.did}`
);
if (session) {
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;
}
```

### 5. Write Test Steps

Wrap every meaningful operation in `timedCall`:

```typescript
// Basic step
await timedCall(
  result, "Create a follow",
  async () => {
    await client.raw.post("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.graph.follow",
      record: {
        $type: "app.bsky.graph.follow",
        subject: marcus.did,
        createdAt: new Date().toISOString(),
      },
    }, luna.accessJwt);
  }
);

// Step with detail string
await timedCall(
  result, "Get profile",
  async () => {
    return await client.raw.get("app.bsky.actor.getProfile", {
      actor: luna.did,
    }, luna.accessJwt);
  },
  (profile) => `handle=${profile.handle}, followers=${profile.followersCount}`
);

// Expect failure
await timedCall(
  result, "Write with revoked token",
  async () => {
    await client.raw.post("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.feed.post",
      record: { $type: "app.bsky.feed.post", text: "should fail", createdAt: new Date().toISOString() },
    }, revokedToken);
  },
  undefined,
  true  // expectFailure = true
);
```

### 6. Skip Optional Steps

When a service or capability is optional:

```typescript
result.stepSkipped("Video processing", "Video service not available");
```

### 7. Record Artifacts

For debugging, record relevant data:

```typescript
result.recordArtifact("created_records", recordUris);
result.recordArtifact("error_responses", client.lastResponses);
```

### 8. Add Standalone Execution

Every scenario must support running directly:

```typescript
if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
```

## Shared Utilities

### Imports

```typescript
// Core
import { XrpcClient } from "@garazyk/atproto-client";
import { PDS1, PDS2, getCharacter, getCharactersByRole, getCharactersByPds } from "@garazyk/scenario-runner";
import { ScenarioResult, timedCall, StepStatus } from "@garazyk/scenario-runner";

// Transport
import { TransportLayer, XrpcError } from "@garazyk/atproto-client";

// Diagnostics
import { createRunContext, collectDiagnostics } from "@garazyk/scenario-runner";

// Instrumentation (load/soak scenarios)
import { OperationTimer, PhaseTimer, scrapePrometheus, sampleStorage } from "@garazyk/scenario-runner";

// Mock services
import { MockTwilio } from "@garazyk/scenario-runner";
```

### XrpcClient API

| Property | Type | Purpose |
|----------|------|---------|
| `client.accounts` | `AccountsClient` | createAccount, createSession, deleteSession |
| `client.identity` | `IdentityClient` | resolveHandle, resolveDID, updateHandle |
| `client.records` | `RecordsClient` | createRecord, getRecord, listRecords, deleteRecord |
| `client.blobs` | `BlobsClient` | uploadBlob, getBlob |
| `client.graph` | `GraphClient` | getFollows, getFollowers, getBlocks |
| `client.feed` | `FeedClient` | getTimeline, getAuthorFeed, getPostThread |
| `client.notifications` | `NotificationsClient` | listNotifications, updateSeen |
| `client.drafts` | `DraftsClient` | createDraft, listDrafts, deleteDraft |
| `client.search` | `SearchClient` | searchActors, searchPosts |
| `client.contact` | `ContactClient` | getContacts, importContacts |
| `client.ageAssurance` | `AgeAssuranceClient` | age assurance flows |
| `client.admin` | `AdminClient` | admin login, getSubjectStatus, takedown |
| `client.raw` | `RawClient` | raw XRPC get/post with any method NSID |
| `client.agent` | proxy | `agent.createAccount()`, `agent.login()`, then `agent.com.atproto.repo.createRecord(...)` |

### TransportLayer (Raw HTTP)

```typescript
const transport = new TransportLayer(PDS1);

// XRPC methods
await transport.get("com.atproto.server.describeServer");
await transport.post("com.atproto.repo.createRecord", body, token);
await transport.postBinary("com.atproto.repo.uploadBlob", data, "image/png", token);
await transport.getBinary("com.atproto.sync.getBlob", params, token);

// Raw HTTP
await transport.httpGet("/api/relay/health");
await transport.httpPost("/admin/backfill/status", body, adminToken);
```

### Characters

| Name | Role | PDS | Persona |
|------|------|-----|---------|
| `luna` | user | PDS1 | Astronomy enthusiast |
| `marcus` | user | PDS1 | Developer, ATProto tools |
| `rosa` | user | PDS1 | Food blogger |
| `volt` | user | PDS1 | Music producer |
| `troll` | user | PDS1 | Bad actor, gets reported |
| `quiet` | user | PDS1 | Lurker, reads feeds |
| `admin` | admin | PDS1 | Server administrator |
| `mod` | mod | PDS1 | Ozone moderator |
| `nova` | user | PDS2 | Cross-PDS user |
| `rex` | user | PDS2 | Cross-PDS troll |

Handles are suffixed with a hex timestamp to avoid collisions across runs.

## References

- [references/scenario-patterns.md](references/scenario-patterns.md) — common scenario patterns (account lifecycle, content, social graph, federation, admin, load)
- [references/runner-api.md](references/runner-api.md) — full ScenarioResult, timedCall, StepStatus API reference
