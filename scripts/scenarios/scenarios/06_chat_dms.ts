import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Chat & DMs");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result, "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    }
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({ handle: char.handle, email: char.email, password: char.password });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({ identifier: char.handle, password: char.password });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  const rosa = getCharacter("rosa");
  const volt = getCharacter("volt");

  if (!luna.did || !marcus.did || !rosa.did || !volt.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  const convo = await timedCall(
    result, "Luna gets/creates DM convo with Marcus",
    async () => {
      return await client.raw.get("chat.bsky.convo.getConvoForMembers", {
        members: [luna.did, marcus.did]
      }, luna.accessJwt);
    }
  );
  
  const convoId = convo?.convo?.id;

  const lunaMsg = await timedCall(
    result, "Luna sends DM to Marcus",
    async () => {
      return await client.raw.post("chat.bsky.convo.sendMessage", {
        convoId: convoId || "default",
        message: {
          $type: "chat.bsky.convo.message",
          text: "Hey Marcus! Want to collaborate on a space-tech project?",
          createdAt: now()
        }
      }, luna.accessJwt);
    }
  );
  
  const lunaMsgId = lunaMsg?.id;

  await timedCall(
    result, "Marcus replies to Luna's DM",
    async () => {
      return await client.raw.post("chat.bsky.convo.sendMessage", {
        convoId: convoId || "default",
        message: {
          $type: "chat.bsky.convo.message",
          text: "Absolutely! I've been thinking about ATProto + space data. Let's do it!",
          createdAt: now()
        }
      }, marcus.accessJwt);
    }
  );

  await timedCall(
    result, "Marcus lists conversations",
    async () => {
      return await client.raw.get("chat.bsky.convo.listConvos", { limit: 10 }, marcus.accessJwt);
    }
  );

  if (convoId) {
    await timedCall(
      result, "Marcus gets conversation messages",
      async () => {
        return await client.raw.get("chat.bsky.convo.getMessages", {
          convoId: convoId,
          limit: 20
        }, marcus.accessJwt);
      }
    );

    await timedCall(
      result, "Marcus mutes conversation",
      async () => {
        return await client.raw.post("chat.bsky.convo.muteConvo", {
          convoId: convoId
        }, marcus.accessJwt);
      }
    );
  }

  const group = await timedCall(
    result, "Rosa creates group chat",
    async () => {
      return await client.raw.post("chat.bsky.group.createGroup", {
        name: "Food & Space Enthusiasts",
        members: [luna.did, volt.did]
      }, rosa.accessJwt);
    }
  );
  
  const groupId = group?.group?.id;

  if (groupId) {
    await timedCall(
      result, "Rosa adds member to group",
      async () => {
        return await client.raw.post("chat.bsky.group.addMember", {
          groupId: groupId,
          did: marcus.did
        }, rosa.accessJwt);
      }
    );

    await timedCall(
      result, "Rosa gets group info",
      async () => {
        return await client.raw.get("chat.bsky.group.getGroup", {
          groupId: groupId
        }, rosa.accessJwt);
      }
    );
  }

  if (convoId && lunaMsgId) {
    await timedCall(
      result, "Luna marks conversation as read",
      async () => {
        return await client.raw.post("chat.bsky.convo.updateRead", {
          convoId: convoId,
          messageId: lunaMsgId
        }, luna.accessJwt);
      }
    );
  }

  if (convoId) {
    await timedCall(
      result, "Marcus unmutes conversation",
      async () => {
        return await client.raw.post("chat.bsky.convo.unmuteConvo", {
          convoId: convoId
        }, marcus.accessJwt);
      }
    );

    await timedCall(
      result, "Marcus leaves conversation",
      async () => {
        return await client.raw.post("chat.bsky.convo.leaveConvo", {
          convoId: convoId
        }, marcus.accessJwt);
      }
    );
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
