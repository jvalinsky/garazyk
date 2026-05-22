# Adversarial Protocol Abuse Scenarios Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 3 new E2E test scenarios to cover MST poisoning, Firehose sequencer attacks, and DAG-CBOR zip bombs.

**Architecture:** 
These are Deno test scenarios under `scripts/scenarios/scenarios/`. We will create three new files mapping to the scenarios defined in the design doc. The scenarios will bypass standard ATProto clients where necessary to craft malicious payloads.

**Tech Stack:** TypeScript, Deno, ATProto, DAG-CBOR, local PDS network.

### Task 1: Create MST Poisoning Scenario

**Files:**
- Create: `scripts/scenarios/scenarios/64_mst_poisoning.ts`

**Step 1: Write the failing scenario structure**

```typescript
/**
 * @module scenarios/64_mst_poisoning
 *
 * Scenario: MST Exploitation (Merkle Search Tree Poisoning)
 */

import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("MST Exploitation");
  result.start();
  
  const client = new XrpcClient(PDS1);
  const troll = getCharacter("troll");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create Troll", async () => {
    return await client.accounts.createAccount(troll.handle, troll.email, troll.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  troll.did = session.did;
  troll.accessJwt = session.accessJwt;

  await timedCall(result, "Create colliding records", async () => {
    throw new Error("Not implemented");
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `deno run -A scripts/scenarios/scenarios/64_mst_poisoning.ts`
Expected: FAIL with "Not implemented"

**Step 3: Write minimal implementation**

Implement the logic to generate records with identical `rkey` prefixes and apply them via `com.atproto.repo.applyWrites`. Assert that it either fails gracefully or handles it within reasonable time.

```typescript
  await timedCall(result, "Create colliding records", async () => {
    const writes = [];
    const basePrefix = "poison1234";
    for (let i = 0; i < 500; i++) {
      const suffix = i.toString().padStart(3, "0");
      writes.push({
        $type: "com.atproto.repo.applyWrites#create",
        collection: "app.bsky.feed.post",
        rkey: basePrefix + suffix,
        value: {
          $type: "app.bsky.feed.post",
          text: "Poison record " + i,
          createdAt: new Date().toISOString()
        }
      });
    }

    try {
      await client.records.applyWrites(troll.did, writes, troll.accessJwt);
    } catch (err: any) {
      if (err.message.includes("MST depth") || err.message.includes("400") || err.message.includes("Rate")) {
        // Expected rejection or limits
        return;
      }
      throw err;
    }
  });
```

*(Note: exact client method may vary, check client.ts if applyWrites is supported, else create records sequentially or use the raw client)*

**Step 4: Run test to verify it passes**

Run: `deno run -A scripts/scenarios/scenarios/64_mst_poisoning.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/scenarios/scenarios/64_mst_poisoning.ts
git commit -m "test: add MST poisoning scenario"
```

### Task 2: Create Firehose Fuzzing Scenario

**Files:**
- Create: `scripts/scenarios/scenarios/65_firehose_fuzzing.ts`

**Step 1: Write the failing test**

```typescript
/**
 * @module scenarios/65_firehose_fuzzing
 *
 * Scenario: Firehose Sequencer Attacks
 */
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Sequencer Attacks");
  result.start();
  
  await timedCall(result, "Simulate sequencer attacks", async () => {
    throw new Error("Not implemented");
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `deno run -A scripts/scenarios/scenarios/65_firehose_fuzzing.ts`
Expected: FAIL

**Step 3: Write minimal implementation**

We will mock connecting to a firehose and verifying consumer robustness, or generate records and intercept. Because intercepting PDS 2 firehose requires modifying PDS 2, we can simply craft negative tests if a direct websocket fuzzing client is available, or use the raw client.
*(Implementation will use a mocked websocket server that emits malformed seq gaps/regressions and connect the consumer client to it)*

**Step 4: Run test to verify it passes**

Run: `deno run -A scripts/scenarios/scenarios/65_firehose_fuzzing.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/scenarios/scenarios/65_firehose_fuzzing.ts
git commit -m "test: add firehose fuzzing scenario"
```

### Task 3: Create CBOR Bomb Scenario

**Files:**
- Create: `scripts/scenarios/scenarios/66_cbor_bombs.ts`

**Step 1: Write the failing test**

Create the file structure similar to above, failing on "Not implemented".

**Step 2: Run test to verify it fails**

Run: `deno run -A scripts/scenarios/scenarios/66_cbor_bombs.ts`
Expected: FAIL

**Step 3: Write minimal implementation**

Construct a raw payload for `notifyOfUpdate` or `applyWrites` where the CBOR is maliciously structured (e.g. an array with length header of 10000000 but few actual bytes). Use `Deno.core` or a raw buffer to bypass standard CBOR encoders if needed, then send via `fetch` directly. Assert a 400 Bad Request is returned and the PDS health check succeeds immediately afterward.

**Step 4: Run test to verify it passes**

Run: `deno run -A scripts/scenarios/scenarios/66_cbor_bombs.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add scripts/scenarios/scenarios/66_cbor_bombs.ts
git commit -m "test: add cbor bombs scenario"
```
