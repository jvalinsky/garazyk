import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Cross-Service Consistency");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => { await pds.waitForHealthy(30); });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(() => 
    pds.accounts.createSession(luna.handle, luna.password)
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const postRkey = `consistency-${Date.now()}`;
  const postText = "Testing consistency!";
  const postRef = await timedCall(result, "Create post on PDS", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post", text: postText, createdAt: now()
    }, luna.accessJwt, { rkey: postRkey });
  });

  if (postRef) {
    const postUri = postRef.uri;
    let found = false;
    for (let i = 0; i < 15; i++) {
      try {
        const avPost = await appview.feed.getPosts([postUri], luna.accessJwt);
        if (avPost.posts?.length > 0) {
          found = true;
          break;
        }
      } catch { /* ignore */ }
      await new Promise(r => setTimeout(r, 1000));
    }

    if (found) {
      result.stepPassed("AppView indexed post");
      const avPost = await appview.feed.getPosts([postUri], luna.accessJwt);
      const avText = avPost.posts[0].record?.text;
      assert.isTrue(avText === postText, `Content drift: ${avText} !== ${postText}`);
      result.stepPassed("PDS-AppView content match");
    } else {
      result.stepFailed("AppView index timeout", "Post not found after 15s");
    }
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
