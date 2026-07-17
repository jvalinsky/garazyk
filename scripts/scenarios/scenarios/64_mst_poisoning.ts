/**
 * @module scenarios/64_mst_poisoning
 *
 * Scenario: MST Exploitation (Merkle Search Tree Poisoning)
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("MST Exploitation");
  result.start();
  
  const client = new XrpcClient(PDS1);
  const troll = getActor("troll");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(result, "Create Troll", async () => {
    return await client.accounts.createAccount(troll.handle, troll.email, troll.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  troll.did = session.did;
  troll.accessJwt = session.accessJwt;

  await timedCall(result, "Create colliding records", async () => {
    const writes = [];
    const basePrefix = "poison1234";
    for (let i = 0; i < 500; i++) {
      const suffix = i.toString().padStart(3, "0");
      writes.push({
        $type: "com.atproto.repo.applyWrites#create",
        collection: "app.bsky.feed.post",
        rkey: basePrefix + suffix,
        value: {
          $type: "app.bsky.feed.post",
          text: "Poison record " + i,
          createdAt: new Date().toISOString()
        }
      });
    }

    try {
      await client.records.applyWrites(troll.did, writes, troll.accessJwt);
    } catch (err: any) {
      if (err.message.includes("MST depth") || err.message.includes("400") || err.message.includes("Rate")) {
        // Expected rejection or limits
        return;
      }
      throw err;
    }
  });

  await timedCall(result, "Post-attack health check", async () => {
    await client.waitForHealthy(10);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
