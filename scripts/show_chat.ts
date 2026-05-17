#!/usr/bin/env -S deno run -A

const pdsUrl = (Deno.env.get("PDS_URL") || "").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "").replace(/\/$/, "");
const handle = Deno.env.get("TEST_HANDLE") || "";
const password = Deno.env.get("TEST_PASSWORD") || "";
const messageLimit = Number(Deno.env.get("CHAT_MESSAGE_LIMIT") || "100");

if (!pdsUrl || !chatUrl || !handle || !password) {
  console.error(
    "PDS_URL, CHAT_URL, TEST_HANDLE, and TEST_PASSWORD environment variables are required.",
  );
  console.error(
    "Usage: PDS_URL=<url> CHAT_URL=<url> TEST_HANDLE=<handle> TEST_PASSWORD=<password> deno run -A show_chat.ts",
  );
  Deno.exit(1);
}

// ── Terminal size ──────────────────────────────────────────────────────

function getTermWidth(): number {
  // 1. Try Deno consoleSize (works for real TTYs)
  try {
    const { columns } = Deno.consoleSize();
    if (columns > 0) return columns;
  } catch {
    // not a TTY
  }
  // 2. Try COLUMNS env var (set by many shells)
  const envCols = Number(Deno.env.get("COLUMNS") || "0");
  if (envCols > 0) return envCols;
  // 3. Try stty as last resort
  try {
    const result = new Deno.Command("stty", { args: ["size"], stdout: "piped" }).outputSync();
    const text = new TextDecoder().decode(result.stdout).trim();
    const cols = Number(text.split(" ")[1]);
    if (cols > 0) return cols;
  } catch {
    // stty not available
  }
  return 80;
}

const W = getTermWidth();

// ── ANSI ───────────────────────────────────────────────────────────────

const R = "\x1b[0m";
const B = "\x1b[1m";
const D = "\x1b[2m";
const I = "\x1b[3m";
const grn = "\x1b[32m";
const ylw = "\x1b[33m";
const blu = "\x1b[34m";
const mag = "\x1b[35m";
const wht = "\x1b[37m";
const bgG = "\x1b[42m";
const bgY = "\x1b[43m";
const bgM = "\x1b[45m";

function c(s: string, ...codes: string[]): string {
  return codes.join("") + s + R;
}

function vis(s: string): number {
  return s.replace(/\x1b\[[0-9;]*m/g, "").length;
}

function padR(s: string, w: number): string {
  return s + " ".repeat(Math.max(0, w - vis(s)));
}

function padL(s: string, w: number): string {
  return " ".repeat(Math.max(0, w - vis(s))) + s;
}

// ── Box drawing ────────────────────────────────────────────────────────

// All box functions use W as total width. Inner content width = W - 4 (║ space content space ║)

function boxTop(title: string): void {
  const inner = W - 4;
  const tLen = vis(title);
  const left = Math.floor((inner - tLen) / 2);
  const right = inner - tLen - left;
  console.log(
    c("╔", B, blu) + c("═".repeat(left), blu) + title + c("═".repeat(right), blu) + c("╗", B, blu),
  );
}

function boxBot(): void {
  console.log(c("╚", B, blu) + c("═".repeat(W - 4), blu) + c("╝", B, blu));
}

function boxMid(): void {
  console.log(c("╟", B, blu) + c("─".repeat(W - 4), blu) + c("╢", B, blu));
}

function boxRow(content: string): void {
  const inner = W - 4;
  const pad = Math.max(0, inner - vis(content));
  console.log(c("║", blu) + " " + content + " ".repeat(pad) + " " + c("║", blu));
}

// ── XRPC ───────────────────────────────────────────────────────────────

type JR = Record<string, unknown>;

function asR(v: unknown): JR {
  return v && typeof v === "object" ? v as JR : {};
}

function chatDid(): string {
  const cfg = Deno.env.get("CHAT_SERVICE_DID");
  if (cfg) return cfg.includes("#") ? cfg : `${cfg}#bsky_chat`;
  const u = new URL(chatUrl);
  const h = u.hostname === "127.0.0.1" || u.hostname === "::1" ? "localhost" : u.hostname;
  const defPort = !u.port || (u.protocol === "https:" && u.port === "443") ||
    (u.protocol === "http:" && u.port === "80");
  return `did:web:${defPort ? h : `${h}%3A${u.port}`}#bsky_chat`;
}

async function xrpcGet(
  baseUrl: string,
  method: string,
  params: JR = {},
  token?: string,
): Promise<JR> {
  const url = new URL(`/xrpc/${method}`, baseUrl);
  for (const [k, v] of Object.entries(params)) {
    if (v == null) continue;
    if (Array.isArray(v)) {
      for (const item of v) if (item != null) url.searchParams.append(k, String(item));
      continue;
    }
    url.searchParams.set(k, String(v));
  }
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  const resp = await fetch(url, { headers });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`${method} failed (${resp.status}): ${JSON.stringify(body)}`);
  return body as JR;
}

