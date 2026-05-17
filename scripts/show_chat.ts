#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  chatGetMessages,
  chatListConvos,
  chatServiceDidForUrl,
  createChatServiceContext,
} from "@garazyk/gruszka/seed";
import {
  boxBot,
  boxMid,
  boxRow,
  boxTop,
  c,
  getTermWidth,
  printConvo,
} from "@garazyk/gruszka/chat-viewer";

const pdsUrl = (Deno.env.get("PDS_URL") || "").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "";
const password = Deno.env.get("TEST_PASSWORD") || "";
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "100");

const BOLD = 1;
const WHITE = 37;
const DIM = 2;
const BLUE = 94;
const GREEN = 92;
const YELLOW = 93;
const ITALIC = 3;

if (!pdsUrl || !chatUrl || !handle || !password) {
  console.error(
    "PDS_URL, CHAT_URL, TEST_HANDLE, and TEST_PASSWORD environment variables are required.",
  );
  console.error(
    "Usage: PDS_URL=<url> CHAT_URL=<url> TEST_HANDLE=<handle> TEST_PASSWORD=<password> deno run -A show_chat.ts",
  );
  Deno.exit(1);
}

async function main() {
  const pdsClient = new XrpcClient(pdsUrl);
  const serviceDid = chatServiceDidForUrl(chatUrl);
  const context = createChatServiceContext(pdsClient, chatUrl, serviceDid);
  const width = getTermWidth();

  console.log();
  console.log(boxTop(c(" Garazyk Chat Viewer ", BOLD, WHITE)));
  console.log(boxMid());
  console.log(boxRow(c("PDS:  ", DIM) + c(pdsUrl, BLUE), width));
  console.log(boxRow(c("Chat: ", DIM) + c(chatUrl, BLUE), width));
  console.log(boxRow(c("DID:  ", DIM) + c(serviceDid, BLUE), width));
  console.log(boxRow(c("Term: ", DIM) + c(`${width} cols`, DIM), width));
  console.log(boxMid());

  // Login
  const session = await pdsClient.api.com.atproto.server.createSession({
    identifier: handle,
    password,
  }) as any;
  const jwt = session.accessJwt;
  const selfDid = session.did;
  const sHandle = session.handle || handle;

  if (!jwt || !selfDid) {
    throw new Error("Login succeeded but response did not include accessJwt and did");
  }

  console.log(boxRow(c("Auth: ", DIM) + c(sHandle, GREEN, BOLD) + c(` (${selfDid})`, DIM), width));
  console.log(boxBot());
  console.log();

  // Fetch convos
  console.log(c("  Fetching conversations…", DIM, ITALIC));
  const convoResp = await chatListConvos(context, jwt, 100);
  const convos = convoResp.convos;

  if (convos.length === 0) {
    console.log();
    console.log(c("  No conversations found.", YELLOW));
    console.log();
    return;
  }

  console.log(c(`  Found ${convos.length} conversation${convos.length === 1 ? "" : "s"}`, BOLD));
  console.log();

  for (let i = 0; i < convos.length; i++) {
    const convo = convos[i];
    const msgResp = await chatGetMessages(context, jwt, convo.id, messageLimit);
    printConvo(convo, i, convos.length, selfDid, msgResp.messages);
    console.log();
  }
}

if (import.meta.main) {
  await main();
}
