import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("List Management");
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

  const listRkey = `curate-list-${Date.now()}`;
  const listRecord = {
    $type: "app.bsky.graph.list",
    purpose: "app.bsky.graph.defs#curatelist",
    name: "Luna's Favorites",
    description: "Accounts Luna finds interesting",
    createdAt: now(),
  };

  const listRef = await timedCall(result, "Create curate list", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.graph.list", listRecord, luna.accessJwt, { rkey: listRkey });
  });

  if (listRef) {
    const listUri = listRef.uri;
    const itemRkey = `item-${Date.now()}`;
    
    await timedCall(result, "Add Marcus to list", async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.graph.listitem", {
        $type: "app.bsky.graph.listitem",
        list: listUri,
        subject: marcus.did,
        createdAt: now()
      }, luna.accessJwt, { rkey: itemRkey });
    });

    await new Promise(r => setTimeout(r, 2000));

    await timedCall(result, "Get lists for Luna", async () => {
      // Note: appview.graph.getLists doesn't exist yet, I'll use raw
      return await appview.raw.xrpcGet("app.bsky.graph.getLists", { actor: luna.did, limit: 10 }, luna.accessJwt);
    });

    await timedCall(result, "Get list items", async () => {
      return await appview.raw.xrpcGet("app.bsky.graph.getList", { list: listUri, limit: 10 }, luna.accessJwt);
    });

    await timedCall(result, "Remove Marcus from list", async () => {
      return await pds.records.deleteRecord(luna.did, "app.bsky.graph.listitem", itemRkey, luna.accessJwt);
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
