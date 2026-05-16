#!/usr/bin/env -S deno run -A

const pdsUrl = (Deno.env.get("PDS_URL") || "https://pds.garazyk.xyz").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "https://chat.garazyk.xyz").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "test.garazyk.xyz";
const password = Deno.env.get("TEST_PASSWORD") || "testpass123";
const convoLimit = Number(Deno.env.get("CHAT_CONVO_LIMIT") || "50");
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "25");
const targetLimit = Number(Deno.env.get("CHAT_TARGET_LIMIT") || "10");
const defaultMessage = Deno.env.get("CHAT_MESSAGE") || "";

type JsonRecord = Record<string, unknown>;

type TargetIdentity = {
  input: string;
  did: string;
  handle?: string;
};

function splitList(value: string | undefined): string[] {
  return (value || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" ? value as JsonRecord : {};
}

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

function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function memberName(member: unknown): string {
  const record = asRecord(member);
  return String(record.handle || record.did || "?");
}

function senderName(message: JsonRecord): string {
  const sender = asRecord(message.sender);
  return String(sender.handle || sender.did || "?");
}

function messageTimestamp(message: JsonRecord): string {
  return String(message.sentAt || message.createdAt || "");
}

function short(value: string, length = 42): string {
  return value.length > length ? `${value.slice(0, length)}...` : value;
}

function appendParams(url: URL, params: JsonRecord): void {
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    if (Array.isArray(value)) {
      for (const item of value) {
        if (item !== undefined && item !== null) url.searchParams.append(key, String(item));
      }
      continue;
    }
    url.searchParams.set(key, String(value));
  }
}

