/**
 * @module scenarios/06_chat_dms
 *
 * Scenario: Tests chat and Direct Messaging (DM) functionality including group chats.
 *
 * Behavior:
 * - Luna, Marcus, Rosa, and Volt accounts are created.
 * - Verify default incoming message declaration for Luna.
 * - Perform DM exchange between Luna and Marcus.
 * - Verify non-member cannot send messages into existing DM.
 * - Marcus mutes, lists, and reads messages in conversation.
 * - Marcus updates chat declaration to 'none' and verifies access rejection.
 * - Marcus restores chat declaration.
 * - Rosa creates a group chat and manages memberships.
 * - Luna marks conversation as read, and Marcus unmutes and leaves the conversation.
 *
 * Expectations:
 * - All chat service interactions succeed as expected.
 * - Authentication and authorization rules for messaging are enforced.
 * - Group and DM lifecycle management functions correctly.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcError } from "../../lib/deno/transport.ts";
import { chatXrpcGet, chatXrpcPost, createChatServiceContext } from "../../lib/deno/seed.ts";

async function putChatDeclaration(did: string, token: string, allowIncoming: "all" | "none") {
  const response = await fetch(`${PDS1}/xrpc/com.atproto.repo.putRecord`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      repo: did,
      collection: "chat.bsky.actor.declaration",
      rkey: "self",
      record: {
        $type: "chat.bsky.actor.declaration",
        allowIncoming,
      },
    }),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`putRecord chat declaration failed (${response.status}): ${body}`);
  }

  const readback = await fetch(
    `${PDS1}/xrpc/com.atproto.repo.getRecord?repo=${encodeURIComponent(did)}&collection=chat.bsky.actor.declaration&rkey=self`,
  );
  const readbackBody = await readback.text();
  if (!readback.ok) {
    throw new Error(`chat declaration readback failed (${readback.status}): ${readbackBody}`);
  }
  const parsed = JSON.parse(readbackBody);
  assert.equal(parsed.value?.allowIncoming, allowIncoming, `Expected allowIncoming=${allowIncoming}`);
  return JSON.parse(body);
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Chat & DMs");
  result.start();

  const client = new XrpcClient(PDS1);
  const chatUrl = Deno.env.get("CHAT_URL") || SERVICE_URLS.chat || "http://localhost:2585";
  const chatContext = createChatServiceContext(
    client,
    chatUrl,
    Deno.env.get("CHAT_SERVICE_DID") || undefined,
  );

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );
  await timedCall(
    result,
    "Chat service health check",
    async () => {
      await chatContext.chatClient.waitForHealthy(30);
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e) {
          if (e instanceof Error && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
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

  await timedCall(
    result,
    "Luna gets default chat declaration",
    async () => {
      const declaration = await chatXrpcGet(
        chatContext,
        luna.accessJwt,
        "chat.bsky.actor.declaration",
        {},
      );
      assert.equal(
        declaration?.value?.allowIncoming,
        "all",
        "Default chat declaration should allow incoming messages",
      );
      return declaration;
    },
  );

  const convo = await timedCall(
    result,
    "Luna gets/creates DM convo with Marcus",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getConvoForMembers", {
        members: [luna.did, marcus.did],
      });
    },
  );

  const convoId = convo?.convo?.id;

  const lunaMsg = await timedCall(
    result,
    "Luna sends DM to Marcus",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.sendMessage", {
        convoId: convoId || "default",
        message: { text: "Hey Marcus! Want to collaborate on a space-tech project?" },
      });
    },
  );

  const lunaMsgId = lunaMsg?.id;

  await timedCall(
    result,
    "Marcus replies to Luna's DM",
    async () => {
      return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.sendMessage", {
        convoId: convoId || "default",
        message: {
          text: "Absolutely! I've been thinking about ATProto + space data. Let's do it!",
        },
      });
    },
  );

  await timedCall(
    result,
    "Non-member cannot send to Luna and Marcus DM",
    async () => {
      try {
        await chatXrpcPost(chatContext, volt.accessJwt, "chat.bsky.convo.sendMessage", {
          convoId: convoId || "default",
          message: { text: "I should not be able to write into this DM." },
        });
      } catch (error) {
        if (error instanceof XrpcError && error.status === 403) {
          return { rejected: true };
        }
        throw error;
      }
      throw new Error("Expected non-member sendMessage to be rejected with 403");
    },
  );

  await timedCall(
    result,
    "Marcus lists conversations",
    async () => {
      return await chatXrpcGet(chatContext, marcus.accessJwt, "chat.bsky.convo.listConvos", {
        limit: 10,
      });
    },
  );

  if (convoId) {
    await timedCall(
      result,
      "Marcus gets conversation messages",
      async () => {
        return await chatXrpcGet(chatContext, marcus.accessJwt, "chat.bsky.convo.getMessages", {
          convoId: convoId,
          limit: 20,
        });
      },
    );

    await timedCall(
      result,
      "Marcus mutes conversation",
      async () => {
        return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.muteConvo", {
          convoId: convoId,
        });
      },
    );
  }

  await timedCall(
    result,
    "Marcus blocks new incoming conversations",
    async () => {
      return await putChatDeclaration(marcus.did!, marcus.accessJwt!, "none");
    },
  );

  await timedCall(
    result,
    "Chat respects allowIncoming none",
    async () => {
      try {
        await chatXrpcGet(chatContext, rosa.accessJwt, "chat.bsky.convo.getConvoForMembers", {
          members: [rosa.did, marcus.did],
        });
      } catch (error) {
        if (error instanceof XrpcError && error.status === 403) {
          return { rejected: true };
        }
        throw error;
      }
      throw new Error("Expected getConvoForMembers to be rejected by allowIncoming=none");
    },
  );

  await timedCall(
    result,
    "Marcus restores incoming chat declaration",
    async () => {
      return await putChatDeclaration(marcus.did!, marcus.accessJwt!, "all");
    },
  );

  const group = await timedCall(
    result,
    "Rosa creates group chat",
    async () => {
      return await chatXrpcPost(chatContext, rosa.accessJwt, "chat.bsky.group.createGroup", {
        name: "Food & Space Enthusiasts",
        members: [luna.did, volt.did],
      });
    },
  );

  const groupId = group?.group?.id;

  if (groupId) {
    await timedCall(
      result,
      "Rosa adds member to group",
      async () => {
        return await chatXrpcPost(chatContext, rosa.accessJwt, "chat.bsky.group.addMember", {
          groupId: groupId,
          did: marcus.did,
        });
      },
    );

    await timedCall(
      result,
      "Rosa gets group info",
      async () => {
        return await chatXrpcGet(chatContext, rosa.accessJwt, "chat.bsky.group.getGroup", {
          groupId: groupId,
        });
      },
    );
  }

  if (convoId && lunaMsgId) {
    await timedCall(
      result,
      "Luna marks conversation as read",
      async () => {
        return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.updateRead", {
          convoId: convoId,
          messageId: lunaMsgId,
        });
      },
    );
  }

  if (convoId) {
    await timedCall(
      result,
      "Marcus unmutes conversation",
      async () => {
        return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.unmuteConvo", {
          convoId: convoId,
        });
      },
    );

    await timedCall(
      result,
      "Marcus leaves conversation",
      async () => {
        return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.leaveConvo", {
          convoId: convoId,
        });
      },
    );
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
