#!/usr/bin/env -S deno run -A

const pdsUrl = (Deno.env.get("PDS_URL") || "https://pds.garazyk.xyz").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "https://chat.garazyk.xyz").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "test.garazyk.xyz";
const password = Deno.env.get("TEST_PASSWORD") || "testpass123";
const altHandle = Deno.env.get("ALT_HANDLE") || "";
const altPassword = Deno.env.get("ALT_PASSWORD") || "";
const convoLimit = Number(Deno.env.get("CHAT_CONVO_LIMIT") || "50");
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "25");
const targetLimit = Number(Deno.env.get("CHAT_TARGET_LIMIT") || "10");
const defaultMessage = Deno.env.get("CHAT_MESSAGE") || "";
const existingConvoId = Deno.env.get("CHAT_CONVO_ID") || "";
const messageCount = Number(Deno.env.get("CHAT_MESSAGE_COUNT") || "1");
const backAndForth = Boolean(Deno.env.get("CHAT_BACK_AND_FORTH") || (altHandle && altPassword));
const rounds = Number(Deno.env.get("CHAT_ROUNDS") || "3");
const discoverMode = Boolean(Deno.env.get("CHAT_DISCOVER"));
const sshHost = Deno.env.get("CHAT_SSH_HOST") || "";
const sshDbPath = Deno.env.get("CHAT_SSH_DB") || "DEPLOY_DIR/pds-data/service/service.db";

type JsonRecord = Record<string, unknown>;

type Session = {
  accessJwt: string;
  did: string;
  handle: string;
};

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

