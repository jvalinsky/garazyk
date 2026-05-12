import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Labeler Subscription");
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

  const labelerRecord = {
    $type: "app.bsky.labeler.service",
    policies: { labelValueDefinitions: [] },
    createdAt: now(),
  };

  await timedCall(result, "Marcus creates labeler service", async () => {
    return await pds.records.createRecord(marcus.did, "app.bsky.labeler.service", labelerRecord, marcus.accessJwt, { rkey: "self" });
  });

  await timedCall(result, "Luna subscribes to Marcus's labeler", async () => {
    const prefs = [
      {
        $type: "app.bsky.actor.defs#contentLabelPref",
        labelerDid: marcus.did,
        label: "test-label",
        visibility: "show"
      }
    ];
    return await pds.search.putPreferences(prefs, luna.accessJwt);
  });

  await new Promise(r => setTimeout(r, 2000));

  await timedCall(result, "Get labeler services", async () => {
    return await appview.raw.xrpcGet("app.bsky.labeler.getServices", { dids: [marcus.did] }, luna.accessJwt);
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
