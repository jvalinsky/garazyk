/** Seed data helpers for ATProto E2E tests — accounts, posts, chat interactions. @module seed */
import { XrpcClient } from "./client.ts";
import { XrpcError } from "./transport.ts";
import type { GeneratedClient as ExactGeneratedClient } from "./lexicons.ts";
import type { ProcedureOutput, QueryOutput } from "./lexicons.ts";

/** Default test accounts used by seed data helpers. */
export const DEFAULT_ACCOUNTS = [
  { handle: "alice.test", email: "alice@test.local", password: "alicepass" },
  { handle: "bob.test", email: "bob@test.local", password: "bobpass" },
  { handle: "carol.test", email: "carol@test.local", password: "carolpass" },
];

/** Post text templates for seed data. Use `{handle}` as a placeholder for the account handle. */
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

/** Current timestamp in ISO 8601 format with milliseconds stripped (e.g. `2024-01-15T12:30:00Z`). */
export function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function exactApi(client: XrpcClient): ExactGeneratedClient {
  return client.api as unknown as ExactGeneratedClient;
}

/**
 * Wait for a PDS server to respond with HTTP 200 on its `/_health` endpoint.
 *
 * @param baseUrl - Root URL of the PDS (e.g. `http://localhost:2583`)
 * @param timeout - Maximum seconds to wait. @defaultValue 30
 * @throws If the server does not become healthy within the timeout
 */
