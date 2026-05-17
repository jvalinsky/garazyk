#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  chatGetMessages,
  chatListConvos,
  chatServiceDidForUrl,
  createChatServiceContext,
} from "@garazyk/gruszka/seed";

const pdsUrl = (Deno.env.get("PDS_URL") || "").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "";
const password = Deno.env.get("TEST_PASSWORD") || "";
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "100");

if (!pdsUrl || !chatUrl || !handle || !password) {
  console.error(
    "PDS_URL, CHAT_URL, TEST_HANDLE, and TEST_PASSWORD environment variables are required.",
  );
  Deno.exit(1);
}

async function main() {
  const pdsClient = new XrpcClient(pdsUrl);
  const context = createChatServiceContext(pdsClient, chatUrl, chatServiceDidForUrl(chatUrl));

  const session = await pdsClient.api.com.atproto.server.createSession({
    identifier: handle,
    password,
  }) as any;
  const jwt = session.accessJwt;

  const convoResp = await chatListConvos(context, jwt, 100);
  for (const convo of convoResp.convos) {
    const msgResp = await chatGetMessages(context, jwt, convo.id, messageLimit);
    console.log(`Convo ${convo.id}: ${msgResp.messages.length} messages`);
  }
}

if (import.meta.main) {
  await main();
}
