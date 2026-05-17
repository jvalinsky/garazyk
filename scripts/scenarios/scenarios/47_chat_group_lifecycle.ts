/**
 * @module scenarios/47_chat_group_lifecycle
 *
 * Scenario: 47 chat group lifecycle
 *
 * Behavior:
 * - Executes the 47 chat group lifecycle scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import {
  chatGetConvoForMembers,
  chatGetMessages,
  chatListConvos,
  chatSendMessage,
  chatXrpcPost,
  createChatServiceContext,
} from "@garazyk/atproto-client/seed";
import { ScenarioResult } from "@garazyk/scenario-runner";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/scenario-runner";
export type { ScenarioReport } from "@garazyk/scenario-runner";
import { XrpcClient } from "@garazyk/atproto-client";
import { assert } from "@garazyk/scenario-runner";
import { getCharacter, PDS1, SERVICE_URLS } from "@garazyk/scenario-runner";
import { timedCall } from "@garazyk/scenario-runner";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Chat Group Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const chatUrl = Deno.env.get("CHAT_URL") || SERVICE_URLS.chat || "http://localhost:2585";
  const chatContext = createChatServiceContext(
    pds,
    chatUrl,
    Deno.env.get("CHAT_SERVICE_DID") || undefined,
  );
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  const rosa = getCharacter("rosa");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Chat service health check", async () => {
    await chatContext.chatClient.waitForHealthy(30);
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
    return await chatGetConvoForMembers(chatContext, luna.accessJwt, [
      luna.did,
      marcus.did,
      rosa.did,
    ]);
  });

  if (convo?.convo?.id) {
    const convoId = convo.convo.id;

    await timedCall(result, "Luna sends message", async () => {
      return await chatSendMessage(chatContext, luna.accessJwt, convoId, "Hello group!");
    });

    await new Promise((r) => setTimeout(r, 1000));

    await timedCall(result, "Marcus retrieves conversations", async () => {
      return await chatListConvos(chatContext, marcus.accessJwt, 10);
    });

    await timedCall(result, "Marcus reads messages", async () => {
      return await chatGetMessages(chatContext, marcus.accessJwt, convoId, 20);
    });

    await timedCall(result, "Marcus mutes group", async () => {
      return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.muteConvo", {
        convoId,
      });
    });

    await timedCall(result, "Rosa leaves group", async () => {
      return await chatXrpcPost(chatContext, rosa.accessJwt, "chat.bsky.convo.leaveConvo", {
        convoId,
      });
    });

    await timedCall(result, "Verify state", async () => {
      return await chatGetMessages(chatContext, luna.accessJwt, convoId, 20);
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
