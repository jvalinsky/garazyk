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
  return stripAnsi(s).length;
}

function senderMeta(
  sender: unknown,
  selfDid: string,
): { label: string; isSelf: boolean } {
  const r = asR(sender);
  const did = String(r.did || "");
  const handle = String(r.handle || did);
  const isSelf = did === selfDid;
  return {
    label: isSelf
      ? ansiColor(handle, GREEN, BOLD)
      : ansiColor(handle, YELLOW, BOLD),
    isSelf,
  };
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
    const result = new Deno.Command("stty", { args: ["size"], stdout: "piped" })
      .outputSync();
    const text = new TextDecoder().decode(result.stdout).trim();
    const cols = Number(text.split(" ")[1]);
    if (cols > 0) return cols;
  } catch {
    // stty not available
  }
  return 80;
}

export function ansiColor(s: string, ...codes: number[]): string {
  return `${codes.map((code) => `\x1b[${code}m`).join("")}${s}${ANSI.reset}`;
}

export function stripAnsi(s: string): string {
  // deno-lint-ignore no-control-regex -- SGR escape stripping intentionally matches ESC.
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

export function padRight(s: string, w: number): string {
  return s + " ".repeat(Math.max(0, w - visibleLen(s)));
}

export function padLeft(s: string, w: number): string {
  return " ".repeat(Math.max(0, w - visibleLen(s))) + s;
}

export function renderBoxTop(title: string): string {
  const width = getTermWidth();
  const inner = width - 4;
  const tLen = visibleLen(title);
  const left = Math.floor((inner - tLen) / 2);
  const right = inner - tLen - left;
  return (
    ansiColor(BOX.tl, BOLD, BLUE) + ansiColor(BOX.h.repeat(left), BLUE) +
    title +
    ansiColor(BOX.h.repeat(right), BLUE) +
    ansiColor(BOX.tr, BOLD, BLUE)
  );
}

export function renderBoxBottom(): string {
  const width = getTermWidth();
  return ansiColor(BOX.bl, BOLD, BLUE) +
    ansiColor(BOX.h.repeat(width - 4), BLUE) +
    ansiColor(BOX.br, BOLD, BLUE);
}

export function renderBoxMid(): string {
  const width = getTermWidth();
  return ansiColor(BOX.lt, BOLD, BLUE) +
    ansiColor(BOX.h.repeat(width - 4), BLUE) +
    ansiColor(BOX.rt, BOLD, BLUE);
}

export function renderBoxRow(content: string, width: number): string {
  const inner = width - 4;
  const pad = Math.max(0, inner - visibleLen(content));
  return ansiColor(BOX.v, BLUE) + " " + content + " ".repeat(pad) + " " +
    ansiColor(BOX.v, BLUE);
}

export function formatTimestamp(ts: string): string {
  if (!ts) return ansiColor("?", DIM);
  try {
    const d = new Date(ts.includes("T") ? ts : Number(ts) * 1000);
    if (isNaN(d.getTime())) return ansiColor(ts, DIM);
    const now = new Date();
    const time = d.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
    });
    if (d.toDateString() === now.toDateString()) return ansiColor(time, DIM);
    return ansiColor(
      `${
        d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
      } ${time}`,
      DIM,
    );
  } catch {
    return ansiColor(ts, DIM);
  }
}

export function formatSender(sender: unknown, selfDid: string): string {
  return senderMeta(sender, selfDid).label;
}

export function wrapText(text: string, max: number): string[] {
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

export function printChatMessage(msg: unknown, selfDid: string): void {
  const record = asR(msg);
  const sender = senderMeta(record.sender, selfDid);
  const ts = formatTimestamp(String(record.sentAt || record.createdAt || ""));
  const text = String(record.text ?? "");
  const id = String(record.id || "");
  const width = getTermWidth();

  // Inner content width: W - 4 (║ space ... space ║)
  const inner = width - 4;
  // Sidebar takes 2 chars (sidebar char + space), leaving inner - 2 for text
  const maxText = inner - 4;
  const lines = wrapText(text, maxText);

  if (sender.isSelf) {
    const bar = ansiColor("▐", BG_GREEN, BOLD);
    // Header line: right-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(
      ansiColor(BOX.v, BLUE) + " " + bar + padLeft(hdr, inner - 2) + " " +
        ansiColor(BOX.v, BLUE),
    );
    for (const line of lines) {
      console.log(
        ansiColor(BOX.v, BLUE) + " " + bar + padLeft(line, inner - 2) + " " +
          ansiColor(BOX.v, BLUE),
      );
    }
  } else {
    const bar = ansiColor("▌", BG_YELLOW, BOLD);
    // Header line: left-aligned
    const hdr = `${sender.label} ${ts}`;
    console.log(
      ansiColor(BOX.v, BLUE) + " " + bar + " " + padRight(hdr, inner - 4) +
        " " +
        ansiColor(BOX.v, BLUE),
    );
    for (const line of lines) {
      console.log(
        ansiColor(BOX.v, BLUE) + " " + bar + " " + padRight(line, inner - 4) +
          " " +
          ansiColor(BOX.v, BLUE),
      );
    }
  }

  if (id) {
    const idStr = ansiColor(id, DIM, ITALIC);
    console.log(
      ansiColor(BOX.v, BLUE) + " " + padRight(idStr, inner) + " " +
        ansiColor(BOX.v, BLUE),
    );
  }
}

export function printConversation(
  convo: unknown,
  idx: number,
  total: number,
  selfDid: string,
  messages: unknown[],
): void {
  const width = getTermWidth();
  const record = asR(convo);
  const cid = String(record.id || "");
  const members = Array.isArray(record.members)
    ? record.members as unknown[]
    : [];
  const unread = Number(record.unreadCount || 0);

  const labels = members.map((m) => formatSender(m, selfDid));

  const badge = unread > 0
    ? ansiColor(` ${unread} unread `, BG_MAGENTA, WHITE, BOLD)
    : "";
  const title = labels.join(ansiColor(", ", DIM));

  console.log(
    renderBoxTop(ansiColor(` Convo ${idx + 1}/${total} `, BOLD, WHITE)),
  );
  console.log(
    renderBoxRow(ansiColor("Members: ", DIM) + title + "  " + badge, width),
  );
  console.log(
    renderBoxRow(ansiColor("ID: ", DIM) + ansiColor(cid, DIM, ITALIC), width),
  );

  if (messages.length === 0) {
    console.log(renderBoxMid());
    console.log(renderBoxRow(ansiColor("(no messages)", DIM, ITALIC), width));
    console.log(renderBoxBottom());
    return;
  }

  console.log(renderBoxMid());
  console.log(
    renderBoxRow(
      ansiColor(
        `${messages.length} message${messages.length === 1 ? "" : "s"}`,
        DIM,
      ),
      width,
    ),
  );
  console.log(renderBoxMid());

  // Chronological: oldest first
  for (const raw of messages.toReversed()) {
    printChatMessage(raw, selfDid);
  }

  console.log(renderBoxBottom());
}
