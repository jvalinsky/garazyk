import { XrpcClient } from "./client.ts";
import { XrpcError } from "./transport.ts";

export const DEFAULT_ACCOUNTS = [
  { handle: "alice.test", email: "alice@test.local", password: "alicepass" },
  { handle: "bob.test", email: "bob@test.local", password: "bobpass" },
  { handle: "carol.test", email: "carol@test.local", password: "carolpass" },
];

export const DEFAULT_POSTS_TEMPLATES = [
  "Hello from {handle}! Excited to be on the ATProto network!",
  "Just set up my PDS instance. Decentralization rocks!",
  "Working on some cool features today. #atproto #coding",
  "Beautiful day to build something new!",
  "The future of social is decentralized. Here we go!",
  "Just learned about MST (Merkle Search Tree) -- fascinating tech!",
  "Shoutout to the Bluesky team for the protocol design!",
  "Testing out the firehose relay functionality today.",
  "Record indexing is working great with the new backfill logic.",
  "Admin UI makes managing the PDS so much easier!",
];

export function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

export async function waitForServer(baseUrl: string, timeout = 30): Promise<void> {
  const deadline = Date.now() + timeout * 1000;
  let lastError = "not attempted";
  while (Date.now() < deadline) {
    try {
      const resp = await fetch(`${baseUrl.replace(/\/$/, "")}/_health`);
      if (resp.status === 200) return;
      lastError = `HTTP ${resp.status}`;
    } catch (exc) {
      lastError = exc instanceof Error ? exc.message : String(exc);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`PDS not ready at ${baseUrl} (last: ${lastError})`);
}

export async function createAccountOrLogin(
  client: XrpcClient,
  handle: string,
  email: string,
  password: string,
) {
  try {
    return await client.accounts.createAccount(handle, email, password);
  } catch {
    return await client.accounts.createSession(handle, password);
  }
}

export async function createRecordIdempotent(
  client: XrpcClient,
  repo: string,
  collection: string,
  record: Record<string, unknown>,
  token: string,
) {
  try {
    return await client.records.createRecord(repo, collection, record, token);
  } catch (exc) {
    if (exc instanceof XrpcError && exc.status === 400) {
      const body = typeof exc.body === "string" ? exc.body : JSON.stringify(exc.body);
      if (body.toLowerCase().includes("already exists")) return {};
    }
    throw exc;
  }
}

export async function getConvoForMembers(client: XrpcClient, jwt: string, memberDids: string[]) {
  return await client.raw.xrpcPost("chat.bsky.convo.getConvoForMembers", {
    members: memberDids,
  }, jwt);
}

export async function sendMessage(client: XrpcClient, jwt: string, convoId: string, text: string) {
  return await client.raw.xrpcPost("chat.bsky.convo.sendMessage", {
    convoId,
    message: {
      "$type": "chat.bsky.convo.def#messageRef",
      text,
      createdAt: nowIso(),
    },
  }, jwt);
}

export async function listConvos(client: XrpcClient, jwt: string, limit = 20) {
  return await client.raw.xrpcGet("chat.bsky.convo.listConvos", { limit }, jwt);
}

export async function getMessages(client: XrpcClient, jwt: string, convoId: string, limit = 50) {
  return await client.raw.xrpcGet("chat.bsky.convo.getMessages", { convoId, limit }, jwt);
}
