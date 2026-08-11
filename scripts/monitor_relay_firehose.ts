#!/usr/bin/env -S deno run -A

/**
 * Monitor an AT Protocol relay's subscribeRepos firehose.
 *
 * The monitor prints one compact line per event and periodically emits a
 * summary of throughput, sequence progress, event types, commit actions, and
 * collections observed. It resumes from the highest sequence received after
 * a disconnect.
 */
import {
  type FirehoseEvent,
  firehoseEventFromFrame,
  parseFirehoseFrame,
} from "@garazyk/gruszka";
import { parseArgs } from "@std/cli/parse-args";
import { bold, dim, green, magenta, red, yellow } from "@std/fmt/colors";

export interface MonitorOptions {
  relayUrl: string;
  cursor?: number;
  durationS: number;
  maxEvents?: number;
  statsIntervalS: number;
  reconnectDelayS: number;
  color: boolean;
}

export interface RelayStats {
  startedAt: number;
  events: number;
  bytes: number;
  malformedFrames: number;
  reconnects: number;
  firstSeq?: number;
  lastSeq?: number;
  eventTypes: Map<string, number>;
  actions: Map<string, number>;
  collections: Map<string, number>;
  repos: Set<string>;
}

function usage(): never {
  console.log(`Usage: deno run -A scripts/monitor_relay_firehose.ts [options]

Connects to com.atproto.sync.subscribeRepos, prints events as they arrive,
and periodically prints live stream statistics. The monitor reconnects after
a disconnect and resumes with the highest sequence it has seen.

Options:
  --relay-url URL          Relay HTTP(S) or WebSocket URL
                           (default: RELAY_URL or https://relay.garazyk.xyz)
  --cursor SEQ             Start after this relay sequence number
  --duration SECONDS       Stop after this many seconds; 0 runs forever (default: 0)
  --max-events NUMBER      Stop after this many valid events
  --stats-interval SECONDS Print stats at this interval (default: 10)
  --reconnect-delay SECONDS
                           Wait this long before reconnecting (default: 3)
  --no-color               Disable ANSI colors
  -h, --help               Show this help

Examples:
  deno run -A scripts/monitor_relay_firehose.ts
  deno run -A scripts/monitor_relay_firehose.ts --duration 60
  deno run -A scripts/monitor_relay_firehose.ts --relay-url http://127.0.0.1:2470 --stats-interval 5
  deno run -A scripts/monitor_relay_firehose.ts --cursor 12345 --max-events 100
`);
  Deno.exit(0);
}

function positiveNumber(
  value: string,
  flag: string,
  allowZero = false,
): number {
  const parsed = Number(value);
  const valid = Number.isFinite(parsed) &&
    (allowZero ? parsed >= 0 : parsed > 0);
  if (!valid) {
    throw new Error(
      `${flag} must be ${allowZero ? "a non-negative" : "a positive"} number`,
    );
  }
  return parsed;
}

function optionalPositiveInteger(
  value: string,
  flag: string,
  allowZero = false,
): number {
  const parsed = Number(value);
  if (
    !Number.isSafeInteger(parsed) ||
    parsed < (allowZero ? 0 : 1)
  ) {
    throw new Error(
      `${flag} must be ${allowZero ? "a non-negative" : "a positive"} integer`,
    );
  }
  return parsed;
}

export function parseOptions(
  argv: string[],
  env = Deno.env.toObject(),
): MonitorOptions {
  const args = parseArgs(argv, {
    string: [
      "relay-url",
      "cursor",
      "duration",
      "max-events",
      "stats-interval",
      "reconnect-delay",
    ],
    boolean: ["help", "no-color"],
    alias: { h: "help" },
    default: { "no-color": false },
  });

  if (args.help) usage();

  const relayUrl = String(
    args["relay-url"] ?? env.RELAY_URL ?? "https://relay.garazyk.xyz",
  );
  const durationS = args.duration === undefined
    ? 0
    : positiveNumber(String(args.duration), "--duration", true);
  const statsIntervalS = args["stats-interval"] === undefined
    ? 10
    : positiveNumber(String(args["stats-interval"]), "--stats-interval");
  const reconnectDelayS = args["reconnect-delay"] === undefined
    ? 3
    : positiveNumber(
      String(args["reconnect-delay"]),
      "--reconnect-delay",
      true,
    );

  return {
    relayUrl,
    cursor: args.cursor === undefined
      ? undefined
      : optionalPositiveInteger(String(args.cursor), "--cursor", true),
    durationS,
    maxEvents: args["max-events"] === undefined
      ? undefined
      : optionalPositiveInteger(String(args["max-events"]), "--max-events"),
    statsIntervalS,
    reconnectDelayS,
    color: !Boolean(args["no-color"]),
  };
}

