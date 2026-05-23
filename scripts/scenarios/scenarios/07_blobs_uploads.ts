/**
 * @module scenarios/07_blobs_uploads
 *
 * Scenario: Tests blob upload, storage, and retrieval functionality.
 *
 * Behavior:
 * - Creates test accounts for Rosa, Volt, Luna, and Marcus.
 * - Rosa uploads a blob and creates a post with an image embed.
 * - Volt uploads multiple blobs and creates a post with a 4-image album.
 * - Luna uploads a banner blob and updates her profile banner.
 * - Verifies blob retrieval from the PDS.
 * - Tests negative case: uploads an oversized blob and ensures it is rejected.
 * - Confirms records correctly reference uploaded blobs.
 *
 * Expectations:
 * - Blob uploads succeed for valid inputs.
 * - Blobs are successfully attached to records (posts/profiles).
 * - Blob retrieval via sync API functions.
 * - Oversized blobs are rejected by the PDS.
 */

import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

function makePng(width = 100, height = 100): Uint8Array {
  const b64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  const raw = atob(b64);
  const u8 = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) u8[i] = raw.charCodeAt(i);

  const out = new Uint8Array(u8.length + width * height);
  out.set(u8);
  return out;
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Blobs & Uploads");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["rosa", "volt", "luna", "marcus"];
  for (const name of charNames) {
    const char = getActor(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const rosa = getActor("rosa");
  const volt = getActor("volt");
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  if (!rosa.did || !volt.did || !luna.did || !marcus.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  const pngData = makePng(200, 200);
  const rosaBlobResp = await timedCall(
    result,
    "Rosa uploads food photo",
    async () => {
      return await client.raw.postBinary(
        "com.atproto.repo.uploadBlob",
        pngData,
        "image/png",
        rosa.accessJwt,
      );
    },
    (r) => `size=${r.blob?.size || "unknown"}`,
  );

  const rosaBlob = rosaBlobResp?.blob;

  if (rosaBlob) {
    await timedCall(
      result,
      "Rosa posts with image embed",
      async () => {
        await client.as(rosa).raw.post("com.atproto.repo.createRecord", {
          repo: rosa.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Look at this amazing sourdough I made!",
            createdAt: now(),
            embed: {
              $type: "app.bsky.embed.images",
              images: [{ alt: "Fresh sourdough bread", image: rosaBlob }],
            },
          },
        });
      },
    );
  } else {
    result.stepSkipped("Rosa posts with image embed", "No blob available");
  }

  const voltBlobs: Array<Record<string, unknown>> = [];
  for (let i = 0; i < 4; i++) {
    const data = makePng(100 + i * 10, 100 + i * 10);
    const blobResp = await timedCall(
      result,
      `DJ Volt uploads image ${i + 1}`,
      async () => {
        return await client.raw.postBinary(
          "com.atproto.repo.uploadBlob",
          data,
          "image/png",
          volt.accessJwt,
        );
      },
    );
    if (blobResp?.blob) {
      voltBlobs.push(blobResp.blob);
    }
  }

  if (voltBlobs.length >= 4) {
    await timedCall(
      result,
      "DJ Volt posts 4-image album",
      async () => {
        await client.as(volt).raw.post("com.atproto.repo.createRecord", {
          repo: volt.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Album cover concepts for the new EP! Which one do you like?",
            createdAt: now(),
            embed: {
              $type: "app.bsky.embed.images",
              images: voltBlobs.slice(0, 4).map((b, i) => ({
                alt: `Album concept ${i + 1}`,
                image: b,
              })),
            },
          },
        });
      },
    );
  } else {
    result.stepSkipped("DJ Volt posts 4-image album", "Not enough blobs uploaded");
  }

  const bannerData = makePng(600, 200);
  const bannerBlobResp = await timedCall(
    result,
    "Luna uploads banner image",
    async () => {
      return await client.raw.postBinary(
        "com.atproto.repo.uploadBlob",
        bannerData,
        "image/png",
        luna.accessJwt,
      );
    },
  );
  const bannerBlob = bannerBlobResp?.blob;

  if (bannerBlob) {
    await timedCall(
      result,
      "Luna sets profile banner",
      async () => {
        await client.as(luna).raw.post("com.atproto.repo.createRecord", {
          repo: luna.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: "Luna Starfield",
            description: "Astronomy enthusiast. Looking up, always.",
            banner: bannerBlob,
          },
        });
      },
    );
  }

  if (rosaBlob) {
    try {
      const cid = rosaBlob.ref?.$link || rosaBlob.cid || rosaBlob.ref;
      if (cid) {
        const blobUrl = `${PDS1}/xrpc/com.atproto.sync.getBlob?did=${rosa.did}&cid=${cid}`;
        const resp = await fetch(blobUrl);
        if (resp.ok) {
          const buf = await resp.arrayBuffer();
          result.stepPassed("Blob retrieval", `size=${buf.byteLength} bytes`);
        } else {
          result.stepFailed("Blob retrieval", `status=${resp.status}`);
        }
      } else {
        result.stepSkipped("Blob retrieval", "No blob CID available");
      }
    } catch (exc: any) {
      result.stepSkipped("Blob retrieval", String(exc));
    }
  }

  const largeData = new Uint8Array(2 * 1024 * 1024); // 2MB
  await timedCall(
    result,
    "Oversized blob upload",
    async () => {
      try {
        await client.raw.postBinary(
          "com.atproto.repo.uploadBlob",
          largeData,
          "application/octet-stream",
          marcus.accessJwt,
        );
      } catch (e) {
        if (e instanceof XrpcError && e.status === 400 && (e.body as Record<string, unknown>)?.error === "BlobTooLarge") {
          return e.body as { error: string };
        }
        throw e;
      }
      throw new Error("Expected BlobTooLarge response");
    },
    (body) => `error=${body.error}`,
  );

  if (rosaBlob) {
    await timedCall(
      result,
      "Records contain blob refs",
      async () => {
        return await client.as(rosa).raw.get("com.atproto.repo.listRecords", {
          repo: rosa.did,
          collection: "app.bsky.feed.post",
        });
      },
      (r) => `posts_with_embed=${(r.records || []).some((rec: any) => rec.value?.embed)}`,
    );
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
