#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  chatGetConvoForMembers,
  chatGetMessages,
  chatListConvos,
  chatSendMessage,
  chatServiceDidForUrl,
  createChatServiceContext,
  nowIso,
} from "@garazyk/gruszka/seed";
import {
  discoverRemoteAccountsViaAdminApi,
  discoverRemoteAccountsViaSsh,
  resolveTargets,
} from "@garazyk/hamownia/account-discovery";

const pdsUrl = (Deno.env.get("PDS_URL") || "").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "";
const password = Deno.env.get("TEST_PASSWORD") || "";
if (!pdsUrl || !chatUrl || !handle || !password) {
  console.error(
    "PDS_URL, CHAT_URL, TEST_HANDLE, and TEST_PASSWORD environment variables are required.",
  );
  console.error(
    "Usage: PDS_URL=<url> CHAT_URL=<url> TEST_HANDLE=<handle> TEST_PASSWORD=<password> deno run -A create_chat_convos.ts",
  );
  Deno.exit(1);
}
const altHandle = Deno.env.get("ALT_HANDLE") || "";
const altPassword = Deno.env.get("ALT_PASSWORD") || "";
const convoLimit = Number(Deno.env.get("CHAT_CONVO_LIMIT") || "50");
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "25");
const targetLimit = Number(Deno.env.get("CHAT_TARGET_LIMIT") || "10");
const defaultMessage = Deno.env.get("CHAT_MESSAGE") || "";
const existingConvoId = Deno.env.get("CHAT_CONVO_ID") || "";
const messageCount = Number(Deno.env.get("CHAT_MESSAGE_COUNT") || "1");
const backAndForth = Boolean(Deno.env.get("CHAT_BACK_AND_FORTH")) ||
  (altHandle.length > 0 && altPassword.length > 0);
const rounds = Number(Deno.env.get("CHAT_ROUNDS") || "3");
const discoverMode = Boolean(Deno.env.get("CHAT_DISCOVER"));
const sshHost = Deno.env.get("CHAT_SSH_HOST") || "";
const sshDbPath = Deno.env.get("CHAT_SSH_DB") || "";

type Session = {
  accessJwt: string;
  did: string;
  handle: string;
};

function short(value: string, length = 42): string {
  return value.length > length ? `${value.slice(0, length)}...` : value;
}

async function createSession(
  client: XrpcClient,
  identifier: string,
  secret: string,
): Promise<Session> {
  const session = await client.api.com.atproto.server.createSession({
    identifier,
    password: secret,
  }) as any;
  return {
    accessJwt: session.accessJwt,
    did: session.did,
    handle: session.handle || identifier,
  };
}

function printMessages(messages: any[]): void {
  for (const message of messages.toReversed()) {
    const text = String(message.text ?? "");
    const id = String(message.id || "");
    const sentAt = String(message.sentAt || message.createdAt || "");
    const sender = message.sender?.handle || message.sender?.did || "?";
    console.log(`[${sentAt}] ${sender}: ${text}`);
    if (id) console.log(`  id: ${id}`);
  }
}

async function printAllConvos(
  context: any,
  session: Session,
  markedIds: string[] = [],
): Promise<void> {
  console.log("\n=== Conversation Count ===");
  const convoResponse = await chatListConvos(context, session.accessJwt, convoLimit);
  const convos = convoResponse.convos;
  console.log(`Conversations: ${convos.length}`);

  console.log("\n=== Messages Per Conversation ===");
  for (const convo of convos) {
    const convoId = convo.id;
    const members = convo.members.map((m: any) => m.handle || m.did).join(", ");
    const marker = markedIds.includes(convoId) ? " *" : "";
    console.log(`\n${convoId}${marker}`);
    console.log(`Members: ${members || "(none)"}`);

    const messageResponse = await chatGetMessages(context, session.accessJwt, convoId, messageLimit);
    const messages = messageResponse.messages;
    console.log(`Messages: ${messages.length}`);
    printMessages(messages);
  }
}

async function main() {
  const pdsClient = new XrpcClient(pdsUrl);
  const chatContext = createChatServiceContext(pdsClient, chatUrl, chatServiceDidForUrl(chatUrl));

  const session = await createSession(pdsClient, handle, password);
  console.log(`Account: ${session.handle} (${session.did})`);

  if (existingConvoId) {
    console.log(`Mode: send to existing conversation ${existingConvoId}`);
    for (let i = 0; i < messageCount; i++) {
      const text = defaultMessage || `Message ${i + 1} from ${session.handle} at ${nowIso()}.`;
      const sent = await chatSendMessage(chatContext, session.accessJwt, existingConvoId, text);
      console.log(`  [${i + 1}] ${short(sent.id)} ${text}`);
    }
    return;
  }

  if (backAndForth && altHandle && altPassword) {
    const altSession = await createSession(pdsClient, altHandle, altPassword);
    console.log(`Alt Account: ${altSession.handle} (${altSession.did})`);

    const convoResp = await chatGetConvoForMembers(chatContext, session.accessJwt, [
      session.did,
      altSession.did,
    ]);
    const convoId = convoResp.convo.id;

    for (let round = 0; round < rounds; round++) {
      const textA = defaultMessage || `Round ${round + 1} from ${session.handle} at ${nowIso()}.`;
      await chatSendMessage(chatContext, session.accessJwt, convoId, textA);
      console.log(`  Round ${round + 1} A -> B`);

      const textB = defaultMessage ? `${defaultMessage} (reply)` : `Round ${round + 1} reply from ${altSession.handle} at ${nowIso()}.`;
      await chatSendMessage(chatContext, altSession.accessJwt, convoId, textB);
      console.log(`  Round ${round + 1} B -> A`);
    }
    await printAllConvos(chatContext, session, [convoId]);
    return;
  }

  const targets = await resolveTargets(pdsUrl, session.did, session.accessJwt, {
    sshHost,
    dbPath: sshDbPath,
    limit: targetLimit,
  });

  console.log(`Targets: ${targets.length}`);
  const createdIds: string[] = [];
  for (const target of targets) {
    try {
      const convoResp = await chatGetConvoForMembers(chatContext, session.accessJwt, [
        session.did,
        target.did,
      ]);
      const convoId = convoResp.convo.id;
      createdIds.push(convoId);

      const text = defaultMessage || `Hello ${target.handle || target.did}. Chat smoke from ${session.handle} at ${nowIso()}.`;
      await chatSendMessage(chatContext, session.accessJwt, convoId, text);
      console.log(`  Sent to ${target.handle || target.did} (convo: ${convoId})`);
    } catch (err: any) {
      console.error(`  Failed for ${target.handle || target.did}: ${err.message}`);
    }
  }

  await printAllConvos(chatContext, session, createdIds);
}

if (import.meta.main) {
  await main();
}
