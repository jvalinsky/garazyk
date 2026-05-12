import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("The Depth Charger");
  result.start();

  const client = new XrpcClient(PDS1);
  const marcus = getCharacter("marcus");

  await timedCall(result, "Server health check", async () => {
    await client.wait_for_healthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create Marcus", async () => {
    return await client.accounts.createAccount(marcus.handle, marcus.email, marcus.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  marcus.did = session.did;
  marcus.accessJwt = session.accessJwt;

  // 1. Lexicon Nesting Limit
  let deepMap: any = { a: "b" };
  for (let i = 0; i < 40; i++) {
    deepMap = { n: deepMap };
  }

  await timedCall(
    result, "Reject 32-level Lexicon nesting",
    async () => {
      await client.records.createRecord(
        marcus.did, "app.bsky.feed.post",
        { $type: "app.bsky.feed.post", text: "too deep", createdAt: now(), testExtra: deepMap },
        marcus.accessJwt
      );
    },
    undefined,
    true // Expect failure
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
