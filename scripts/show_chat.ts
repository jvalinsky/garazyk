#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  chatGetMessages,
  chatListConvos,
  chatServiceDidForUrl,
  createChatServiceContext,
} from "@garazyk/gruszka/seed";
import {
  ansiColor,
  getTermWidth,
  printConversation,
  renderBoxBottom,
  renderBoxMid,
  renderBoxRow,
  renderBoxTop,
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
  console.log(renderBoxTop(ansiColor(" Garazyk Chat Viewer ", BOLD, WHITE)));
  console.log(renderBoxMid());
  console.log(
    renderBoxRow(ansiColor("PDS:  ", DIM) + ansiColor(pdsUrl, BLUE), width),
  );
  console.log(
    renderBoxRow(ansiColor("Chat: ", DIM) + ansiColor(chatUrl, BLUE), width),
  );
  console.log(
    renderBoxRow(ansiColor("DID:  ", DIM) + ansiColor(serviceDid, BLUE), width),
  );
  console.log(
    renderBoxRow(
      ansiColor("Term: ", DIM) + ansiColor(`${width} cols`, DIM),
      width,
    ),
  );
  console.log(renderBoxMid());

  // Login
  const session = await pdsClient.api.com.atproto.server.createSession({
    identifier: handle,
    password,
  });
  const jwt = session.accessJwt;
  const selfDid = session.did;
  const sHandle = session.handle || handle;

  if (!jwt || !selfDid) {
    throw new Error(
      "Login succeeded but response did not include accessJwt and did",
    );
  }

  console.log(
    renderBoxRow(
      ansiColor("Auth: ", DIM) + ansiColor(sHandle, GREEN, BOLD) +
        ansiColor(` (${selfDid})`, DIM),
      width,
    ),
  );
  console.log(renderBoxBottom());
  console.log();

  // Fetch convos
  console.log(ansiColor("  Fetching conversations…", DIM, ITALIC));
  const convoResp = await chatListConvos(context, jwt, 100);
  const convos = convoResp.convos;

  if (convos.length === 0) {
    console.log();
    console.log(ansiColor("  No conversations found.", YELLOW));
    console.log();
    return;
  }

  console.log(
    ansiColor(
      `  Found ${convos.length} conversation${convos.length === 1 ? "" : "s"}`,
      BOLD,
    ),
  );
  console.log();

  for (let i = 0; i < convos.length; i++) {
    const convo = convos[i];
    const msgResp = await chatGetMessages(context, jwt, convo.id, messageLimit);
    printConversation(convo, i, convos.length, selfDid, msgResp.messages);
    console.log();
  }
}

if (import.meta.main) {
  await main();
}
