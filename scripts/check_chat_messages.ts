#!/usr/bin/env -S deno run -A

const pdsUrl = (Deno.env.get("PDS_URL") || "https://pds.garazyk.xyz").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "https://chat.garazyk.xyz").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "test.garazyk.xyz";
const password = Deno.env.get("TEST_PASSWORD") || "";
if (!password) {
  console.error("TEST_PASSWORD environment variable is required.");
  console.error("Usage: TEST_PASSWORD=<password> TEST_HANDLE=<handle> deno run -A check_chat_messages.ts");
  Deno.exit(1);
}
const convoLimit = Number(Deno.env.get("CHAT_CONVO_LIMIT") || "20");
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "50");

function chatServiceDidForUrl(baseUrl: string): string {
  const configured = Deno.env.get("CHAT_SERVICE_DID");
  if (configured) {
    return configured.includes("#") ? configured : `${configured}#bsky_chat`;
  }

  const url = new URL(baseUrl);
  const hostname = url.hostname === "127.0.0.1" || url.hostname === "::1"
    ? "localhost"
    : url.hostname;
  const isDefaultPort = !url.port ||
    (url.protocol === "https:" && url.port === "443") ||
    (url.protocol === "http:" && url.port === "80");
  const didHost = isDefaultPort ? hostname : `${hostname}%3A${url.port}`;
  return `did:web:${didHost}#bsky_chat`;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function memberName(member: unknown): string {
  const record = asRecord(member);
  return String(record.handle || record.did || "?");
}

function senderName(message: Record<string, unknown>): string {
  const sender = asRecord(message.sender);
  return String(sender.handle || sender.did || "?");
}

async function xrpcGet(
  baseUrl: string,
  method: string,
  params: Record<string, unknown>,
  token: string,
) {
  const url = new URL(`/xrpc/${method}`, baseUrl);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }

  const response = await fetch(url, {
    headers: { "Authorization": `Bearer ${token}` },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${method} failed (${response.status}): ${JSON.stringify(body)}`);
  }
  return body;
}

async function serviceAuthForChatMethod(
  method: string,
  accessJwt: string,
  serviceDid: string,
): Promise<string> {
  const response = await xrpcGet(
    pdsUrl,
    "com.atproto.server.getServiceAuth",
    { aud: serviceDid, lxm: method },
    accessJwt,
  );
  const token = String(response.token || "");
  if (!token) {
    throw new Error(`com.atproto.server.getServiceAuth did not return a token for ${method}`);
  }
  return token;
}

async function xrpcPost(
  baseUrl: string,
  method: string,
  body: Record<string, unknown>,
  token?: string,
) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(new URL(`/xrpc/${method}`, baseUrl), {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${method} failed (${response.status}): ${JSON.stringify(responseBody)}`);
  }
  return responseBody;
}

async function main() {
  console.log(`PDS: ${pdsUrl}`);
  console.log(`Chat: ${chatUrl}`);
  console.log(`Account: ${handle}`);
  const chatServiceDid = chatServiceDidForUrl(chatUrl);
  console.log(`Chat DID: ${chatServiceDid}`);

  const session = await xrpcPost(pdsUrl, "com.atproto.server.createSession", {
    identifier: handle,
    password,
  });
  const accessJwt = String(session.accessJwt || "");
  if (!accessJwt) throw new Error("Login succeeded but response did not include accessJwt");

  console.log(`Logged in as ${session.handle ?? handle}`);
  console.log(`DID: ${session.did}`);
  console.log("");

  const listConvosToken = await serviceAuthForChatMethod(
    "chat.bsky.convo.listConvos",
    accessJwt,
    chatServiceDid,
  );
  const convoResponse = await xrpcGet(
    chatUrl,
    "chat.bsky.convo.listConvos",
    { limit: convoLimit },
    listConvosToken,
  );
  const convos = Array.isArray(convoResponse.convos) ? convoResponse.convos : [];

  console.log(`Conversations: ${convos.length}`);

  for (const rawConvo of convos) {
    const convo = asRecord(rawConvo);
    const convoId = String(convo.id || "");
    if (!convoId) continue;

    const members = Array.isArray(convo.members) ? convo.members.map(memberName).join(", ") : "";
    console.log("");
    console.log(`=== ${convoId} ===`);
    console.log(`Members: ${members || "(none)"}`);

    const getMessagesToken = await serviceAuthForChatMethod(
      "chat.bsky.convo.getMessages",
      accessJwt,
      chatServiceDid,
    );
    const messageResponse = await xrpcGet(
      chatUrl,
      "chat.bsky.convo.getMessages",
      { convoId, limit: messageLimit },
      getMessagesToken,
    );
    const messages = Array.isArray(messageResponse.messages) ? messageResponse.messages : [];

    if (messages.length === 0) {
      console.log("No messages.");
      continue;
    }

    for (const rawMessage of messages.toReversed()) {
      const message = asRecord(rawMessage);
      const text = String(message.text ?? "");
      const createdAt = String(message.sentAt ?? message.createdAt ?? "");
      const id = String(message.id ?? "");
      console.log(`[${createdAt}] ${senderName(message)}: ${text}`);
      if (id) console.log(`  id: ${id}`);
    }
  }
}

if (import.meta.main) {
  await main();
}
