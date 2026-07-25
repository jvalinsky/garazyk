#!/usr/bin/env -S deno run -A

/** Print decoded com.atproto.sync.subscribeRepos messages from an ATProto relay. */
import { parseFirehoseFrame } from "@garazyk/gruszka";

interface Options {
  relayUrl: string;
  cursor?: number;
  count: number;
  timeoutMs: number;
  includeBytes: boolean;
}

function usage(): never {
  console.log(`Usage: deno run -A scripts/dump_relay_firehose.ts [options]

Connects to a relay's com.atproto.sync.subscribeRepos XRPC WebSocket and
prints each decoded DAG-CBOR header and body as JSON.

Options:
  --relay-url URL       Relay HTTP(S) or WebSocket URL
                          (default: RELAY_URL or https://relay.garazyk.xyz)
  --cursor SEQ          Resume after this relay sequence number
  --count NUMBER        Stop after this many messages (default: 10)
  --timeout SECONDS     Stop if the count is not reached in this time (default: 30)
  --include-bytes       Include binary fields as base64 instead of byte counts
  -h, --help            Show this help

Examples:
  deno run -A scripts/dump_relay_firehose.ts --count 3
  deno run -A scripts/dump_relay_firehose.ts --relay-url http://127.0.0.1:2584 --cursor 42
`);
  Deno.exit(0);
}

function positiveInteger(
  value: string,
  flag: string,
  allowZero = false,
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < (allowZero ? 0 : 1)) {
    throw new Error(
      `${flag} must be ${allowZero ? "a non-negative" : "a positive"} integer`,
    );
  }
  return parsed;
}

function parseOptions(argv: string[]): Options {
  const options: Options = {
    relayUrl: Deno.env.get("RELAY_URL") || "https://relay.garazyk.xyz",
    count: 10,
    timeoutMs: 30_000,
    includeBytes: false,
  };

  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    const value = argv[index + 1];
    switch (argument) {
      case "--help":
      case "-h":
        return usage();
      case "--relay-url":
        if (!value) throw new Error("--relay-url requires a value");
        options.relayUrl = value;
        index++;
        break;
      case "--cursor":
        if (!value) throw new Error("--cursor requires a value");
        options.cursor = positiveInteger(value, "--cursor", true);
        index++;
        break;
      case "--count":
        if (!value) throw new Error("--count requires a value");
        options.count = positiveInteger(value, "--count");
        index++;
        break;
      case "--timeout":
        if (!value) throw new Error("--timeout requires a value");
        options.timeoutMs = positiveInteger(value, "--timeout") * 1000;
        index++;
        break;
      case "--include-bytes":
        options.includeBytes = true;
        break;
      default:
        throw new Error(`Unknown option: ${argument}`);
    }
  }

  return options;
}

function firehoseURL(relayUrl: string, cursor?: number): URL {
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

function base64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 32 * 1024;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(
      ...bytes.subarray(offset, offset + chunkSize),
    );
  }
  return btoa(binary);
}

function jsonSafe(value: unknown, includeBytes: boolean): unknown {
  if (value instanceof Uint8Array) {
    const output: Record<string, unknown> = { $bytes: value.byteLength };
    if (includeBytes) output.$base64 = base64(value);
    return output;
  }
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) {
    return value.map((item) => jsonSafe(item, includeBytes));
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map((
        [key, nested],
      ) => [key, jsonSafe(nested, includeBytes)]),
    );
  }
  return value;
}

async function dumpMessages(options: Options): Promise<void> {
  const url = firehoseURL(options.relayUrl, options.cursor);
  console.error(`Connecting to ${url}`);

  await new Promise<void>((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.binaryType = "arraybuffer";
    let received = 0;
    let settled = false;

    const settle = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket.close();
      if (error) reject(error);
      else resolve();
    };

    const timeout = setTimeout(() => {
      settle(
        new Error(
          `Timed out after ${
            options.timeoutMs / 1000
          } seconds with ${received}/${options.count} messages`,
        ),
      );
    }, options.timeoutMs);

    socket.onopen = () => console.error("Connected");
    socket.onerror = () =>
      settle(new Error(`WebSocket error while connecting to ${url}`));
    socket.onclose = () => {
      if (!settled) {
        settle(
          new Error(
            `WebSocket closed after ${received}/${options.count} messages`,
          ),
        );
      }
    };
    socket.onmessage = (message) => {
      if (settled) return;
      if (!(message.data instanceof ArrayBuffer)) {
        console.error(
          `Ignoring non-binary WebSocket message (${typeof message.data})`,
        );
        return;
      }

      try {
        const frame = parseFirehoseFrame(new Uint8Array(message.data));
        received++;
        console.log(JSON.stringify(
          {
            receivedAt: new Date().toISOString(),
            bytes: message.data.byteLength,
            header: jsonSafe(frame.header, options.includeBytes),
            body: jsonSafe(frame.body, options.includeBytes),
          },
          null,
          2,
        ));
        if (received >= options.count) settle();
      } catch (cause) {
        const messageText = cause instanceof Error
          ? cause.message
          : String(cause);
        console.error(`Ignoring undecodable firehose frame: ${messageText}`);
      }
    };
  });
}

if (import.meta.main) {
  try {
    await dumpMessages(parseOptions(Deno.args));
  } catch (cause) {
    console.error(cause instanceof Error ? cause.message : cause);
    Deno.exit(1);
  }
}
