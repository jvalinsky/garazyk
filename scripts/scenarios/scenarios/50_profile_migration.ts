import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

function makePng(width: number, height: number): Uint8Array {
  // Simple 1x1 PNG-like or just enough for a blob
  return new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xde, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xfc, 0xff, 0x9f, 0xa1,
    0x1e, 0x00, 0x07, 0x82, 0x02, 0x3c, 0x3f, 0xc8, 0x48, 0xef, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
  ]);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("The Profile Evolution");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  await timedCall(result, "PDS health check", async () => { await pds.waitForHealthy(30); });

  if (result.failed > 0) return result;

  for (const char of [luna, marcus]) {
    const session = await pds.accounts.createAccount(char.handle, char.email, char.password).catch(() => 
      pds.accounts.createSession(char.handle, char.password)
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const avatarV1 = await timedCall(result, "Luna uploads first portrait", async () => {
    return await pds.blobs.uploadBlob(makePng(64, 64), "image/png", luna.accessJwt);
  });

  const bannerV1 = await timedCall(result, "Luna uploads first banner", async () => {
    return await pds.blobs.uploadBlob(makePng(64, 64), "image/png", luna.accessJwt);
  });

  if (avatarV1?.blob && bannerV1?.blob) {
    const initialProfile = {
      $type: "app.bsky.actor.profile",
      displayName: "Luna Starfield",
      description: luna.persona,
      avatar: avatarV1.blob,
      banner: bannerV1.blob,
    };

    await timedCall(result, "Luna writes opening profile", async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.actor.profile", initialProfile, luna.accessJwt, { rkey: "self" });
    });

    const newName = "Luna Reframed";
    await timedCall(result, "Luna sharpens display name", async () => {
      return await pds.records.putRecord(luna.did, "app.bsky.actor.profile", "self", {
        ...initialProfile, displayName: newName
      }, luna.accessJwt);
    });

    const avatarV2 = await timedCall(result, "Luna trades portrait", async () => {
      return await pds.blobs.uploadBlob(makePng(64, 64), "image/png", luna.accessJwt);
    });

    if (avatarV2?.blob) {
      await timedCall(result, "Luna swaps portrait", async () => {
        return await pds.records.putRecord(luna.did, "app.bsky.actor.profile", "self", {
          ...initialProfile, displayName: newName, avatar: avatarV2.blob
        }, luna.accessJwt);
      });
    }

    await new Promise(r => setTimeout(r, 2000));

    await timedCall(result, "AppView catches final profile", async () => {
      const profile = await appview.feed.getProfile(luna.did, luna.accessJwt);
      assert.isTrue(profile.displayName === newName, "Display name mismatch");
    });
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
