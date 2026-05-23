/**
 * @module scenarios/44_content_embedding
 *
 * Scenario: Creates posts with image, quote, and external embeds.
 *
 * Behavior:
 * - Executes the 44 content embedding scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */


const MINIMAL_PNG = new Uint8Array([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xde,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xfc,
  0xff,
  0x9f,
  0xa1,
  0x1e,
  0x00,
  0x07,
  0x82,
  0x02,
  0x3c,
  0x3f,
  0xc8,
  0x48,
  0xef,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Content Embedding");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getActor("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(
    () => pds.accounts.createSession(luna.handle, luna.password),
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const blobResp = await timedCall(result, "Upload image blob", async () => {
    return await pds.blobs.uploadBlob(MINIMAL_PNG, "image/png", luna.accessJwt);
  });

  if (blobResp?.blob) {
    await timedCall(result, "Create post with image embed", async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: "Check out this image!",
        createdAt: now(),
        embed: {
          $type: "app.bsky.embed.images",
          images: [{ alt: "A test image", image: blobResp.blob }],
        },
      }, luna.accessJwt);
    });
  }

  const baseRef = await timedCall(result, "Create base post", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "Original post",
      createdAt: now(),
    }, luna.accessJwt);
  });

  if (baseRef) {
    await timedCall(result, "Create quote post", async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: "Quoting!",
        createdAt: now(),
        embed: { $type: "app.bsky.embed.record", record: { uri: baseRef.uri, cid: baseRef.cid } },
      }, luna.accessJwt);
    });
  }

  await timedCall(result, "Create link card post", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "Check this out!",
      createdAt: now(),
      embed: {
        $type: "app.bsky.embed.external",
        external: { uri: "https://example.com", title: "Example", description: "Desc" },
      },
    }, luna.accessJwt);
  });

  await new Promise((r) => setTimeout(r, 2000));

  if (baseRef) {
    await timedCall(result, "Verify posts retrievable", async () => {
      return await appview.feed.getPosts([baseRef.uri], luna.accessJwt);
    });

    await timedCall(result, "Get post thread with embeds", async () => {
      return await appview.feed.getPostThread(baseRef.uri, luna.accessJwt);
    });
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