export function firehoseURL(relayUrl: string, cursor?: number): URL {
  const url = new URL(relayUrl);
  if (url.protocol === "http:") url.protocol = "ws:";
  if (url.protocol === "https:") url.protocol = "wss:";
  if (url.protocol !== "ws:" && url.protocol !== "wss:") {
    throw new Error(`Relay URL must use HTTP(S) or WebSocket: ${relayUrl}`);
  }

  url.pathname = "/xrpc/com.atproto.sync.subscribeRepos";
  url.search = "";
  if (cursor !== undefined) url.searchParams.set("cursor", String(cursor));
  return url;
}

export function createStats(startedAt = Date.now()): RelayStats {
  return {
    startedAt,
    events: 0,
    bytes: 0,
    malformedFrames: 0,
    reconnects: 0,
    eventTypes: new Map(),
    actions: new Map(),
    collections: new Map(),
    repos: new Set(),
  };
}

function bump(map: Map<string, number>, key: string): void {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function collectionOf(path: unknown): string {
  if (typeof path !== "string") return "(unknown)";
  const slash = path.indexOf("/");
  return slash === -1 ? path : path.slice(0, slash);
}

export function recordEvent(stats: RelayStats, event: FirehoseEvent): void {
  stats.events++;
  stats.bytes += event.payload.byteLength;
  bump(stats.eventTypes, event.type);

  if (event.seq > 0) {
    stats.firstSeq = stats.firstSeq === undefined
      ? event.seq
      : Math.min(stats.firstSeq, event.seq);
    stats.lastSeq = stats.lastSeq === undefined
      ? event.seq
      : Math.max(stats.lastSeq, event.seq);
  }

  const repo = event.body.repo;
  if (typeof repo === "string") stats.repos.add(repo);

  if (event.type !== "#commit" || !Array.isArray(event.body.ops)) return;
  for (const op of event.body.ops) {
    if (typeof op !== "object" || op === null || Array.isArray(op)) continue;
    const action = "action" in op && typeof op.action === "string"
      ? op.action
      : "(unknown)";
    const path = "path" in op ? op.path : undefined;
    bump(stats.actions, action);
    bump(stats.collections, collectionOf(path));
  }
}

function topEntries(map: Map<string, number>, limit = 8): string {
  return [...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([key, count]) => `${key}=${count}`)
    .join(" ") || "-";
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(2)} MiB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GiB`;
}

function paint(
  enabled: boolean,
  color: (text: string) => string,
  text: string,
): string {
  return enabled ? color(text) : text;
}

function shortRepo(repo: unknown): string {
  if (typeof repo !== "string") return "(unknown)";
  return repo.length > 35 ? `${repo.slice(0, 32)}...` : repo;
}

function truncate(value: string, length = 100): string {
  return value.length > length ? `${value.slice(0, length - 3)}...` : value;
}

function jsonSafe(value: unknown): unknown {
  if (value instanceof Uint8Array) return `<${value.byteLength} bytes>`;
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, jsonSafe(nested)]),
    );
  }
  return value;
}

export function printEvent(
  event: FirehoseEvent,
  bytes: number,
  color = true,
  output = console.log,
): void {
  const timestamp = paint(
    color,
    dim,
    `[${new Date().toISOString().slice(11, 19)}]`,
  );
  const type = event.type === "#commit"
    ? paint(color, green, event.type)
    : event.type === "error"
    ? paint(color, red, event.type)
    : paint(color, yellow, event.type);

  if (event.type === "#commit") {
    const ops = Array.isArray(event.body.ops) ? event.body.ops : [];
    const actions = new Map<string, number>();
    for (const op of ops) {
      if (typeof op !== "object" || op === null || Array.isArray(op)) continue;
      const action = "action" in op && typeof op.action === "string"
        ? op.action
        : "?";
      bump(actions, action);
    }
    const actionSummary = [...actions.entries()]
      .map(([action, count]) => `${action}:${count}`)
      .join(",") || "none";
    output(
      `${timestamp} ${type} seq=${event.seq} ` +
        `repo=${shortRepo(event.body.repo)} ops=${ops.length} ` +
        `(${actionSummary}) bytes=${bytes}`,
    );
    return;
  }

  const detail = event.type === "error"
    ? `${event.body.error ?? "unknown"}: ${event.body.message ?? ""}`
    : JSON.stringify(jsonSafe(event.body));
  output(
    `${timestamp} ${type} seq=${event.seq} ` +
      truncate(detail, 180) + ` bytes=${bytes}`,
  );
}

export function printStats(
  stats: RelayStats,
  color = true,
  output = console.log,
  now = Date.now(),
): void {
  const elapsedS = Math.max((now - stats.startedAt) / 1000, 0.001);
  const eventsPerSecond = stats.events / elapsedS;
  const bytesPerSecond = stats.bytes / elapsedS;
  const title = paint(
    color,
    bold,
    paint(color, magenta, "─ Relay firehose statistics ─"),
  );
  output("");
  output(title);
  output(
    `uptime=${elapsedS.toFixed(1)}s events=${stats.events} ` +
      `rate=${eventsPerSecond.toFixed(2)}/s bytes=${
        formatBytes(stats.bytes)
      } ` +
      `rate=${formatBytes(bytesPerSecond)}/s`,
  );
  output(
    `seq=${stats.firstSeq ?? "-"}..${stats.lastSeq ?? "-"} ` +
      `repos=${stats.repos.size} reconnects=${stats.reconnects} ` +
      `malformed=${stats.malformedFrames}`,
  );
  output(`types: ${topEntries(stats.eventTypes)}`);
  output(`actions: ${topEntries(stats.actions)}`);
  output(`collections: ${topEntries(stats.collections)}`);
}

async function messageBytes(data: unknown): Promise<Uint8Array | undefined> {
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (data instanceof Uint8Array) return data;
  if (data instanceof Blob) return new Uint8Array(await data.arrayBuffer());
  return undefined;
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
  });
}

async function connectOnce(
  url: URL,
  stats: RelayStats,
  signal: AbortSignal,
  options: MonitorOptions,
  stop: () => void,
): Promise<void> {
  await new Promise<void>((resolve) => {
    let settled = false;
    let pendingMessages = Promise.resolve();
    const socket = new WebSocket(url);
    socket.binaryType = "arraybuffer";

    const finish = async () => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", close);
      await pendingMessages;
      resolve();
    };
    const close = () => {
      try {
        socket.close();
      } catch {
        // The socket may already be closed.
      }
      void finish();
    };

    socket.onopen = () => {
      console.error(`Connected: ${url}`);
    };
    socket.onerror = () => {
      console.error(`WebSocket error: ${url}`);
      try {
        socket.close();
      } catch {
        // onclose will finish the connection.
      }
    };
    socket.onclose = () => {
      console.error("WebSocket closed");
      void finish();
    };
    signal.addEventListener("abort", close, { once: true });

    socket.onmessage = (message) => {
      pendingMessages = pendingMessages.then(async () => {
        const payload = await messageBytes(message.data);
        if (!payload) {
          console.error("Ignoring non-binary WebSocket message");
          return;
        }
        try {
          const event = firehoseEventFromFrame(parseFirehoseFrame(payload));
          recordEvent(stats, event);
          printEvent(event, payload.byteLength, options.color);
          if (
            options.maxEvents !== undefined &&
            stats.events >= options.maxEvents
          ) {
            stop();
          }
        } catch (cause) {
          stats.malformedFrames++;
          const detail = cause instanceof Error ? cause.message : String(cause);
          console.error(`Ignoring malformed firehose frame: ${detail}`);
        }
      });
    };
  });
}

export async function runMonitor(options: MonitorOptions): Promise<RelayStats> {
  const controller = new AbortController();
  const stats = createStats();
  let cursor = options.cursor;
  let durationTimer: number | undefined;

  const stop = () => controller.abort();
  if (options.durationS > 0) {
    durationTimer = setTimeout(stop, options.durationS * 1000);
  }
  const statsTimer = setInterval(
    () => printStats(stats, options.color),
    options.statsIntervalS * 1000,
  );

  const onInterrupt = () => {
    console.error("Stopping...");
    stop();
  };
  Deno.addSignalListener("SIGINT", onInterrupt);

  try {
    while (!controller.signal.aborted) {
      const url = firehoseURL(options.relayUrl, cursor);
      try {
        await connectOnce(url, stats, controller.signal, options, stop);
      } catch (cause) {
        console.error(
          `Unable to connect to ${url}: ${
            cause instanceof Error ? cause.message : cause
          }`,
        );
      }
      if (stats.lastSeq !== undefined) cursor = stats.lastSeq;
      if (controller.signal.aborted) break;

      stats.reconnects++;
      console.error(
        `Reconnecting in ${options.reconnectDelayS}s (cursor=${
          cursor ?? "none"
        })...`,
      );
      await sleep(options.reconnectDelayS * 1000, controller.signal);
    }
  } finally {
    if (durationTimer !== undefined) clearTimeout(durationTimer);
    clearInterval(statsTimer);
    Deno.removeSignalListener("SIGINT", onInterrupt);
    printStats(stats, options.color);
  }

  return stats;
}

if (import.meta.main) {
  try {
    await runMonitor(parseOptions(Deno.args));
  } catch (cause) {
    console.error(cause instanceof Error ? cause.message : cause);
    Deno.exit(1);
  }
}
