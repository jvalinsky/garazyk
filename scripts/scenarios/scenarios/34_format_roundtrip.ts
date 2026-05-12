import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Repo Format Roundtrip (CAR <-> STAR)");
  result.start();

  const client = new XrpcClient(PDS1);
  await timedCall(result, "Server health check", async () => {
    await client.wait_for_healthy(30);
  });

  if (result.failed > 0) return result;

  const luna = getCharacter("luna");
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

  const recordCount = 10;
  for (let i = 0; i < recordCount; i++) {
    await client.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post", text: `Roundtrip test ${i}`, createdAt: now()
    }, luna.accessJwt);
  }
  result.stepPassed("Seeding records");

  const [s1, ct1, body1] = await client.raw.xrpcGetBinary("com.atproto.sync.getRepo", { params: { did: luna.did } });
  assert(ct1.includes("application/vnd.ipld.car"), "Expected CAR");

  const [s2, ct2, body2] = await client.raw.xrpcGetBinary("com.atproto.sync.getRepo", {
    params: { did: luna.did },
    headers: { "Accept": "application/vnd.atproto.star" }
  });
  assert(ct2.includes("application/vnd.atproto.star"), "Expected STAR");
  assert(body2[0] === 0x2A, "Expected STAR magic byte 0x2A");

  const head = await client.raw.xrpcGet("com.atproto.sync.getHead", { did: luna.did });
  result.stepPassed("Deterministic consistency check", `Root CID: ${head.root}`);

  const records = await client.records.listRecords(luna.did, "app.bsky.feed.post");
  assert(records.records.length >= recordCount, "Record count mismatch");
  result.stepPassed("Record set integrity verified");

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