async function xrpcPost(
  baseUrl: string,
  method: string,
  postBody: JR,
  token?: string,
): Promise<JR> {
  const url = new URL(`/xrpc/${method}`, baseUrl);
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const resp = await fetch(url, { method: "POST", headers, body: JSON.stringify(postBody) });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`${method} failed (${resp.status}): ${JSON.stringify(body)}`);
  return body as JR;
}

async function srvAuth(method: string, jwt: string, did: string): Promise<string> {
  const r = await xrpcGet(
    pdsUrl,
    "com.atproto.server.getServiceAuth",
    { aud: did, lxm: method },
    jwt,
  );
  const t = String(asR(r).token || "");
  if (!t) throw new Error(`getServiceAuth returned no token for ${method}`);
  return t;
}

async function listConvos(jwt: string, did: string) {
  const t = await srvAuth("chat.bsky.convo.listConvos", jwt, did);
  return xrpcGet(chatUrl, "chat.bsky.convo.listConvos", { limit: 100 }, t);
}

async function getMsgs(jwt: string, did: string, cid: string) {
  const t = await srvAuth("chat.bsky.convo.getMessages", jwt, did);
  return xrpcGet(chatUrl, "chat.bsky.convo.getMessages", { convoId: cid, limit: messageLimit }, t);
}

// ── Formatting ─────────────────────────────────────────────────────────

function fmtTs(ts: string): string {
  if (!ts) return c("?", D);
  try {
    const d = new Date(ts.includes("T") ? ts : Number(ts) * 1000);
    if (isNaN(d.getTime())) return c(ts, D);
    const now = new Date();
    const time = d.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
    });
    if (d.toDateString() === now.toDateString()) return c(time, D);
    return c(`${d.toLocaleDateString("en-US", { month: "short", day: "numeric" })} ${time}`, D);
  } catch {
    return c(ts, D);
  }
}

function fmtSender(sender: unknown, selfDid: string): { label: string; isSelf: boolean } {
  const r = asR(sender);
  const did = String(r.did || "");
  const h = String(r.handle || did);
  const isSelf = did === selfDid;
  return { label: isSelf ? c(h, grn, B) : c(h, ylw, B), isSelf };
}

function wrap(text: string, max: number): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let cur = "";
  for (const w of words) {
    if (cur.length + w.length + 1 > max) {
      if (cur) lines.push(cur);
      cur = w;
    } else cur = cur ? `${cur} ${w}` : w;
  }
  if (cur) lines.push(cur);
  return lines.length > 0 ? lines : [text];
}

// ── Message rendering ─────────────────────────────────────────────────

