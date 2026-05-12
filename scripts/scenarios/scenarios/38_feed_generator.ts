import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Feed Generator Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => { await pds.wait_for_healthy(30); });

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

  const feedRkey = `test-feed-${Date.now()}`;
  const feedRecord = {
    $type: "app.bsky.feed.generator",
    did: luna.did,
    displayName: "Luna's Test Feed",
    description: "A curated feed for testing",
    createdAt: now(),
  };

  const feedRef = await timedCall(result, "Create feed generator", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.generator", feedRecord, luna.accessJwt, { rkey: feedRkey });
  });

  if (feedRef) {
    const feedUri = feedRef.uri;
    await new Promise(r => setTimeout(r, 2000));

    await timedCall(result, "Get feed generator from AppView", async () => {
      // Note: XrpcClient.feed.getFeedGenerators handles join(",") 
      return await appview.feed.getFeedGenerators([feedUri], luna.accessJwt);
    });

    await timedCall(result, "Get custom feed", async () => {
      return await appview.feed.getFeed(feedUri, luna.accessJwt, 10);
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
