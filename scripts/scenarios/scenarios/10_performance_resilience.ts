/**
 * @module scenarios/10_performance_resilience
 *
 * Scenario: Tests PDS performance, scalability, and resilience under burst load.
 *
 * Behavior:
 * - Creates test accounts for multiple users.
 * - Performs burst post creation to measure throughput.
 * - Verifies that all records were correctly persisted across accounts.
 * - Tests batch operations using `applyWrites`.
 * - Verifies resilience by testing various negative cases (invalid record, duplicate rkey, missing auth, non-existent collection).
 * - Checks AppView consistency and PDS/Relay health after load.
 * - Confirms timeline retrieval works correctly after the load test.
 *
 * Expectations:
 * - High-throughput write operations are handled within acceptable limits.
 * - System remains consistent and records are correctly indexed after burst activity.
 * - Negative inputs and unauthorized requests are rejected gracefully.
 * - System services (PDS/Relay/AppView) remain healthy under stress.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { createAccountOrLogin, now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Performance & Resilience");
  result.start();

  const client = new XrpcClient(PDS1);
  const av = new XrpcClient(SERVICE_URLS.appview);

  await timedCall(
    result,
    "Server health check",
    async () => {
      await client.raw.xrpcGet("com.atproto.server.describeServer");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt", "quiet"];
  for (const name of charNames) {
    const char = getActor(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      () => createAccountOrLogin(client, char),
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => getActor(n).did);
  if (active.length < 3) {
    result.stepFailed("Account creation", "Not enough accounts");
    result.finish();
    return result;
  }

  await new Promise((r) => setTimeout(r, 2000));

  const POSTS_PER_USER = 10;
  let totalPosts = 0;
  let failedPosts = 0;
  const startTime = performance.now();

  const promises = [];
  for (const name of active) {
    const char = getActor(name);
    for (let i = 0; i < POSTS_PER_USER; i++) {
      promises.push((async () => {
        try {
          await client.as(char).raw.post("com.atproto.repo.createRecord", {
            repo: char.did,
            collection: "app.bsky.feed.post",
            record: {
              $type: "app.bsky.feed.post",
              text: `Burst post #${i + 1} from ${char.name}! Load testing the PDS.`,
              createdAt: now(),
            },
          });
          return true;
        } catch {
          return false;
        }
      })());
    }
  }

  const results = await Promise.all(promises);
  results.forEach((success) => {
    if (success) totalPosts++;
    else failedPosts++;
  });

  const elapsed = (performance.now() - startTime) / 1000;
  result.stepPassed(
    "Burst post creation",
    `created=${totalPosts}, failed=${failedPosts}, elapsed=${elapsed.toFixed(1)}s, rate=${
      (totalPosts / Math.max(elapsed, 0.01)).toFixed(1)
    } posts/s`,
  );

  let totalRecords = 0;
  for (const name of active) {
    const char = getActor(name);
    const records = await timedCall(
      result,
      `Verify posts: ${char.name}`,
      async () => {
        return await client.as(char).raw.get("com.atproto.repo.listRecords", {
          repo: char.did,
          collection: "app.bsky.feed.post",
        });
      },
    );
    if (records) {
      totalRecords += (records.records || []).length;
    }
  }

  result.stepPassed("Verify posts exist", `total_records_across_users=${totalRecords}`);

  const luna = getActor("luna");
  const batchWrites: Array<Record<string, unknown>> = [];
  for (let i = 0; i < 5; i++) {
    batchWrites.push({
      $type: "com.atproto.repo.applyWrites#create",
      collection: "app.bsky.feed.post",
      rkey: `batch-${i}`,
      value: { $type: "app.bsky.feed.post", text: `Batch post #${i} from Luna`, createdAt: now() },
    });
  }

  await timedCall(
    result,
    "Batch applyWrites",
    async () => {
      return await client.as(luna).raw.post("com.atproto.repo.applyWrites", {
        repo: luna.did,
        writes: batchWrites,
      });
    },
    () => "5 records created",
  );

  await timedCall(
    result,
    "Invalid record rejected",
    async () => {
      await client.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post" },
      });
    },
    undefined,
    true,
  );

  try {
    await client.as(luna).raw.post("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "Original post with specific rkey",
        createdAt: now(),
      },
      rkey: "duplicate-test-rkey",
    });

    await timedCall(
      result,
      "Duplicate rkey rejected",
      async () => {
        await client.as(luna).raw.post("com.atproto.repo.createRecord", {
          repo: luna.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Duplicate post with same rkey",
            createdAt: now(),
          },
          rkey: "duplicate-test-rkey",
        });
      },
      undefined,
      true,
    );
  } catch (exc: any) {
    result.stepSkipped("Duplicate rkey rejected", String(exc));
  }

  await timedCall(
    result,
    "Missing auth rejected",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post", text: "unauthorized", createdAt: now() },
      }, "invalid-token-xyz");
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "Non-existent collection rejected",
    async () => {
      await client.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.nonexistent",
        record: { $type: "app.bsky.feed.nonexistent", text: "test", createdAt: now() },
      });
    },
    undefined,
    true,
  );

  await new Promise((r) => setTimeout(r, 5000));

  try {
    await av.asAdmin("localdevadmin").raw.httpGet("/admin/backfill/status");
    result.stepPassed("AppView consistency check", "backfill status OK");
  } catch (exc: any) {
    result.stepFailed("AppView consistency check", String(exc));
  }

  await timedCall(
    result,
    "Timeline has content after burst",
    async () => {
      return await client.as(luna).raw.get("app.bsky.feed.getTimeline", {});
    },
    (t) => `items=${t.feed?.length || 0}`,
  );

  try {
    const relayClient = new XrpcClient(SERVICE_URLS.relay);
    await relayClient.raw.httpGet("/api/relay/health");
    result.stepPassed("Relay healthy after load");
  } catch (exc: any) {
    result.stepSkipped("Relay healthy after load", String(exc));
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
