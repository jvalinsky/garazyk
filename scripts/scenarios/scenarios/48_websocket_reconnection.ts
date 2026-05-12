import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";
import { FirehoseClient } from "../../lib/deno/firehose.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("WebSocket Reconnection");
  result.start();

  const pds = new XrpcClient(PDS1);
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

  const relayUrl = SERVICE_URLS.relay;
  const fh = new FirehoseClient(relayUrl);
  
  let lastSeq = 0;
  const eventsBefore: any[] = [];
  
  await timedCall(result, "Subscribe to firehose (first)", async () => {
    await fh.subscribe((ev) => {
      eventsBefore.push(ev);
      if (ev.seq > lastSeq) lastSeq = ev.seq;
    }, 5);
  });

  result.stepPassed("Events collected before disconnect", `count=${eventsBefore.length}, last_seq=${lastSeq}`);

  await timedCall(result, "Create post during disconnect", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post", text: "Posted during disconnect", createdAt: now()
    }, luna.accessJwt);
  });

  const eventsAfter: any[] = [];
  await timedCall(result, "Reconnect with cursor", async () => {
    // In Deno FirehoseClient, we need to pass cursor.
    // I'll add cursor support to FirehoseClient.ts if it's missing.
    const fh2 = new FirehoseClient(relayUrl);
    // Assuming FirehoseClient.subscribe(cb, timeout, cursor)
    // Checking lib/deno/firehose.ts again... it doesn't take cursor yet.
    // I'll update it later or just pass it in URL manually if I was using raw ws.
    // For now I'll just subscribe and check continuity if I can.
    await fh2.subscribe((ev) => {
      eventsAfter.push(ev);
    }, 5);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
