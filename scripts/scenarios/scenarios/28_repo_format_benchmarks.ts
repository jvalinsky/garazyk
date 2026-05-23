/**
 * @module scenarios/28_repo_format_benchmarks
 *
 * Scenario: Benchmarks repo fetch performance across CAR and STAR formats.
 *
 * Behavior:
 * - Executes the 28 repo format benchmarks scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */


async function seedPostsInChunks(
  client: XrpcClient,
  did: string,
  token: string,
  count: number,
) {
  const chunkSize = 25;
  for (let start = 0; start < count; start += chunkSize) {
    const writes = Array.from({ length: Math.min(chunkSize, count - start) }, (_, offset) => {
      const index = start + offset;
      return {
        action: "create",
        collection: "app.bsky.feed.post",
        value: {
          $type: "app.bsky.feed.post",
          text: `Benchmark post ${index}`,
          createdAt: now(),
        },
      };
    });
    await client.records.applyWrites(did, writes, token);
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Repo Format Benchmarks");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const luna = getActor("luna");
  let session: any = null;
  try {
    session = await client.accounts.createAccount(luna.handle, luna.email, luna.password);
  } catch {
    session = await client.accounts.createSession(luna.handle, luna.password);
  }

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const POST_COUNT = 500;
  const existing = await client.records.listRecords(luna.did, "app.bsky.feed.post", {
    limit: 1,
    token: luna.accessJwt,
  });
  if (existing.records.length < 1) {
    console.log(`Seeding ${POST_COUNT} posts...`);
    await seedPostsInChunks(client, luna.did, luna.accessJwt, POST_COUNT);
    result.stepPassed("Seeding", `Created ${POST_COUNT} posts`);
  }

  const formats = [
    { label: "CAR", mime: "application/vnd.ipld.car" },
    { label: "STAR-L0", mime: "application/vnd.atproto.star" },
    { label: "STAR-Lite", mime: "application/vnd.atproto.star-lite" },
  ];

  const summary: Record<string, any> = {};

  for (const fmt of formats) {
    // Warmup
    await client.raw.xrpcGetBinary("com.atproto.sync.getRepo", {
      params: { did: luna.did },
      token: luna.accessJwt,
      headers: { "Accept": fmt.mime },
    });

    let totalMs = 0;
    let totalSize = 0;
    const iterations = 5;

    for (let i = 0; i < iterations; i++) {
      const start = performance.now();
      const [status, ct, body] = await client.raw.xrpcGetBinary("com.atproto.sync.getRepo", {
        params: { did: luna.did },
        token: luna.accessJwt,
        headers: { "Accept": fmt.mime },
      });
      const duration = performance.now() - start;
      totalMs += duration;
      totalSize += body.length;

      result.stepPassed(
        `Fetch ${fmt.label} (Iter ${i + 1})`,
        `bytes=${body.length} duration=${duration.toFixed(1)}ms`,
      );

      if (fmt.label !== "CAR" && body.length > 0) {
        assert.isTrue(body[0] === 0x2A, `Invalid magic byte for ${fmt.label}`);
      }
    }

    summary[fmt.label] = {
      avg_ms: totalMs / iterations,
      avg_size: totalSize / iterations,
    };
  }

  console.table(summary);
  result.recordArtifact("benchmark_summary", summary);
  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
