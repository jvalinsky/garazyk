import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1 } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Chat Group Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  const rosa = getCharacter("rosa");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  for (const char of [luna, marcus, rosa]) {
    const session = await pds.accounts.createAccount(char.handle, char.email, char.password).catch(
      () => pds.accounts.createSession(char.handle, char.password),
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  // Create a group conversation
  const convo = await timedCall(result, "Create group conversation", async () => {
    return await pds.raw.xrpcGet("chat.bsky.convo.getConvoForMembers", {
      members: [luna.did, marcus.did, rosa.did],
    }, luna.accessJwt);
  });

  if (convo?.convo?.id) {
    const convoId = convo.convo.id;

    await timedCall(result, "Luna sends message", async () => {
      return await pds.raw.xrpcPost("chat.bsky.convo.sendMessage", {
        convoId,
        message: { $type: "chat.bsky.convo.message", text: "Hello group!", createdAt: now() },
      }, luna.accessJwt);
    });

    await new Promise((r) => setTimeout(r, 1000));

    await timedCall(result, "Marcus retrieves conversations", async () => {
      return await pds.raw.xrpcGet("chat.bsky.convo.listConvos", { limit: 10 }, marcus.accessJwt);
    });

    await timedCall(result, "Marcus reads messages", async () => {
      return await pds.raw.xrpcGet(
        "chat.bsky.convo.getMessages",
        { convoId, limit: 20 },
        marcus.accessJwt,
      );
    });

    await timedCall(result, "Marcus mutes group", async () => {
      return await pds.raw.xrpcPost("chat.bsky.convo.muteConvo", { convoId }, marcus.accessJwt);
    });

    await timedCall(result, "Rosa leaves group", async () => {
      return await pds.raw.xrpcPost("chat.bsky.convo.leaveConvo", { convoId }, rosa.accessJwt);
    });

    await timedCall(result, "Verify state", async () => {
      return await pds.raw.xrpcGet(
        "chat.bsky.convo.getMessages",
        { convoId, limit: 20 },
        luna.accessJwt,
      );
    });
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