async function createSession(
  identifier: string,
  secret: string,
): Promise<Session> {
  const response = await xrpcPost(pdsUrl, "com.atproto.server.createSession", {
    identifier,
    password: secret,
  });
  const record = asRecord(response);
  const accessJwt = String(record.accessJwt || "");
  const did = String(record.did || "");
  const sessionHandle = String(record.handle || identifier);
  if (!accessJwt || !did) {
    throw new Error(`Login for ${identifier} succeeded but response did not include accessJwt and did`);
  }
  return { accessJwt, did, handle: sessionHandle };
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

async function discoverRemoteAccounts(accessJwt?: string): Promise<TargetIdentity[]> {
  const limit = Number.isFinite(targetLimit)
    ? Math.max(1, Math.min(100, Math.trunc(targetLimit)))
    : 10;

  // SSH-based discovery: query the remote PDS DB directly
  if (sshHost) {
    const sql =
      `SELECT did, handle FROM accounts WHERE did LIKE 'did:plc:%' ORDER BY created_at DESC LIMIT ${limit};`;
    const command = new Deno.Command("ssh", {
      args: [sshHost, `sqlite3 -json ${sshDbPath} ${JSON.stringify(sql)}`],
      stdout: "piped",
      stderr: "piped",
    });
    const output = await command.output();
    if (!output.success) {
      const stderr = new TextDecoder().decode(output.stderr).trim();
      throw new Error(`SSH discovery failed: ${stderr || "ssh command failed"}`);
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

  // Admin API fallback: try com.atproto.admin.getAccounts
  if (accessJwt) {
    try {
      const response = await xrpcGet(
        pdsUrl,
        "com.atproto.admin.getAccounts",
        { limit },
        accessJwt,
      );
      const accounts = Array.isArray(asRecord(response).accounts)
        ? asRecord(response).accounts as unknown[]
        : [];
      return accounts
        .map((raw) => {
          const account = asRecord(raw);
          const did = String(account.did || "");
          const accountHandle = String(account.handle?.handle || account.handle || "");
          return { input: accountHandle || did, handle: accountHandle || undefined, did };
        })
        .filter((t) => t.did.startsWith("did:plc:"));
    } catch (err) {
      console.error(`  Admin API unavailable: ${err instanceof Error ? err.message : err}`);
      console.error("  Falling back to local DB discovery...");
    }
  }

  return discoverLocalDidTargets();
}

async function resolveTargets(selfDid: string, accessJwt?: string): Promise<TargetIdentity[]> {
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
  if (targets.length === 0 && discoverMode && accessJwt) {
    console.log("\n=== Discovering Accounts on PDS ===");
    const discovered = await discoverRemoteAccounts(accessJwt);
    targets.push(...discovered);
    console.log(`  Found ${discovered.length} accounts`);
  }
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

function printMessages(messages: unknown[]): void {
  for (const rawMessage of messages.toReversed()) {
    const message = asRecord(rawMessage);
    const text = String(message.text ?? "");
    const id = String(message.id || "");
    console.log(`[${messageTimestamp(message)}] ${senderName(message)}: ${text}`);
    if (id) console.log(`  id: ${id}`);
  }
}

async function printAllConvos(session: Session, serviceDid: string, markedIds: string[] = []): Promise<void> {
  console.log("\n=== Conversation Count ===");
  const convoResponse = await listConvos(session.accessJwt, serviceDid);
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
    const marker = markedIds.includes(convoId) ? " *" : "";
    console.log(`\n${convoId}${marker}`);
    console.log(`Members: ${members || "(none)"}`);

    const messageResponse = await getMessages(session.accessJwt, serviceDid, convoId);
    const messages = Array.isArray(asRecord(messageResponse).messages)
      ? asRecord(messageResponse).messages as unknown[]
      : [];
    console.log(`Messages: ${messages.length}`);
    printMessages(messages);
  }
}

// ── Mode 1: Send messages to an existing conversation ──────────────────

async function modeExistingConvo(session: Session, serviceDid: string): Promise<void> {
  const convoId = existingConvoId;
  console.log(`\n=== Send to Existing Conversation ===`);
  console.log(`Convo: ${convoId}`);
  console.log(`Messages to send: ${messageCount}`);

  for (let i = 0; i < messageCount; i++) {
    const text = defaultMessage ||
      `Message ${i + 1} from ${session.handle} at ${nowIso()}.`;
    const sent = await sendMessage(session.accessJwt, serviceDid, convoId, text);
    console.log(`  [${i + 1}] ${short(String(asRecord(sent).id || "?"))} ${text}`);
  }

  console.log("\n=== Latest Messages ===");
  const messageResponse = await getMessages(session.accessJwt, serviceDid, convoId);
  const messages = Array.isArray(asRecord(messageResponse).messages)
    ? asRecord(messageResponse).messages as unknown[]
    : [];
  console.log(`Messages: ${messages.length}`);
  printMessages(messages);
}

// ── Mode 2: Discover accounts and create conversations ─────────────────

async function modeDiscoverAndCreate(session: Session, serviceDid: string): Promise<void> {
  const targets = await resolveTargets(session.did, session.accessJwt);
  console.log(`Targets: ${targets.length}`);
  for (const target of targets) {
    console.log(`  ${target.handle ? `${target.handle} ` : ""}${target.did}`);
  }

  console.log("\n=== Create Or Reuse Conversations ===");
  const createdConvoIds: string[] = [];
  const skipped: string[] = [];
  for (const target of targets) {
    const label = target.handle || target.did;
    let convoId: string;
    try {
      const convoResponse = await getConvoForMembers(session.accessJwt, serviceDid, [
        session.did,
        target.did,
      ]);
      const convo = asRecord(asRecord(convoResponse).convo);
      convoId = String(convo.id || "");
      if (!convoId) throw new Error(`No convo id returned for ${label}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("Blocked") || msg.includes("does not allow incoming")) {
        console.log(`\n${label} -- SKIPPED (incoming messages blocked)`);
        skipped.push(target.did);
        continue;
      }
      throw err;
    }

    createdConvoIds.push(convoId);
    for (let i = 0; i < messageCount; i++) {
      const text = defaultMessage ||
        `Hello ${label}. Chat smoke from ${session.handle} at ${nowIso()}${messageCount > 1 ? ` (${i + 1}/${messageCount})` : ""}.`;
      const sent = await sendMessage(session.accessJwt, serviceDid, convoId, text);
      console.log(`\n${label}`);
      console.log(`  Convo: ${convoId}`);
      console.log(`  Sent: ${short(String(asRecord(sent).id || "?"))} ${text}`);
    }
  }
  if (skipped.length > 0) {
    console.log(`\nSkipped ${skipped.length} accounts with incoming messages blocked.`);
  }

  await printAllConvos(session, serviceDid, createdConvoIds);
}

// ── Mode 3: Back-and-forth between two accounts ────────────────────────

async function modeBackAndForth(sessionA: Session, sessionB: Session, serviceDid: string): Promise<void> {
  console.log(`\n=== Back-and-Forth Conversation ===`);
  console.log(`Account A: ${sessionA.handle} (${sessionA.did})`);
  console.log(`Account B: ${sessionB.handle} (${sessionB.did})`);
  console.log(`Rounds: ${rounds}`);

  const convoResponse = await getConvoForMembers(sessionA.accessJwt, serviceDid, [
    sessionA.did,
    sessionB.did,
  ]);
  const convo = asRecord(asRecord(convoResponse).convo);
  const convoId = String(convo.id || "");
  if (!convoId) throw new Error("No convo id returned for back-and-forth");
  console.log(`Convo: ${convoId}`);

  const totalMessages = rounds * 2;
  let sentCount = 0;

  for (let round = 0; round < rounds; round++) {
    const textA = defaultMessage ||
      `Round ${round + 1} from ${sessionA.handle} at ${nowIso()}.`;
    const sentA = await sendMessage(sessionA.accessJwt, serviceDid, convoId, textA);
    sentCount++;
    console.log(`  [${sentCount}/${totalMessages}] ${sessionA.handle}: ${textA}`);
    console.log(`    id: ${short(String(asRecord(sentA).id || "?"))}`);

    const textB = defaultMessage
      ? `${defaultMessage} (reply ${round + 1})`
      : `Round ${round + 1} reply from ${sessionB.handle} at ${nowIso()}.`;
    const sentB = await sendMessage(sessionB.accessJwt, serviceDid, convoId, textB);
    sentCount++;
    console.log(`  [${sentCount}/${totalMessages}] ${sessionB.handle}: ${textB}`);
    console.log(`    id: ${short(String(asRecord(sentB).id || "?"))}`);
  }

  console.log(`\nSent ${sentCount} messages total.`);

  console.log("\n=== Full Conversation Log ===");
  const messageResponse = await getMessages(sessionA.accessJwt, serviceDid, convoId);
  const messages = Array.isArray(asRecord(messageResponse).messages)
    ? asRecord(messageResponse).messages as unknown[]
    : [];
  console.log(`Messages: ${messages.length}`);
  printMessages(messages);
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const chatServiceDid = chatServiceDidForUrl(chatUrl);
  console.log(`PDS: ${pdsUrl}`);
  console.log(`Chat: ${chatUrl}`);
  console.log(`Chat DID: ${chatServiceDid}`);

  const session = await createSession(handle, password);
  console.log(`Account: ${session.handle}`);
  console.log(`DID: ${session.did}`);

  // Mode 1: existing conversation
  if (existingConvoId) {
    await modeExistingConvo(session, chatServiceDid);
    console.log("\nDone.");
    return;
  }

  // Mode 3: back-and-forth (requires alt account)
  if (backAndForth && altHandle && altPassword) {
    const altSession = await createSession(altHandle, altPassword);
    console.log(`Alt Account: ${altSession.handle}`);
    console.log(`Alt DID: ${altSession.did}`);

    await modeBackAndForth(session, altSession, chatServiceDid);
    console.log("\nDone.");
    return;
  }

  // Mode 2: discover targets and create conversations (default)
  await modeDiscoverAndCreate(session, chatServiceDid);
  console.log("\nDone.");
}

if (import.meta.main) {
  await main();
}
