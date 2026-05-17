export const ANSI = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[92m",
  blue: "\x1b[94m",
  red: "\x1b[91m",
  yellow: "\x1b[93m",
  cyan: "\x1b[96m",
  magenta: "\x1b[95m",
} as const;

export const BOX = {
  tl: "╭",
  tr: "╮",
  bl: "╰",
  br: "╯",
  h: "─",
  v: "│",
  lt: "├",
  rt: "┤",
  tt: "┬",
  bt: "┴",
  cross: "┼",
} as const;

const BOLD = 1;
const DIM = 2;
const ITALIC = 3;
const BLUE = 94;
const GREEN = 92;
const YELLOW = 93;
const WHITE = 37;
const BG_GREEN = 42;
const BG_YELLOW = 43;
const BG_MAGENTA = 45;

function asR(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" ? v as Record<string, unknown> : {};
}

function visibleLen(s: string): number {
  return vis(s).length;
}

function senderMeta(sender: unknown, selfDid: string): { label: string; isSelf: boolean } {
  const r = asR(sender);
  const did = String(r.did || "");
  const handle = String(r.handle || did);
  const isSelf = did === selfDid;
  return { label: isSelf ? c(handle, GREEN, BOLD) : c(handle, YELLOW, BOLD), isSelf };
}

export function getTermWidth(): number {
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

export function c(s: string, ...codes: number[]): string {
  return `${codes.map((code) => `\x1b[${code}m`).join("")}${s}${ANSI.reset}`;
}

export function vis(s: string): string {
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

export function padR(s: string, w: number): string {
  return s + " ".repeat(Math.max(0, w - visibleLen(s)));
}

export function padL(s: string, w: number): string {
  return " ".repeat(Math.max(0, w - visibleLen(s))) + s;
}

export function boxTop(title: string): string {
  const width = getTermWidth();
  const inner = width - 4;
  const tLen = visibleLen(title);
  const left = Math.floor((inner - tLen) / 2);
  const right = inner - tLen - left;
  return (
    c(BOX.tl, BOLD, BLUE) + c(BOX.h.repeat(left), BLUE) + title + c(BOX.h.repeat(right), BLUE) +
    c(BOX.tr, BOLD, BLUE)
  );
}

export function boxBot(): string {
  const width = getTermWidth();
  return c(BOX.bl, BOLD, BLUE) + c(BOX.h.repeat(width - 4), BLUE) + c(BOX.br, BOLD, BLUE);
}

export function boxMid(): string {
  const width = getTermWidth();
  return c(BOX.lt, BOLD, BLUE) + c(BOX.h.repeat(width - 4), BLUE) + c(BOX.rt, BOLD, BLUE);
}

export function boxRow(content: string, width: number): string {
  const inner = width - 4;
  const pad = Math.max(0, inner - visibleLen(content));
  return c(BOX.v, BLUE) + " " + content + " ".repeat(pad) + " " + c(BOX.v, BLUE);
}

export function fmtTs(ts: string): string {
  if (!ts) return c("?", DIM);
  try {
    const d = new Date(ts.includes("T") ? ts : Number(ts) * 1000);
    if (isNaN(d.getTime())) return c(ts, DIM);
    const now = new Date();
    const time = d.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
    });
    if (d.toDateString() === now.toDateString()) return c(time, DIM);
    return c(`${d.toLocaleDateString("en-US", { month: "short", day: "numeric" })} ${time}`, DIM);
  } catch {
    return c(ts, DIM);
  }
}

export function fmtSender(sender: any, selfDid: string): string {
  return senderMeta(sender, selfDid).label;
}

export function wrap(text: string, max: number): string[] {
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

export function printMsg(msg: any, selfDid: string): void {
  const sender = senderMeta(msg.sender, selfDid);
  const ts = fmtTs(String(msg.sentAt || msg.createdAt || ""));
  const text = String(msg.text ?? "");
  const id = String(msg.id || "");
  const width = getTermWidth();

  // Inner content width: W - 4 (║ space ... space ║)
  const inner = width - 4;
  // Sidebar takes 2 chars (sidebar char + space), leaving inner - 2 for text
  const maxText = inner - 4;
  const lines = wrap(text, maxText);

  if (sender.isSelf) {
    const bar = c("▐", BG_GREEN, BOLD);
    // Header line: right-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(c(BOX.v, BLUE) + " " + bar + padL(hdr, inner - 2) + " " + c(BOX.v, BLUE));
    for (const line of lines) {
      console.log(c(BOX.v, BLUE) + " " + bar + padL(line, inner - 2) + " " + c(BOX.v, BLUE));
    }
  } else {
    const bar = c("▌", BG_YELLOW, BOLD);
    // Header line: left-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(c(BOX.v, BLUE) + " " + bar + " " + padR(hdr, inner - 4) + " " + c(BOX.v, BLUE));
    for (const line of lines) {
      console.log(c(BOX.v, BLUE) + " " + bar + " " + padR(line, inner - 4) + " " + c(BOX.v, BLUE));
    }
  }

  if (id) {
    const idStr = c(id, DIM, ITALIC);
    console.log(c(BOX.v, BLUE) + " " + padR(idStr, inner) + " " + c(BOX.v, BLUE));
  }
}

export function printConvo(convo: any, idx: number, total: number, selfDid: string, messages: any[]): void {
  const width = getTermWidth();
  const cid = String(convo.id || "");
  const members = Array.isArray(convo.members) ? convo.members as unknown[] : [];
  const unread = Number(convo.unreadCount || 0);

  const labels = members.map((m) => fmtSender(m, selfDid));

  const badge = unread > 0 ? c(` ${unread} unread `, BG_MAGENTA, WHITE, BOLD) : "";
  const title = labels.join(c(", ", DIM));

  console.log(boxTop(c(` Convo ${idx + 1}/${total} `, BOLD, WHITE)));
  console.log(boxRow(c("Members: ", DIM) + title + "  " + badge, width));
  console.log(boxRow(c("ID: ", DIM) + c(cid, DIM, ITALIC), width));

  if (messages.length === 0) {
    console.log(boxMid());
    console.log(boxRow(c("(no messages)", DIM, ITALIC), width));
    console.log(boxBot());
    return;
  }

  console.log(boxMid());
  console.log(boxRow(c(`${messages.length} message${messages.length === 1 ? "" : "s"}`, DIM), width));
  console.log(boxMid());

  // Chronological: oldest first
  for (const raw of messages.toReversed()) {
    printMsg(raw, selfDid);
  }

  console.log(boxBot());
}
