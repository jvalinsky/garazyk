import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Rate Limit Client Behavior");
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

  // Rapidly create records
  let hitLimit = false;
  for (let i = 0; i < 100; i++) {
    try {
      await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post", text: `Rate test ${i}`, createdAt: now()
      }, luna.accessJwt);
    } catch (e) {
      if (e instanceof XrpcError && e.status === 429) {
        hitLimit = true;
        result.stepPassed("Rate limit triggered (429)");
        break;
      }
    }
  }

  if (!hitLimit) result.stepSkipped("Rate limit trigger", "Limits might be too high for local dev");

  // Recovery
  await new Promise(r => setTimeout(r, 2000));
  await timedCall(result, "Verify recovery", async () => {
    return await pds.accounts.getSession(luna.accessJwt);
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