async function xrpcGet(
  baseUrl: string,
  method: string,
  params: JsonRecord = {},
  token?: string,
) {
  const url = new URL(`/xrpc/${method}`, baseUrl);
  appendParams(url, params);

  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(url, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${method} failed (${response.status}): ${JSON.stringify(body)}`);
  }
  return body;
}

async function xrpcPost(
  baseUrl: string,
  method: string,
  body: JsonRecord,
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
  const token = String(asRecord(response).token || "");
  if (!token) {
    throw new Error(`com.atproto.server.getServiceAuth did not return a token for ${method}`);
  }
  return token;
}

async function resolveHandle(handleInput: string): Promise<TargetIdentity> {
  const response = await xrpcGet(
    pdsUrl,
    "com.atproto.identity.resolveHandle",
    { handle: handleInput },
  );
  const did = String(asRecord(response).did || "");
  if (!did) throw new Error(`Could not resolve handle ${handleInput}`);
  return { input: handleInput, handle: handleInput, did };
}

async function fileExists(path: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(path);
    return stat.isFile;
  } catch {
    return false;
  }
}

async function firstExistingServiceDbPath(): Promise<string | undefined> {
  const explicit = Deno.env.get("PDS_SERVICE_DB");
  const dataDir = Deno.env.get("PDS_DATA_DIR");
  const candidates = [
    explicit,
    dataDir ? `${dataDir.replace(/\/$/, "")}/service/service.db` : undefined,
    "DEPLOY_DIR/pds-data/service/service.db",
  ].filter((path): path is string => Boolean(path));

  for (const candidate of candidates) {
    if (await fileExists(candidate)) return candidate;
  }
  return undefined;
}

async function discoverLocalDidTargets(): Promise<TargetIdentity[]> {
  const dbPath = await firstExistingServiceDbPath();
  if (!dbPath) return [];

  const limit = Number.isFinite(targetLimit)
    ? Math.max(1, Math.min(100, Math.trunc(targetLimit)))
    : 10;
  const sql =
    `SELECT did, handle FROM accounts WHERE did LIKE 'did:plc:%' ORDER BY created_at DESC LIMIT ${limit};`;
  const command = new Deno.Command("sqlite3", {
    args: ["-json", dbPath, sql],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr).trim();
    throw new Error(
      `Failed to discover local accounts from ${dbPath}: ${stderr || "sqlite3 failed"}`,
    );
  }

  const stdout = new TextDecoder().decode(output.stdout).trim();
  if (!stdout) return [];
  const rows = JSON.parse(stdout) as Array<{ did?: string; handle?: string }>;
  return rows
    .filter((row) => row.did?.startsWith("did:plc:"))
    .map((row) => ({
      input: row.handle || row.did || "",
      handle: row.handle,
      did: row.did || "",
    }));
}

async function resolveTargets(selfDid: string): Promise<TargetIdentity[]> {
  const positionalInputs = Deno.args;
  const didInputs = [
    ...splitList(Deno.env.get("CHAT_TARGET_DIDS")),
    ...positionalInputs.filter((input) => input.startsWith("did:")),
  ];
  const handleInputs = [
    ...splitList(Deno.env.get("CHAT_TARGET_HANDLES")),
    ...positionalInputs.filter((input) => !input.startsWith("did:")),
  ];

  const targets: TargetIdentity[] = [];
  for (const did of didInputs) targets.push({ input: did, did });
  for (const targetHandle of handleInputs) targets.push(await resolveHandle(targetHandle));
  if (targets.length === 0) {
    targets.push(...await discoverLocalDidTargets());
  }

  const unique = new Map<string, TargetIdentity>();
  for (const target of targets) {
    if (!target.did.startsWith("did:plc:")) {
      throw new Error(
        `Target ${target.input} resolved to ${target.did}; expected a did:plc account`,
      );
    }
    if (target.did === selfDid) continue;
    unique.set(target.did, target);
  }

  if (unique.size === 0) {
    throw new Error(
      "No target did:plc accounts provided. Pass DIDs as arguments or set CHAT_TARGET_DIDS / CHAT_TARGET_HANDLES.",
    );
  }

  return [...unique.values()];
}

async function getConvoForMembers(accessJwt: string, serviceDid: string, members: string[]) {
  const token = await serviceAuthForChatMethod(
    "chat.bsky.convo.getConvoForMembers",
    accessJwt,
    serviceDid,
  );
  return await xrpcGet(chatUrl, "chat.bsky.convo.getConvoForMembers", { members }, token);
}

async function sendMessage(
  accessJwt: string,
  serviceDid: string,
  convoId: string,
  text: string,
) {
  const token = await serviceAuthForChatMethod(
    "chat.bsky.convo.sendMessage",
    accessJwt,
    serviceDid,
  );
  return await xrpcPost(
    chatUrl,
    "chat.bsky.convo.sendMessage",
    {
      convoId,
      message: { text },
    },
    token,
  );
}

async function listConvos(accessJwt: string, serviceDid: string) {
  const token = await serviceAuthForChatMethod("chat.bsky.convo.listConvos", accessJwt, serviceDid);
  return await xrpcGet(chatUrl, "chat.bsky.convo.listConvos", { limit: convoLimit }, token);
}

async function getMessages(
  accessJwt: string,
  serviceDid: string,
  convoId: string,
) {
  const token = await serviceAuthForChatMethod(
    "chat.bsky.convo.getMessages",
    accessJwt,
    serviceDid,
  );
  return await xrpcGet(
    chatUrl,
    "chat.bsky.convo.getMessages",
    { convoId, limit: messageLimit },
    token,
  );
}

async function main() {
  const chatServiceDid = chatServiceDidForUrl(chatUrl);
  console.log(`PDS: ${pdsUrl}`);
  console.log(`Chat: ${chatUrl}`);
  console.log(`Chat DID: ${chatServiceDid}`);
  console.log(`Account: ${handle}`);

  const session = await xrpcPost(pdsUrl, "com.atproto.server.createSession", {
    identifier: handle,
    password,
  });
  const accessJwt = String(asRecord(session).accessJwt || "");
  const selfDid = String(asRecord(session).did || "");
  if (!accessJwt || !selfDid) {
    throw new Error("Login succeeded but response did not include accessJwt and did");
  }

  console.log(`Logged in as ${session.handle ?? handle}`);
  console.log(`DID: ${selfDid}`);

  const targets = await resolveTargets(selfDid);
  console.log(`Targets: ${targets.length}`);
  for (const target of targets) {
    console.log(`  ${target.handle ? `${target.handle} ` : ""}${target.did}`);
  }

  console.log("\n=== Create Or Reuse Conversations ===");
  const createdConvoIds: string[] = [];
  for (const target of targets) {
    const label = target.handle || target.did;
    const convoResponse = await getConvoForMembers(accessJwt, chatServiceDid, [
      selfDid,
      target.did,
    ]);
    const convo = asRecord(asRecord(convoResponse).convo);
    const convoId = String(convo.id || "");
    if (!convoId) throw new Error(`No convo id returned for ${label}`);

    createdConvoIds.push(convoId);
    const text = defaultMessage ||
      `Hello ${label}. Chat smoke from ${handle} at ${nowIso()}.`;
    const sent = await sendMessage(accessJwt, chatServiceDid, convoId, text);
    console.log(`\n${label}`);
    console.log(`  Convo: ${convoId}`);
    console.log(`  Sent: ${short(String(asRecord(sent).id || "?"))} ${text}`);
  }

  console.log("\n=== Conversation Count ===");
  const convoResponse = await listConvos(accessJwt, chatServiceDid);
  const convos = Array.isArray(asRecord(convoResponse).convos)
    ? asRecord(convoResponse).convos as unknown[]
    : [];
  console.log(`Conversations: ${convos.length}`);

  console.log("\n=== Messages Per Conversation ===");
  for (const rawConvo of convos) {
    const convo = asRecord(rawConvo);
    const convoId = String(convo.id || "");
    if (!convoId) continue;

    const members = Array.isArray(convo.members) ? convo.members.map(memberName).join(", ") : "";
    const marker = createdConvoIds.includes(convoId) ? " *" : "";
    console.log(`\n${convoId}${marker}`);
    console.log(`Members: ${members || "(none)"}`);

    const messageResponse = await getMessages(accessJwt, chatServiceDid, convoId);
    const messages = Array.isArray(asRecord(messageResponse).messages)
      ? asRecord(messageResponse).messages as unknown[]
      : [];
    console.log(`Messages: ${messages.length}`);

    for (const rawMessage of messages.toReversed()) {
      const message = asRecord(rawMessage);
      const text = String(message.text ?? "");
      const id = String(message.id || "");
      console.log(`[${messageTimestamp(message)}] ${senderName(message)}: ${text}`);
      if (id) console.log(`  id: ${id}`);
    }
  }

  console.log("\nDone.");
}

if (import.meta.main) {
  await main();
}
