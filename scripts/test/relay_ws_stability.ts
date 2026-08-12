#!/usr/bin/env -S deno run -A
/**
 * Long-lived WebSocket stability probe for a relay subscribeRepos stream.
 *
 * Connects to com.atproto.sync.subscribeRepos, stays up for a configurable
 * duration, and records every disconnect (close code, reason, session age,
 * events seen). Optionally reconnects so sporadic drops show up as a count
 * rather than a single early exit.
 *
 * Usage:
 *   deno run -A scripts/test/relay_ws_stability.ts
 *   deno run -A scripts/test/relay_ws_stability.ts --duration 900 --reconnect
 *   deno run -A scripts/test/relay_ws_stability.ts --relay-url https://relay.garazyk.xyz --no-reconnect
 *   RELAY_WS_STABILITY_JSON_OUT=/tmp/relay-ws.json deno run -A scripts/test/relay_ws_stability.ts --duration 600
 */

import { parseArgs } from "@std/cli/parse-args";
import {
  firehoseEventFromFrame,
  parseFirehoseFrame,
} from "@garazyk/gruszka";

export interface StabilityOptions {
  relayUrl: string;
  durationS: number;
  reconnect: boolean;
  reconnectDelayS: number;
  cursor?: number;
  heartbeatIntervalS: number;
  idleWarnS: number;
  parseFrames: boolean;
  jsonOut?: string;
}

export interface DisconnectRecord {
  atIso: string;
  sessionIndex: number;
  sessionDurationMs: number;
  code: number;
  reason: string;
  wasClean: boolean;
  eventsInSession: number;
  bytesInSession: number;
  lastSeq?: number;
  msSinceLastEvent?: number;
  errorMessage?: string;
}

export interface StabilitySummary {
  relayUrl: string;
  firehoseUrl: string;
  startedAtIso: string;
  endedAtIso: string;
  wallDurationMs: number;
  sessions: number;
  reconnects: number;
  disconnects: DisconnectRecord[];
  totalEvents: number;
  totalBytes: number;
  malformedFrames: number;
  firstSeq?: number;
  lastSeq?: number;
  longestSessionMs: number;
  shortestSessionMs: number | null;
  meanSessionMs: number | null;
  stillConnected: boolean;
}

function usage(): never {
  console.log(`Usage: deno run -A scripts/test/relay_ws_stability.ts [options]

Probe relay WebSocket stability on com.atproto.sync.subscribeRepos.

Options:
  --relay-url URL           Relay HTTP(S) or WS(S) URL
                            (default: RELAY_URL or https://relay.garazyk.xyz)
  --duration SECONDS        How long to run the probe (default: 600)
  --reconnect / --no-reconnect
                            Reconnect after drops (default: reconnect)
  --reconnect-delay SECONDS Delay before reconnect (default: 2)
  --cursor SEQ              Start after this sequence number
  --heartbeat SECONDS       Log a heartbeat line this often (default: 30)
  --idle-warn SECONDS       Warn if no frames for this long (default: 120)
  --no-parse                Count frames without DAG-CBOR parse (faster drain;
                            useful when catching up a large backlog)
  --json-out PATH           Write machine-readable summary JSON
  -h, --help                Show this help

Close codes of interest on Garazyk relays:
  1008 ConsumerTooSlow           — subscriber fell behind firehose policy
  1009 Outbound queue limit exceeded — websocket outbound buffer tripped

Connecting with no cursor against a busy relay often produces those closes
immediately; pass --cursor near the tip (from a prior probe) to test mid-stream
stability separately from catch-up backpressure.

Examples:
  deno run -A scripts/test/relay_ws_stability.ts --duration 900
  deno run -A scripts/test/relay_ws_stability.ts --duration 300 --no-reconnect
  deno run -A scripts/test/relay_ws_stability.ts --duration 600 --cursor 100877
  deno run -A scripts/test/relay_ws_stability.ts --duration 120 --no-parse
`);
  Deno.exit(0);
}

