/**
 * @module scenarios/96_firehose_cursor_resume
 *
 * Scenario: Gap-free firehose cursor resume across a disconnect/reconnect.
 *
 * Behavior:
 * - Connects to the live PDS's com.atproto.sync.subscribeRepos, generates
 *   a few events, and disconnects, recording the last sequence number seen.
 * - Generates more events *while disconnected* (no consumer attached).
 * - Reconnects with `?cursor=<lastSeq>` and asserts the resumed stream
 *   picks up at exactly lastSeq+1 (no gap), contains no sequence number
 *   already seen in the first session (no duplicate), and actually
 *   contains the records created during the disconnect window (verified
 *   by matching the operation paths from createRecord URIs against the
 *   ops array of #commit events for the same repo).
 *
 * This exercises SubscribeReposHandler's persisted-sequence resume path
 * (-ensureSequenceInitialized seeds from the DB max, not from 0, so a
 * reconnecting client doesn't see a regression) directly against the PDS.
 * It does not cover the Relay's own upstream reconnect
 * (RelayUpstreamManager) — that tracks cursor per upstream independently
 * and would need its own scenario if it becomes a concern.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { firehoseEventFromFrame, parseFirehoseFrame } from "../../lib/deno/firehose.ts";

const WS_OPCODE_TEXT = 0x1;
const WS_OPCODE_BINARY = 0x2;
const WS_OPCODE_CLOSE = 0x8;

async function connectRawWs(url: string): Promise<Deno.Conn> {
  const parsed = new URL(url);
  const host = parsed.hostname;
  const port = parseInt(parsed.port || "80");

  const conn = await Deno.connect({ hostname: host, port });
  const encoder = new TextEncoder();

  const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
  const request = `GET ${parsed.pathname}${parsed.search} HTTP/1.1\r\n` +
    `Host: ${host}:${port}\r\n` +
    `Upgrade: websocket\r\n` +
    `Connection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${key}\r\n` +
    `Sec-WebSocket-Version: 13\r\n\r\n`;

  await conn.write(encoder.encode(request));

  const buffer = new Uint8Array(4096);
  const n = await conn.read(buffer);
  const response = new TextDecoder().decode(buffer.subarray(0, n || 0));

  if (!response.includes("101")) {
    conn.close();
    throw new Error(`Upgrade failed: ${response}`);
  }

  return conn;
}

interface ParsedFrame {
  opcode: number;
  payload: Uint8Array;
}

/** Minimal server-to-client (unmasked) WebSocket frame reader over a raw
 * TCP stream. Handles the 7-bit and 16-bit extended payload-length forms;
 * firehose events in this test are small enough that the 64-bit form
 * never comes up. */
class RawWsFrameReader {
  #conn: Deno.Conn;
  #buf: Uint8Array = new Uint8Array(0);

  constructor(conn: Deno.Conn) {
    this.#conn = conn;
  }

