/** ATProto firehose (subscribeRepos) client for consuming relay events. @module firehose */
import { decodeOptions } from "@ipld/dag-cbor";
import { decodeFirst } from "cborg";

/** Decoded DAG-CBOR header object from a subscribeRepos frame. */
export type FirehoseFrameHeader = Record<string, unknown>;

/** Decoded DAG-CBOR body object from a subscribeRepos frame. */
export type FirehoseFrameBody = Record<string, unknown>;

/** Parsed subscribeRepos frame with the original bytes preserved. */
export interface FirehoseFrame {
  /** Raw WebSocket payload bytes. */
  payload: Uint8Array;
  /** Decoded subscribeRepos header. */
  header: FirehoseFrameHeader;
  /** Decoded subscribeRepos body. */
  body: FirehoseFrameBody;
}

/** Error raised when a subscribeRepos binary frame is not valid DAG-CBOR. */
export class FirehoseFrameParseError extends Error {
  /** Create a parse error for a malformed firehose frame. */
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "FirehoseFrameParseError";
  }
}

/** An event received from the firehose subscription stream. */
export class FirehoseEvent {
  /** Sequence number reported by the firehose event. */
  public seq: number;

  /** Event type reported by the firehose event. */
  public type: string;

  /** Raw payload for the firehose event. */
  public payload: Uint8Array;

  /** Decoded subscribeRepos frame header. */
  public header: FirehoseFrameHeader;

  /** Decoded subscribeRepos frame body. */
  public body: FirehoseFrameBody;

  /**
   * Create a firehose event.
   * @param seq - Sequence number reported by the firehose event.
   * @param type - Event type reported by the firehose event.
   * @param payload - Raw event payload.
   * @param header - Decoded subscribeRepos frame header.
   * @param body - Decoded subscribeRepos frame body.
   */
  constructor(
    seq: number,
    type: string,
    payload: Uint8Array,
    header: FirehoseFrameHeader = {},
    body: FirehoseFrameBody = {},
  ) {
    this.seq = seq;
    this.type = type;
    this.payload = payload;
    this.header = header;
    this.body = body;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) && !(value instanceof Uint8Array);
}

function decodeDagCborObject(
  bytes: Uint8Array,
  label: string,
): [Record<string, unknown>, Uint8Array] {
  let decoded: unknown;
  let remainder: Uint8Array;

  try {
    [decoded, remainder] = decodeFirst(bytes, decodeOptions) as [
      unknown,
      Uint8Array,
    ];
  } catch (cause) {
    throw new FirehoseFrameParseError(`Invalid ${label} DAG-CBOR object`, {
      cause,
    });
  }

  if (!isRecord(decoded)) {
    throw new FirehoseFrameParseError(
      `Invalid ${label} DAG-CBOR object: expected map`,
    );
  }

  return [decoded, remainder];
}

function numberField(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function stringField(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/** Decode a subscribeRepos WebSocket frame into its header and body objects. */
export function parseFirehoseFrame(payload: Uint8Array): FirehoseFrame {
  const [header, bodyBytes] = decodeDagCborObject(payload, "header");
  const [body, trailingBytes] = decodeDagCborObject(bodyBytes, "body");

  if (trailingBytes.length > 0) {
    throw new FirehoseFrameParseError(
      `Invalid firehose frame: ${trailingBytes.length} trailing byte(s)`,
    );
  }

  return { payload, header, body };
}

/** Convert a decoded subscribeRepos frame into the legacy event wrapper. */
export function firehoseEventFromFrame(frame: FirehoseFrame): FirehoseEvent {
  const op = numberField(frame.header.op);
  const seq = numberField(frame.body.seq) ?? 0;
  const type = stringField(frame.header.t) ?? (op === -1 ? "error" : "unknown");
  return new FirehoseEvent(seq, type, frame.payload, frame.header, frame.body);
}

/** WebSocket client for the ATProto firehose (com.atproto.sync.subscribeRepos). */
export class FirehoseClient {
  /** WebSocket URL used for the firehose subscription. */
  public wsUrl: string;

  /** Events collected by the most recent subscription. */
  public events: FirehoseEvent[] = [];

  /** Create a firehose client connected to the given relay. */
  constructor(relayUrl = "ws://localhost:2584") {
    this.wsUrl = relayUrl.replace("http://", "ws://").replace(
      "https://",
      "wss://",
    ).replace(
      /\/$/,
      "",
    );
  }

  /** Subscribe to the firehose for a fixed duration, invoking callback per event. */
  subscribe(
    callback?: (e: FirehoseEvent) => void,
    durationS = 10.0,
    cursor?: number,
    signal?: AbortSignal,
  ): Promise<void> {
    const url = new URL(`${this.wsUrl}/xrpc/com.atproto.sync.subscribeRepos`);
    if (cursor !== undefined) {
      url.searchParams.append("cursor", cursor.toString());
    }

    return new Promise((resolve) => {
      if (signal?.aborted) {
        resolve();
        return;
      }

      console.log(`Connecting to firehose: ${url.toString()}`);
      const ws = new WebSocket(url.toString());
      ws.binaryType = "arraybuffer";

      const timeout = setTimeout(() => {
        ws.close();
        resolve();
      }, durationS * 1000);

      const onAbort = () => {
        clearTimeout(timeout);
        ws.close();
        resolve();
      };
      signal?.addEventListener("abort", onAbort, { once: true });

      ws.onopen = () => {
        console.log("Firehose connected");
      };

      ws.onmessage = (event) => {
        try {
          if (event.data instanceof ArrayBuffer) {
            const buf = new Uint8Array(event.data);
            const fe = firehoseEventFromFrame(parseFirehoseFrame(buf));
            if (callback) callback(fe);
          }
        } catch (e) {
          console.warn("Firehose parse error", e);
        }
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        signal?.removeEventListener("abort", onAbort);
        ws.close();
        resolve();
      };

      ws.onclose = () => {
        clearTimeout(timeout);
        signal?.removeEventListener("abort", onAbort);
        resolve();
      };
    });
  }

  /** Subscribe for the given duration and collect all received events into an array. */
  collect(
    durationS = 5.0,
    cursor?: number,
    signal?: AbortSignal,
  ): Promise<FirehoseEvent[]> {
    this.events = [];
    return this.subscribe((e) => this.events.push(e), durationS, cursor, signal)
      .then(() => this.events);
  }
}