export async function waitForServer(
  baseUrl: string,
  timeout = 30,
): Promise<void> {
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

/**
 * Create an account, or fall back to logging in if the handle already exists.
 *
 * @param client - XRPC client pointing at the PDS
 * @param handle - Desired handle (e.g. `alice.test`)
 * @param email - Account email
 * @param password - Account password
 * @throws {XrpcError} If both creation and login fail.
 */
export async function createAccountOrLogin(
  client: XrpcClient,
  handle: string,
  email: string,
  password: string,
): Promise<ProcedureOutput<"com.atproto.server.createSession">> {
  const api = exactApi(client);
  try {
    return await api.com.atproto.server.createAccount({
      email,
      handle,
      password,
    }) as unknown as ProcedureOutput<"com.atproto.server.createSession">;
  } catch (exc) {
    if (exc instanceof XrpcError && exc.status === 400) {
      const body = typeof exc.body === "string"
        ? exc.body
        : JSON.stringify(exc.body);
      if (body.toLowerCase().includes("already exists")) {
        return await api.com.atproto.server.createSession({
          identifier: handle,
          password,
        });
      }
    }
    throw exc;
  }
}

/**
 * Create a repository record, returning an empty object if it already exists.
 *
 * Catches `XrpcError` with status 400 containing "already exists" and returns `{}`.
 *
 * @param client - XRPC client pointing at the PDS
 * @param repo - DID of the repository
 * @param collection - NSID collection name (e.g. `app.bsky.feed.post`)
 * @param record - Record body to create
 * @param token - Auth access JWT
 * @throws {XrpcError} If the creation fails with an error other than "already exists"
 */
export async function createRecordIdempotent(
  client: XrpcClient,
  repo: string,
  collection: string,
  record: Record<string, unknown>,
  token: string,
): Promise<
  ProcedureOutput<"com.atproto.repo.createRecord"> | Record<string, never>
> {
  const api = exactApi(client);
  try {
    return await api.com.atproto.repo.createRecord({
      repo,
      collection,
      record,
    }, token);
  } catch (exc) {
    if (exc instanceof XrpcError && exc.status === 400) {
      const body = typeof exc.body === "string"
        ? exc.body
        : JSON.stringify(exc.body);
      if (body.toLowerCase().includes("already exists")) return {};
    }
    throw exc;
  }
}

/** Context for interacting with the Bluesky chat service via XRPC. */
export interface ChatServiceContext {
  /** XRPC client for the PDS (used for service auth tokens). */
  pdsClient: XrpcClient;
  /** XRPC client for the chat service endpoint. */
  chatClient: XrpcClient;
  /** DID of the chat service (e.g. `did:web:localhost#bsky_chat`). */
  serviceDid: string;
}

/**
 * Derive the chat service DID from a URL or an explicit override.
 *
 * If `configured` is provided, uses it directly (appending `#bsky_chat` if no
 * fragment is present). Otherwise, constructs a `did:web` DID from the URL
 * hostname, mapping `127.0.0.1`/`::1` to `localhost`.
 *
 * @param baseUrl - Chat service URL
 * @param configured - Optional explicit DID override
 * @returns The chat service DID
 */
export function chatServiceDidForUrl(
  baseUrl: string,
  configured?: string,
): string {
  if (configured?.trim()) {
    const serviceDid = configured.trim();
    return serviceDid.includes("#") ? serviceDid : `${serviceDid}#bsky_chat`;
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

/**
 * Create a {@link ChatServiceContext} with a chat client and derived service DID.
 *
 * @param pdsClient - XRPC client for the PDS
 * @param chatUrl - Chat service base URL
 * @param configuredServiceDid - Optional explicit DID override
 * @returns A fully initialized chat service context
 */
export function createChatServiceContext(
  pdsClient: XrpcClient,
  chatUrl: string,
  configuredServiceDid?: string,
): ChatServiceContext {
  return {
    pdsClient,
    chatClient: new XrpcClient(chatUrl),
    serviceDid: chatServiceDidForUrl(chatUrl, configuredServiceDid),
  };
}

/**
 * Obtain a scoped auth token for a specific chat XRPC method.
 *
 * Calls `com.atproto.server.getServiceAuth` on the PDS to get a token scoped
 * to the chat service DID and the requested method.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param method - XRPC method NSID (e.g. `chat.bsky.convo.sendMessage`)
 * @returns A scoped auth token for the chat service
 * @throws If the PDS does not return a token
 */
export async function chatServiceAuthForMethod(
  context: ChatServiceContext,
  accessJwt: string,
  method: string,
): Promise<string> {
  const response = await context.pdsClient.api.com.atproto.server
    .getServiceAuth({
      aud: context.serviceDid,
      lxm: method,
    }, accessJwt);
  const token = String((response as any)?.token || "");
  if (!token) {
    throw new Error(
      `com.atproto.server.getServiceAuth did not return a token for ${method}`,
    );
  }
  return token;
}

/**
 * Perform an authenticated chat XRPC GET with automatic service auth.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param method - XRPC method NSID
 * @param params - Query parameters
 */
export async function chatXrpcGet(
  context: ChatServiceContext,
  accessJwt: string,
  method: string,
  params?: Record<string, unknown>,
): Promise<any> {
  const token = await chatServiceAuthForMethod(context, accessJwt, method);
  return await context.chatClient.raw.xrpcGet(method, params, token);
}

/**
 * Perform an authenticated chat XRPC POST with automatic service auth.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param method - XRPC method NSID
 * @param body - Request body
 */
export async function chatXrpcPost(
  context: ChatServiceContext,
  accessJwt: string,
  method: string,
  body?: Record<string, unknown>,
): Promise<any> {
  const token = await chatServiceAuthForMethod(context, accessJwt, method);
  return await context.chatClient.raw.xrpcPost(method, body, token);
}

/**
 * Get or create a DM conversation for a set of members.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param memberDids - DIDs of the conversation members
 */
export async function chatGetConvoForMembers(
  context: ChatServiceContext,
  accessJwt: string,
  memberDids: string[],
): Promise<QueryOutput<"chat.bsky.convo.getConvoForMembers">> {
  return await chatXrpcGet(
    context,
    accessJwt,
    "chat.bsky.convo.getConvoForMembers",
    {
      members: memberDids,
    },
  );
}

/**
 * Send a text message in a chat conversation.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param convoId - Conversation ID
 * @param text - Message text
 */
export async function chatSendMessage(
  context: ChatServiceContext,
  accessJwt: string,
  convoId: string,
  text: string,
): Promise<ProcedureOutput<"chat.bsky.convo.sendMessage">> {
  return await chatXrpcPost(context, accessJwt, "chat.bsky.convo.sendMessage", {
    convoId,
    message: { text },
  });
}

/**
 * List conversations for the authenticated user.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param limit - Maximum number of conversations to return. @defaultValue 20
 */
export async function chatListConvos(
  context: ChatServiceContext,
  accessJwt: string,
  limit = 20,
): Promise<QueryOutput<"chat.bsky.convo.listConvos">> {
  return await chatXrpcGet(context, accessJwt, "chat.bsky.convo.listConvos", {
    limit,
  });
}

/**
 * Get messages in a chat conversation.
 *
 * @param context - Chat service context
 * @param accessJwt - PDS access JWT for the calling user
 * @param convoId - Conversation ID
 * @param limit - Maximum number of messages to return. @defaultValue 50
 */
export async function chatGetMessages(
  context: ChatServiceContext,
  accessJwt: string,
  convoId: string,
  limit = 50,
): Promise<QueryOutput<"chat.bsky.convo.getMessages">> {
  return await chatXrpcGet(context, accessJwt, "chat.bsky.convo.getMessages", {
    convoId,
    limit,
  });
}

/** Get or create a DM conversation for a set of members (direct XRPC, no service auth). */
export async function getConvoForMembers(
  client: XrpcClient,
  jwt: string,
  memberDids: string[],
): Promise<QueryOutput<"chat.bsky.convo.getConvoForMembers">> {
  return await exactApi(client).chat.bsky.convo.getConvoForMembers({
    members: memberDids,
  }, jwt);
}

/** Send a text message in a chat conversation (direct XRPC, no service auth). */
export async function sendMessage(
  client: XrpcClient,
  jwt: string,
  convoId: string,
  text: string,
): Promise<ProcedureOutput<"chat.bsky.convo.sendMessage">> {
  return await exactApi(client).chat.bsky.convo.sendMessage({
    convoId,
    message: { text },
  }, jwt);
}

/** List conversations for the authenticated user (direct XRPC, no service auth). */
export async function listConvos(
  client: XrpcClient,
  jwt: string,
  limit = 20,
): Promise<QueryOutput<"chat.bsky.convo.listConvos">> {
  return await exactApi(client).chat.bsky.convo.listConvos({ limit }, jwt);
}

/** Get messages in a chat conversation (direct XRPC, no service auth). */
export async function getMessages(
  client: XrpcClient,
  jwt: string,
  convoId: string,
  limit = 50,
): Promise<QueryOutput<"chat.bsky.convo.getMessages">> {
  return await exactApi(client).chat.bsky.convo.getMessages(
    { convoId, limit },
    jwt,
  );
}
