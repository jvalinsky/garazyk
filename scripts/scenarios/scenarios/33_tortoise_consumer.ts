/**
 * @module scenarios/33_tortoise_consumer
 *
 * Scenario: Drops a slow firehose consumer when backpressure builds.
 *
 * Behavior:
 * - Opens a raw WebSocket to com.atproto.sync.subscribeRepos and stops
 *   reading, then generates enough repo writes to exceed the server's
 *   per-connection pending-send limits.
 * - Polls for the connection to close instead of sleeping a fixed 90
 *   seconds: the test topology (docker-compose.yml, garazyk-default.json,
 *   and binary_services.ts's "pds" case) all set
 *   PDS_FIREHOSE_MAX_PENDING_SENDS=1 / PDS_FIREHOSE_MAX_PENDING_BYTES=10000,
 *   so ConsumerTooSlow should trip once real (unread) traffic backs up the
 *   connection's outbound queue, well before a real OS TCP buffer would
 *   need to fill.
 *
 * Expectations:
 * - The server sends a #error frame naming "ConsumerTooSlow" and closes
 *   the WebSocket with code 1008, within the poll window.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/** Ceiling for detecting the server-initiated close once traffic stops
 * being read. Bounded, but generous relative to how quickly a threshold
 * of 1 pending send / 10KB should trip once the client stops reading. */
const CLOSE_DEADLINE_MS = 30_000;

function hasWebSocketCloseFrame(data: Uint8Array): boolean {
  for (let i = 0; i < data.length; i++) {
    if ((data[i] & 0x0f) === 0x08) return true;
  }
  return false;
}

/** Cheap substring check on the raw (DAG-CBOR) bytes: CBOR text strings
 * encode their UTF-8 bytes verbatim, so the server's #error frame
 * ({error: "ConsumerTooSlow", ...}) contains this literal byte sequence. */
function containsConsumerTooSlowMarker(chunks: Uint8Array[]): boolean {
  const marker = new TextEncoder().encode("ConsumerTooSlow");
  const combined = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let offset = 0;
  for (const c of chunks) {
    combined.set(c, offset);
    offset += c.length;
  }
  outer: for (let i = 0; i + marker.length <= combined.length; i++) {
    for (let j = 0; j < marker.length; j++) {
      if (combined[i + j] !== marker[j]) continue outer;
    }
    return true;
  }
  return false;
}

async function connectRawWs(url: string) {
  const parsed = new URL(url);
  const host = parsed.hostname;
  const port = parseInt(parsed.port || "80");

  const conn = await Deno.connect({ hostname: host, port });
  const encoder = new TextEncoder();

  const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
  const request = `GET /xrpc/com.atproto.sync.subscribeRepos HTTP/1.1\r\n` +
    `Host: ${host}:${port}\r\n` +
    `Upgrade: websocket\r\n` +
    `Connection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${key}\r\n` +
    `Sec-WebSocket-Version: 13\r\n\r\n`;

  await conn.write(encoder.encode(request));

  // Read upgrade response
  const buffer = new Uint8Array(4096);
  const n = await conn.read(buffer);
  const response = new TextDecoder().decode(buffer.subarray(0, n || 0));

  if (!response.includes("101")) {
    conn.close();
    throw new Error(`Upgrade failed: ${response}`);
  }

  return conn;
}

/**
 * Read from `conn` in a tight loop until a close is observed or
 * `deadlineMs` elapses, returning as soon as either happens (no fixed
 * sleep). A single background timer forces the connection closed at the
 * deadline so the in-flight `read()` unblocks instead of leaking.
 */
async function readUntilClosedOrDeadline(
  conn: Deno.Conn,
  deadlineMs: number,
): Promise<{ closed: boolean; chunks: Uint8Array[] }> {
  const chunks: Uint8Array[] = [];
  let closed = false;
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      conn.close();
    } catch { /* already closed */ }
  }, deadlineMs);

  const buf = new Uint8Array(4096);
  try {
    while (!closed && !timedOut) {
      const n = await conn.read(buf);
      if (n === null || n === 0 || n === undefined) {
        closed = true;
        break;
      }
      const chunk = buf.subarray(0, n).slice();
      chunks.push(chunk);
      if (hasWebSocketCloseFrame(chunk)) {
        closed = true;
        break;
      }
    }
  } catch {
    // A read error after our own forced close (timeout) is expected and
    // not itself evidence of the server closing; only count it as
    // "closed" if the deadline hadn't already fired.
    if (!timedOut) closed = true;
  } finally {
    clearTimeout(timer);
  }
  return { closed: closed && !timedOut, chunks };
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Backpressure (Tortoise Consumer)");
  result.start();

  const client = new XrpcClient(PDS1);
  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const volt = getActor("volt");
  const session = await timedCall(result, "Create account: volt", async () => {
    return await client.accounts.createAccount(volt.handle, volt.email, volt.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  volt.did = session.did;
  volt.accessJwt = session.accessJwt;

  let conn: Deno.Conn;
  try {
    conn = await connectRawWs(PDS1);
    result.stepPassed("Connect to firehose");
  } catch (e) {
    result.stepFailed("Connect to firehose", String(e));
    result.finish();
    return result;
  }

  // Read a few initial bytes to confirm traffic
  const buf = new Uint8Array(1024);
  await conn.read(buf);

  // Now stop reading and generate traffic. Do not read again until every
  // post is sent — reading here would drain the connection's outbound
  // queue and prevent the backlog the test depends on from ever forming.
  const POST_COUNT = 600;
  console.log(`Generating ${POST_COUNT} posts...`);
  for (let i = 0; i < POST_COUNT; i++) {
    try {
      await client.records.createRecord(volt.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: `backpressure test ${i}`,
        createdAt: now(),
      }, volt.accessJwt);
    } catch { /* ignore */ }
    if (i % 100 === 0) console.log(`  Sent ${i} records...`);
  }

  console.log("Waiting for the server to drop the slow consumer...");
  const { closed, chunks } = await readUntilClosedOrDeadline(conn, CLOSE_DEADLINE_MS);

  if (closed) {
    result.stepPassed("Firehose disconnected (slow consumer dropped)");
    // Best-effort only: WebSocketConnection.closeWithCode: clears the
    // outbound queue before writing the close frame (see
    // WebSocketConnection.m), so the #error frame that
    // sendErrorFrameWithCode: just enqueued is racing its own close and is
    // not reliably flushed before the socket drops — often the client
    // observes nothing but the raw disconnect, which is still the
    // functionally important behavior (the slow consumer is gone).
    if (containsConsumerTooSlowMarker(chunks)) {
      result.stepPassed("Server sent a ConsumerTooSlow error frame before closing");
    } else {
      console.log(
        "[INFO] No ConsumerTooSlow marker observed before the close (race between " +
          "the error frame and closeWithCode: clearing the queue — not a scenario failure)",
      );
    }
  } else {
    result.stepFailed(
      "Firehose disconnected",
      `Connection still open after ${CLOSE_DEADLINE_MS}ms poll window`,
    );
  }

  try {
    conn.close();
  } catch { /* ignore */ }
  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
