import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Thread Gating & Reply Controls");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  await timedCall(result, "PDS health check", async () => { await pds.wait_for_healthy(30); });

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

  // Post 1: Nobody can reply
  const gatedRkey = `nobody-${Date.now()}`;
  const gatedPost = {
    $type: "app.bsky.feed.post",
    text: "This post has no replies allowed",
    createdAt: now(),
  };

  const gatedRef = await timedCall(result, "Create post with no-reply gate", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", gatedPost, luna.accessJwt, { rkey: gatedRkey });
  });

  if (gatedRef) {
    const gatedUri = gatedRef.uri;
    const gatedCid = gatedRef.cid;

    await timedCall(result, "Create thread gate (nobody)", async () => {
      const gateRecord = {
        $type: "app.bsky.feed.threadgate",
        post: gatedUri,
        allow: [],
        createdAt: now(),
      };
      return await pds.records.createRecord(luna.did, "app.bsky.feed.threadgate", gateRecord, luna.accessJwt, { rkey: gatedRkey });
    });

    const replyRecord = {
      $type: "app.bsky.feed.post",
      text: "This reply should be rejected",
      createdAt: now(),
      reply: {
        root: { uri: gatedUri, cid: gatedCid },
        parent: { uri: gatedUri, cid: gatedCid },
      },
    };

    await timedCall(
      result, "Verify Marcus's reply rejected (nobody gate)",
      async () => {
        await pds.records.createRecord(marcus.did, "app.bsky.feed.post", replyRecord, marcus.accessJwt);
      },
      undefined,
      true // Expect failure
    );
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