function positiveNumber(value: string, flag: string, allowZero = false): number {
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

export function parseOptions(
  argv: string[],
  env = Deno.env.toObject(),
): StabilityOptions {
  const args = parseArgs(argv, {
    string: [
      "relay-url",
      "duration",
      "reconnect-delay",
      "cursor",
      "heartbeat",
      "idle-warn",
      "json-out",
    ],
    boolean: ["help", "reconnect", "no-reconnect", "no-parse"],
    alias: { h: "help" },
    default: {
      reconnect: true,
      "no-reconnect": false,
      "no-parse": false,
    },
  });

  if (args.help) usage();

  const durationS = args.duration
    ? positiveNumber(String(args.duration), "--duration", true)
    : 600;
  const reconnect = args["no-reconnect"] ? false : Boolean(args.reconnect);
  const reconnectDelayS = args["reconnect-delay"]
    ? positiveNumber(String(args["reconnect-delay"]), "--reconnect-delay", true)
    : 2;
  const heartbeatIntervalS = args.heartbeat
    ? positiveNumber(String(args.heartbeat), "--heartbeat")
    : 30;
  const idleWarnS = args["idle-warn"]
    ? positiveNumber(String(args["idle-warn"]), "--idle-warn")
    : 120;
  const cursor = args.cursor !== undefined
    ? positiveNumber(String(args.cursor), "--cursor", true)
    : undefined;

  return {
    relayUrl: String(args["relay-url"] ?? env.RELAY_URL ?? "https://relay.garazyk.xyz"),
    durationS,
    reconnect,
    reconnectDelayS,
    cursor: cursor === undefined ? undefined : Math.trunc(cursor),
    heartbeatIntervalS,
    idleWarnS,
    parseFrames: !Boolean(args["no-parse"]),
    jsonOut: args["json-out"]
      ? String(args["json-out"])
      : env.RELAY_WS_STABILITY_JSON_OUT,
  };
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const rem = s - m * 60;
  return `${m}m${rem.toFixed(0).padStart(2, "0")}s`;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MiB`;
}

function logLine(message: string): void {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${message}`);
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

interface SessionResult {
  disconnect?: DisconnectRecord;
  closedByProbe: boolean;
  lastSeq?: number;
  events: number;
  bytes: number;
  malformedFrames: number;
}

async function connectOnce(
  url: URL,
  sessionIndex: number,
  signal: AbortSignal,
  idleWarnS: number,
  parseFrames: boolean,
): Promise<SessionResult> {
  return await new Promise<SessionResult>((resolve) => {
    let settled = false;
    let pendingMessages = Promise.resolve();
    let openedAt = 0;
    let events = 0;
    let bytes = 0;
    let malformedFrames = 0;
    let lastSeq: number | undefined;
    let lastEventAt: number | undefined;
    let errorMessage: string | undefined;
    let closedByProbe = false;
    let idleTimer: number | undefined;

    const socket = new WebSocket(url);
    socket.binaryType = "arraybuffer";

    const clearIdle = () => {
      if (idleTimer !== undefined) {
        clearInterval(idleTimer);
        idleTimer = undefined;
      }
    };

    const finish = async (disconnect?: DisconnectRecord) => {
      if (settled) return;
      settled = true;
      clearIdle();
      signal.removeEventListener("abort", onAbort);
      await pendingMessages;
      resolve({
        disconnect,
        closedByProbe,
        lastSeq,
        events,
        bytes,
        malformedFrames,
      });
    };

    const onAbort = () => {
      closedByProbe = true;
      try {
        socket.close(1000, "probe duration elapsed");
      } catch {
        // already closed
      }
    };

    socket.onopen = () => {
      openedAt = Date.now();
      lastEventAt = openedAt;
      logLine(`session#${sessionIndex} open ${url}`);
      idleTimer = setInterval(() => {
        if (!lastEventAt) return;
        const idleMs = Date.now() - lastEventAt;
        if (idleMs >= idleWarnS * 1000) {
          logLine(
            `session#${sessionIndex} idle ${formatDuration(idleMs)} (no frames; socket still open)`,
          );
        }
      }, Math.min(idleWarnS, 30) * 1000);
    };

    socket.onerror = () => {
      errorMessage = "WebSocket error event";
      logLine(`session#${sessionIndex} error`);
    };

    socket.onclose = (event) => {
      const now = Date.now();
      const sessionDurationMs = openedAt > 0 ? now - openedAt : 0;
      const disconnect: DisconnectRecord = {
        atIso: new Date(now).toISOString(),
        sessionIndex,
        sessionDurationMs,
        code: event.code,
        reason: event.reason || "",
        wasClean: event.wasClean,
        eventsInSession: events,
        bytesInSession: bytes,
        lastSeq,
        msSinceLastEvent: lastEventAt ? now - lastEventAt : undefined,
        errorMessage,
      };
      logLine(
        `session#${sessionIndex} close code=${event.code} clean=${event.wasClean}` +
          ` reason=${JSON.stringify(event.reason || "")}` +
          ` age=${formatDuration(sessionDurationMs)}` +
          ` events=${events} bytes=${formatBytes(bytes)}` +
          (lastSeq !== undefined ? ` lastSeq=${lastSeq}` : "") +
          (closedByProbe ? " (probe stop)" : ""),
      );
      void finish(disconnect);
    };

    signal.addEventListener("abort", onAbort, { once: true });

    socket.onmessage = (message) => {
      pendingMessages = pendingMessages.then(async () => {
        const payload = await messageBytes(message.data);
        if (!payload) {
          logLine(`session#${sessionIndex} ignoring non-binary frame`);
          return;
        }
        bytes += payload.byteLength;
        lastEventAt = Date.now();
        if (!parseFrames) {
          events++;
          return;
        }
        try {
          const event = firehoseEventFromFrame(parseFirehoseFrame(payload));
          events++;
          if (event.seq > 0) lastSeq = event.seq;
        } catch (cause) {
          malformedFrames++;
          const detail = cause instanceof Error ? cause.message : String(cause);
          logLine(`session#${sessionIndex} malformed frame: ${detail}`);
        }
      });
    };
  });
}

export async function runStabilityProbe(
  options: StabilityOptions,
): Promise<StabilitySummary> {
  const startedAt = Date.now();
  const controller = new AbortController();
  const disconnects: DisconnectRecord[] = [];
  let sessions = 0;
  let reconnects = 0;
  let totalEvents = 0;
  let totalBytes = 0;
  let malformedFrames = 0;
  let firstSeq: number | undefined;
  let lastSeq = options.cursor;
  let stillConnected = false;
  let longestSessionMs = 0;
  const sessionDurations: number[] = [];

  const stop = () => controller.abort();
  let durationTimer: number | undefined;
  if (options.durationS > 0) {
    durationTimer = setTimeout(stop, options.durationS * 1000);
  }

  const heartbeatTimer = setInterval(() => {
    const elapsed = Date.now() - startedAt;
    logLine(
      `heartbeat elapsed=${formatDuration(elapsed)}` +
        ` sessions=${sessions} disconnects=${disconnects.length}` +
        ` events=${totalEvents} bytes=${formatBytes(totalBytes)}` +
        (lastSeq !== undefined ? ` lastSeq=${lastSeq}` : ""),
    );
  }, options.heartbeatIntervalS * 1000);

  const onInterrupt = () => {
    logLine("SIGINT — stopping probe");
    stop();
  };
  Deno.addSignalListener("SIGINT", onInterrupt);

  try {
    while (!controller.signal.aborted) {
      sessions++;
      const url = firehoseURL(options.relayUrl, lastSeq);
      stillConnected = true;
      const result = await connectOnce(
        url,
        sessions,
        controller.signal,
        options.idleWarnS,
        options.parseFrames,
      );
      stillConnected = false;

      totalEvents += result.events;
      totalBytes += result.bytes;
      malformedFrames += result.malformedFrames;
      if (result.lastSeq !== undefined) {
        firstSeq = firstSeq === undefined
          ? result.lastSeq
          : Math.min(firstSeq, result.lastSeq);
        lastSeq = result.lastSeq;
      }

      if (result.disconnect) {
        const d = result.disconnect;
        longestSessionMs = Math.max(longestSessionMs, d.sessionDurationMs);
        if (!result.closedByProbe) {
          disconnects.push(d);
          sessionDurations.push(d.sessionDurationMs);
        } else if (d.sessionDurationMs > 0) {
          sessionDurations.push(d.sessionDurationMs);
          longestSessionMs = Math.max(longestSessionMs, d.sessionDurationMs);
        }
      }

      if (controller.signal.aborted) break;
      if (!options.reconnect) break;

      reconnects++;
      logLine(
        `reconnect #${reconnects} in ${options.reconnectDelayS}s` +
          (lastSeq !== undefined ? ` from cursor=${lastSeq}` : ""),
      );
      await sleep(options.reconnectDelayS * 1000, controller.signal);
    }
  } finally {
    if (durationTimer !== undefined) clearTimeout(durationTimer);
    clearInterval(heartbeatTimer);
    try {
      Deno.removeSignalListener("SIGINT", onInterrupt);
    } catch {
      // ignore
    }
  }

  const endedAt = Date.now();
  const meanSessionMs = sessionDurations.length === 0
    ? null
    : sessionDurations.reduce((a, b) => a + b, 0) / sessionDurations.length;
  const shortestSessionMs = sessionDurations.length === 0
    ? null
    : Math.min(...sessionDurations);

  const summary: StabilitySummary = {
    relayUrl: options.relayUrl,
    firehoseUrl: firehoseURL(options.relayUrl, options.cursor).toString(),
    startedAtIso: new Date(startedAt).toISOString(),
    endedAtIso: new Date(endedAt).toISOString(),
    wallDurationMs: endedAt - startedAt,
    sessions,
    reconnects,
    disconnects,
    totalEvents,
    totalBytes,
    malformedFrames,
    firstSeq,
    lastSeq,
    longestSessionMs,
    shortestSessionMs,
    meanSessionMs,
    stillConnected,
  };

  return summary;
}

function printSummary(summary: StabilitySummary): void {
  console.log("");
  console.log("== Relay WebSocket stability summary ==");
  console.log(`relay:        ${summary.relayUrl}`);
  console.log(`firehose:     ${summary.firehoseUrl}`);
  console.log(`wall time:    ${formatDuration(summary.wallDurationMs)}`);
  console.log(`sessions:     ${summary.sessions}`);
  console.log(`reconnects:   ${summary.reconnects}`);
  console.log(`disconnects:  ${summary.disconnects.length}`);
  console.log(`events:       ${summary.totalEvents}`);
  console.log(`bytes:        ${formatBytes(summary.totalBytes)}`);
  console.log(
    `seq range:    ${summary.firstSeq ?? "-"} .. ${summary.lastSeq ?? "-"}`,
  );
  console.log(`longest sess: ${formatDuration(summary.longestSessionMs)}`);
  console.log(
    `shortest sess:${
      summary.shortestSessionMs == null
        ? " -"
        : " " + formatDuration(summary.shortestSessionMs)
    }`,
  );
  console.log(
    `mean sess:    ${
      summary.meanSessionMs == null
        ? "-"
        : formatDuration(summary.meanSessionMs)
    }`,
  );

  if (summary.disconnects.length === 0) {
    console.log("result:       no unexpected disconnects during the probe window");
  } else {
    const policy = summary.disconnects.filter((d) =>
      d.code === 1008 || d.code === 1009 ||
      /ConsumerTooSlow|Outbound queue/i.test(d.reason)
    );
    console.log(
      `result:       ${summary.disconnects.length} unexpected disconnect(s)` +
        ` (${policy.length} look like relay backpressure policy)`,
    );
    console.log("disconnects:");
    for (const d of summary.disconnects) {
      console.log(
        `  #${d.sessionIndex} ${d.atIso} age=${formatDuration(d.sessionDurationMs)}` +
          ` code=${d.code} clean=${d.wasClean} reason=${JSON.stringify(d.reason)}` +
          ` events=${d.eventsInSession}` +
          (d.lastSeq !== undefined ? ` lastSeq=${d.lastSeq}` : ""),
      );
    }
  }
}

async function main(): Promise<void> {
  const options = parseOptions(Deno.args);
  logLine(
    `probe start relay=${options.relayUrl} duration=${options.durationS}s` +
      ` reconnect=${options.reconnect}`,
  );
  const summary = await runStabilityProbe(options);
  printSummary(summary);

  if (options.jsonOut) {
    await Deno.writeTextFile(
      options.jsonOut,
      JSON.stringify(summary, null, 2) + "\n",
    );
    logLine(`wrote JSON summary to ${options.jsonOut}`);
  }

  // Non-zero exit if we saw unexpected disconnects (useful for CI/alerts).
  if (summary.disconnects.length > 0) {
    Deno.exit(2);
  }
}

if (import.meta.main) {
  await main();
}
