/**
 * @module scenarios/51_blob_garbage_collection
 *
 * Scenario: 51 blob garbage collection
 *
 * Behavior:
 * - Executes the 51 blob garbage collection scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

function makePng(): Uint8Array {
  return new Uint8Array([
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
}

function blobCid(resp: any): string {
  return resp?.blob?.ref?.$link || resp?.blob?.cid || "";
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("The Blob Janitor");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(
    luna.handle,
    luna.email,
    luna.password,
  ).catch(
    () => pds.accounts.createSession(luna.handle, luna.password),
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const keepBlob = await timedCall(
    result,
    "Upload keep-alive snapshot",
    async () => {
      return await pds.blobs.uploadBlob(makePng(), "image/png", luna.accessJwt);
    },
  );

  const doomedBlob = await timedCall(
    result,
    "Upload doomed snapshot",
    async () => {
      return await pds.blobs.uploadBlob(makePng(), "image/png", luna.accessJwt);
    },
  );

  const keepCid = blobCid(keepBlob);
  const doomedCid = blobCid(doomedBlob);

  if (keepCid && doomedCid) {
    await timedCall(result, "Create keep post", async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: "Stays",
        createdAt: now(),
        embed: {
          $type: "app.bsky.embed.images",
          images: [{ alt: "green", image: keepBlob.blob }],
        },
      }, luna.accessJwt);
    });

    const doomedPost = await timedCall(
      result,
      "Create doomed post",
      async () => {
        return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
          $type: "app.bsky.feed.post",
          text: "Goes",
          createdAt: now(),
          embed: {
            $type: "app.bsky.embed.images",
            images: [{ alt: "red", image: doomedBlob.blob }],
          },
        }, luna.accessJwt);
      },
    );

    if (doomedPost) {
      const rkey = doomedPost.uri.split("/").pop();
      await timedCall(result, "Delete doomed post", async () => {
        return await pds.records.deleteRecord(
          luna.did,
          "app.bsky.feed.post",
          rkey,
          luna.accessJwt,
        );
      });

      await timedCall(result, "Delete orphaned blob", async () => {
        return await pds.raw.xrpcPost(
          "com.atproto.repo.deleteBlob",
          { blob: doomedCid },
          luna.accessJwt,
        );
      });

      // Verification
      let doomed404 = false;
      for (let i = 0; i < 10; i++) {
        const res = await fetch(
          `${ctx.pds1}/xrpc/com.atproto.sync.getBlob?did=${luna.did}&cid=${doomedCid}`,
        );
        if (res.status === 404) {
          doomed404 = true;
          break;
        }
        await new Promise((r) => setTimeout(r, 1000));
      }
      assert.isTrue(doomed404, "Doomed blob not deleted");
      result.stepPassed("Doomed blob returns 404");

      const keepRes = await fetch(
        `${ctx.pds1}/xrpc/com.atproto.sync.getBlob?did=${luna.did}&cid=${keepCid}`,
      );
      assert.isTrue(keepRes.status === 200, "Keep-alive blob missing");
      result.stepPassed("Keep-alive blob still downloads");
    }
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