function printMsg(msg: JR, selfDid: string) {
  const sender = fmtSender(msg.sender, selfDid);
  const ts = fmtTs(String(msg.sentAt || msg.createdAt || ""));
  const text = String(msg.text ?? "");
  const id = String(msg.id || "");

  // Inner content width: W - 4 (║ space ... space ║)
  const inner = W - 4;
  // Sidebar takes 2 chars (sidebar char + space), leaving inner - 2 for text
  const maxText = inner - 4;
  const lines = wrap(text, maxText);

  if (sender.isSelf) {
    const bar = c("▐", bgG, B);
    // Header line: right-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(c("║", blu) + " " + bar + padL(hdr, inner - 2) + " " + c("║", blu));
    for (const line of lines) {
      console.log(c("║", blu) + " " + bar + padL(line, inner - 2) + " " + c("║", blu));
    }
  } else {
    const bar = c("▌", bgY, B);
    // Header line: left-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(c("║", blu) + " " + bar + " " + padR(hdr, inner - 4) + " " + c("║", blu));
    for (const line of lines) {
      console.log(c("║", blu) + " " + bar + " " + padR(line, inner - 4) + " " + c("║", blu));
    }
  }

  if (id) {
    const idStr = c(id, D, I);
    console.log(c("║", blu) + " " + padR(idStr, inner) + " " + c("║", blu));
  }
}

function printConvo(convo: JR, idx: number, total: number, selfDid: string, messages: unknown[]) {
  const cid = String(convo.id || "");
  const members = Array.isArray(convo.members) ? convo.members as unknown[] : [];
  const unread = Number(convo.unreadCount || 0);

  const labels = members.map((m) => {
    const r = asR(m);
    const did = String(r.did || "");
    const h = String(r.handle || did);
    return did === selfDid ? c(h, grn, B) : c(h, ylw, B);
  });

  const badge = unread > 0 ? c(` ${unread} unread `, bgM, wht, B) : "";
  const title = labels.join(c(", ", D));

  boxTop(c(` Convo ${idx + 1}/${total} `, B, wht));
  boxRow(c("Members: ", D) + title + "  " + badge);
  boxRow(c("ID: ", D) + c(cid, D, I));

  if (messages.length === 0) {
    boxMid();
    boxRow(c("(no messages)", D, I));
    boxBot();
    return;
  }

  boxMid();
  boxRow(c(`${messages.length} message${messages.length === 1 ? "" : "s"}`, D));
  boxMid();

  // Chronological: oldest first
  for (const raw of messages.toReversed()) {
    printMsg(asR(raw), selfDid);
  }

  boxBot();
}

// ── Main ───────────────────────────────────────────────────────────────

async function main() {
  const did = chatDid();

  console.log();
  boxTop(c(" Garazyk Chat Viewer ", B, wht));
  boxMid();
  boxRow(c("PDS:  ", D) + c(pdsUrl, blu));
  boxRow(c("Chat: ", D) + c(chatUrl, blu));
  boxRow(c("DID:  ", D) + c(did, blu));
  boxRow(c("Term: ", D) + c(`${W} cols`, D));
  boxMid();

  // Login
  const session = await xrpcPost(pdsUrl, "com.atproto.server.createSession", {
    identifier: handle,
    password,
  });
  const jwt = String(asR(session).accessJwt || "");
  const selfDid = String(asR(session).did || "");
  const sHandle = String(asR(session).handle || handle);
  if (!jwt || !selfDid) {
    throw new Error("Login succeeded but response did not include accessJwt and did");
  }

  boxRow(c("Auth: ", D) + c(sHandle, grn, B) + c(` (${selfDid})`, D));
  boxBot();
  console.log();

  // Fetch convos
  console.log(c("  Fetching conversations…", D, I));
  const convoResp = await listConvos(jwt, did);
  const convos = Array.isArray(asR(convoResp).convos) ? asR(convoResp).convos as unknown[] : [];

  if (convos.length === 0) {
    console.log();
    console.log(c("  No conversations found.", ylw));
    console.log();
    return;
  }

  console.log(c(`  Found ${convos.length} conversation${convos.length === 1 ? "" : "s"}`, B));
  console.log();

  for (let i = 0; i < convos.length; i++) {
    const convo = asR(convos[i]);
    const cid = String(convo.id || "");
    if (!cid) continue;

    const msgResp = await getMsgs(jwt, did, cid);
    const msgs = Array.isArray(asR(msgResp).messages) ? asR(msgResp).messages as unknown[] : [];

    printConvo(convo, i, convos.length, selfDid, msgs);
    console.log();
  }
}

if (import.meta.main) {
  await main();
}