  #append(chunk: Uint8Array): void {
    const combined = new Uint8Array(this.#buf.length + chunk.length);
    combined.set(this.#buf, 0);
    combined.set(chunk, this.#buf.length);
    this.#buf = combined;
  }

  /** Try to pull one complete frame out of the buffered bytes. */
  #tryParseFrame(): ParsedFrame | null {
    if (this.#buf.length < 2) return null;
    const opcode = this.#buf[0] & 0x0f;
    const masked = (this.#buf[1] & 0x80) !== 0;
    let payloadLen = this.#buf[1] & 0x7f;
    let offset = 2;

    if (payloadLen === 126) {
      if (this.#buf.length < 4) return null;
      payloadLen = (this.#buf[2] << 8) | this.#buf[3];
      offset = 4;
    } else if (payloadLen === 127) {
      if (this.#buf.length < 10) return null;
      // Only the low 32 bits are used; firehose test payloads are small.
      payloadLen = (this.#buf[6] << 24) | (this.#buf[7] << 16) | (this.#buf[8] << 8) | this.#buf[9];
      offset = 10;
    }

    const maskLen = masked ? 4 : 0;
    const total = offset + maskLen + payloadLen;
    if (this.#buf.length < total) return null;

    let payload = this.#buf.slice(offset + maskLen, total);
    if (masked) {
      const mask = this.#buf.slice(offset, offset + 4);
      const unmasked = new Uint8Array(payload.length);
      for (let i = 0; i < payload.length; i++) {
        unmasked[i] = payload[i] ^ mask[i % 4];
      }
      payload = unmasked;
    }

    this.#buf = this.#buf.slice(total);
    return { opcode, payload };
  }

  /** Read frames until `predicate` returns true for a frame, the
   * connection closes, or `deadlineMs` elapses. Returns every frame seen
   * (including the one that satisfied the predicate, if any) plus whether
   * a close frame/EOF was observed. */
  async readUntil(
    deadlineMs: number,
    predicate: (frames: ParsedFrame[]) => boolean,
  ): Promise<{ frames: ParsedFrame[]; closed: boolean }> {
    const frames: ParsedFrame[] = [];
    let closed = false;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        this.#conn.close();
      } catch { /* already closed */ }
    }, deadlineMs);

    const readBuf = new Uint8Array(65536);
    try {
      while (!timedOut) {
        let frame = this.#tryParseFrame();
        while (frame) {
          frames.push(frame);
          if (frame.opcode === WS_OPCODE_CLOSE) {
            closed = true;
          }
          if (predicate(frames) || closed) {
            clearTimeout(timer);
            return { frames, closed };
          }
          frame = this.#tryParseFrame();
        }
        const n = await this.#conn.read(readBuf);
        if (n === null || n === 0) {
          closed = true;
          break;
        }
        this.#append(readBuf.subarray(0, n));
      }
    } catch {
      if (!timedOut) closed = true;
    } finally {
      clearTimeout(timer);
    }
    return { frames, closed };
  }
}

interface FirehoseEventLike {
  seq: number;
  body: Record<string, unknown>;
}

function decodeDataFrames(frames: ParsedFrame[]): FirehoseEventLike[] {
  const events: FirehoseEventLike[] = [];
  for (const f of frames) {
    if (f.opcode !== WS_OPCODE_BINARY && f.opcode !== WS_OPCODE_TEXT) continue;
    try {
      const fe = firehoseEventFromFrame(parseFirehoseFrame(f.payload));
      events.push({ seq: fe.seq, body: fe.body });
    } catch {
      // Not a decodable firehose frame; skip.
    }
  }
  return events;
}

const CURSOR_RESUME_TIMEOUT_MS = 8_000;

/** Connect, collect events (and detect close) for up to `timeoutMs`. */
async function collectFirehoseEvents(
  cursor: number | undefined,
  timeoutMs: number,
  minEvents: number,
): Promise<FirehoseEventLike[]> {
  const url = new URL(`${PDS1}/xrpc/com.atproto.sync.subscribeRepos`);
  if (cursor !== undefined) url.searchParams.set("cursor", String(cursor));

  const conn = await connectRawWs(url.toString());
  const reader = new RawWsFrameReader(conn);
  try {
    const { frames } = await reader.readUntil(timeoutMs, (seen) => {
      return decodeDataFrames(seen).length >= minEvents;
    });
    return decodeDataFrames(frames);
  } finally {
    try {
      conn.close();
    } catch { /* already closed */ }
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Cursor Resume (Gap-Free)");
  result.start();

  const client = new XrpcClient(PDS1);
  const pigeon = getActor("nova");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(result, "Create account: pigeon", async () => {
    return await client.accounts.createAccount(
      pigeon.handle,
      pigeon.email,
      pigeon.password,
    );
  });
  if (!session) {
    result.finish();
    return result;
  }
  pigeon.did = session.did;
  pigeon.accessJwt = session.accessJwt;

  await timedCall(result, "Create record before disconnect", async () => {
    return await client.records.createRecord(pigeon.did!, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "cursor resume: before disconnect",
      createdAt: now(),
    }, pigeon.accessJwt!);
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Connecting without a cursor replays the persisted backlog (including
  // the record just created above) before switching to live mode, so this
  // doesn't race the write.
  const firstBatch = await collectFirehoseEvents(undefined, CURSOR_RESUME_TIMEOUT_MS, 1);
  if (firstBatch.length === 0) {
    result.stepFailed(
      "First session observed events",
      "No firehose events received on initial connection. Check PDS health and " +
        "subscribeRepos endpoint.",
    );
    result.finish();
    return result;
  }
  result.stepPassed(
    "First session observed events",
    `count=${firstBatch.length} lastSeq=${firstBatch[firstBatch.length - 1]?.seq}`,
  );

  const cursorAfterFirstSession = Math.max(...firstBatch.map((e) => e.seq));
  const seenInFirstSession = new Set(firstBatch.map((e) => e.seq));

  // Generate more traffic with nobody connected to the firehose.
  let uri1 = "";
  let uri2 = "";
  await timedCall(result, "Create records while disconnected", async () => {
    const r1 = await client.records.createRecord(pigeon.did!, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "cursor resume: during disconnect",
      createdAt: now(),
    }, pigeon.accessJwt!);
    uri1 = (r1 as any).uri;
    const r2 = await client.records.createRecord(pigeon.did!, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "cursor resume: during disconnect (2)",
      createdAt: now(),
    }, pigeon.accessJwt!);
    uri2 = (r2 as any).uri;
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const resumedBatch = await collectFirehoseEvents(cursorAfterFirstSession, CURSOR_RESUME_TIMEOUT_MS, 5);
  if (resumedBatch.length === 0) {
    result.stepFailed(
      "Resumed session observed events",
      "No firehose events received on resumed connection. Check PDS health and " +
        "cursor replay path.",
    );
    result.finish();
    return result;
  }
  result.stepPassed("Resumed session observed events", `count=${resumedBatch.length}`);

  const resumedSeqs = resumedBatch.map((e) => e.seq);

  await timedCall(result, "No gap: first resumed seq is cursor+1", () => {
    const firstResumedSeq = resumedSeqs[0];
    assert.isTrue(
      firstResumedSeq === cursorAfterFirstSession + 1,
      `Expected first resumed seq ${cursorAfterFirstSession + 1}, got ${firstResumedSeq} ` +
        `(all resumed seqs: ${resumedSeqs.join(",")})`,
    );
  });

  await timedCall(result, "No duplicate: no resumed seq was already seen", () => {
    const duplicates = resumedSeqs.filter((s) => seenInFirstSession.has(s));
    assert.isTrue(
      duplicates.length === 0,
      `Resumed session re-delivered already-seen seq(s): ${duplicates.join(",")}`,
    );
  });

  await timedCall(result, "Monotonic: resumed seqs strictly increase", () => {
    let ordered = true;
    for (let i = 0; i < resumedSeqs.length - 1; i++) {
      if (resumedSeqs[i] >= resumedSeqs[i + 1]) {
        ordered = false;
        break;
      }
    }
    assert.isTrue(ordered, `Resumed seqs not strictly increasing: ${resumedSeqs.join(",")}`);
  });

  await timedCall(result, "Records created during disconnect were delivered", () => {
    // Extract collection/rkey paths from the URIs returned by createRecord.
    const path1 = uri1.split("/").slice(-2).join("/");
    const path2 = uri2.split("/").slice(-2).join("/");

    // Gather all operation paths from #commit events for the pigeon's repo.
    const deliveredPaths = resumedBatch
      .filter((e) => (e.body as any).repo === pigeon.did && Array.isArray((e.body as any).ops))
      .flatMap((e) => ((e.body as any).ops as any[]).map((op: any) => op.path));

    assert.isTrue(deliveredPaths.includes(path1),
      `First disconnected record (${path1}) not found among resumed ops: ${deliveredPaths.join(", ")}`);
    assert.isTrue(deliveredPaths.includes(path2),
      `Second disconnected record (${path2}) not found among resumed ops: ${deliveredPaths.join(", ")}`);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
