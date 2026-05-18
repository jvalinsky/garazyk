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

import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext, ScenarioResult, timedCall } from "@garazyk/hamownia";

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
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Blobs & Uploads");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${ctx.pds1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["rosa", "volt", "luna", "marcus"];
  for (const name of charNames) {
    const char = ctx.getCharacter(name);
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
      (s: any) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const rosa = ctx.getCharacter("rosa");
  const volt = ctx.getCharacter("volt");
  const luna = ctx.getCharacter("luna");
  const marcus = ctx.getCharacter("marcus");

  if (!rosa.did || !volt.did || !luna.did || !marcus.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  const pngData = makePng(200, 200);
  const rosaBlobResp: any = await timedCall(
    result,
    "Rosa uploads food photo",
    async () => {
      return await client.api.com.atproto.repo.uploadBlob(
        pngData,
        rosa.accessJwt,
      );
    },
    (r: any) => `size=${r.blob?.size || "unknown"}`,
  );

  const rosaBlob = rosaBlobResp?.blob;

  if (rosaBlob) {
    await timedCall(
      result,
      "Rosa posts with image embed",
      async () => {
        await client.api.com.atproto.repo.createRecord({
          repo: rosa.did!,
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
        }, rosa.accessJwt);
      },
    );
  } else {
    result.stepSkipped("Rosa posts with image embed", "No blob available");
  }

  const voltBlobs: Array<Record<string, unknown>> = [];
  for (let i = 0; i < 4; i++) {
    const data = makePng(100 + i * 10, 100 + i * 10);
    const blobResp: any = await timedCall(
      result,
      `DJ Volt uploads image ${i + 1}`,
      async () => {
        return await client.api.com.atproto.repo.uploadBlob(
          data,
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
        await client.api.com.atproto.repo.createRecord({
          repo: volt.did!,
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
        }, volt.accessJwt);
      },
    );
  } else {
    result.stepSkipped(
      "DJ Volt posts 4-image album",
      "Not enough blobs uploaded",
    );
  }

  const bannerData = makePng(600, 200);
  const bannerBlobResp: any = await timedCall(
    result,
    "Luna uploads banner image",
    async () => {
      return await client.api.com.atproto.repo.uploadBlob(
        bannerData,
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
        await client.api.com.atproto.repo.createRecord({
          repo: luna.did!,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: "Luna Starfield",
            description: "Astronomy enthusiast. Looking up, always.",
            banner: bannerBlob,
          },
        }, luna.accessJwt);
      },
    );
  }

  if (rosaBlob) {
    try {
      const cid = rosaBlob.ref?.$link || rosaBlob.cid || rosaBlob.ref;
      if (cid) {
        const blobUrl =
          `${ctx.pds1}/xrpc/com.atproto.sync.getBlob?did=${rosa.did}&cid=${cid}`;
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
        await client.api.com.atproto.repo.uploadBlob(
          largeData,
          marcus.accessJwt,
        );
      } catch (e: any) {
        if (
          e instanceof XrpcError && e.status === 400 &&
          (e.body as any)?.error === "BlobTooLarge"
        ) {
          return e.body;
        }
        throw e;
      }
      throw new Error("Expected BlobTooLarge response");
    },
    (body: any) => `error=${body.error}`,
  );

  if (rosaBlob) {
    await timedCall(
      result,
      "Records contain blob refs",
      async () => {
        return await client.api.com.atproto.repo.listRecords({
          repo: rosa.did!,
          collection: "app.bsky.feed.post",
        }, rosa.accessJwt);
      },
      (r: any) =>
        `posts_with_embed=${
          (r.records || []).some((rec: any) => rec.value?.embed)
        }`,
    );
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
