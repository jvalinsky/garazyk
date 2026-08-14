/**
 * @module scenarios/102_zuk_cursor_containment
 *
 * Verifies the relay's omitted-cursor contract under deliberately small
 * replay and outbound-queue limits. A no-cursor subscription is live-only:
 * retained seed commits must not arrive, while a sentinel committed after the
 * WebSocket upgrade must arrive. The check is repeated across reconnects,
 * then a non-reading subscriber is forced through the existing bounded
 * output path without fixed sleeps.
 *
 * Run with `--topology zuk-cursor-containment`. That topology applies
 * PDS_FIREHOSE_MAX_REPLAY=4 and PDS_FIREHOSE_MAX_PENDING_{SENDS,BYTES} to
 * Zuk, not to production deployments.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import {
  createAccountOrLogin,
  now,
  ScenarioResult,
  timedCall,
} from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import {
  firehoseEventFromFrame,
  parseFirehoseFrame,
} from "../../lib/deno/firehose.ts";

const REPLAY_WINDOW = 4;
const SEED_COUNT = REPLAY_WINDOW + 3;
const RECONNECT_COUNT = 25;
const EVENT_DEADLINE_MS = 12_000;
const RELAY_CATCH_UP_DEADLINE_MS = 12_000;
const RELAY_CATCH_UP_POLL_MS = 100;
const RELAY_QUIESCENCE_POLLS = 5;
const SLOW_CONSUMER_DEADLINE_MS = 30_000;
// 128 × 2.7–3.0 KiB UTF-8 text remains well beyond the 10 KiB/4-send fixture
// limits while respecting the server's byte-counted maxLength and
// maxGraphemes constraints.
const SLOW_CONSUMER_POST_COUNT = 128;
const SLOW_CONSUMER_TEXT_MAX_UTF8_BYTES = 3_000;
const SLOW_CONSUMER_TEXT_MAX_GRAPHEMES = 300;
const SLOW_CONSUMER_TEXT_TARGET_GRAPHEMES = 290;
const SLOW_CONSUMER_TEXT_MIN_UTF8_BYTES = 2_700;
const SLOW_CONSUMER_COMBINING_MARKS_PER_CLUSTER = 5;
const UPGRADE_HEADER_MAX_BYTES = 32 * 1024;
const UPGRADE_HEADER_DEADLINE_MS = 5_000;
const WS_OPCODE_BINARY = 0x2;
const WS_OPCODE_TEXT = 0x1;
const WS_OPCODE_CLOSE = 0x8;

interface ParsedFrame {
  opcode: number;
  payload: Uint8Array;
}

interface RelayEvent {
  seq: number;
  type: string;
  body: Record<string, unknown>;
}

interface ReadResult {
  events: RelayEvent[];
  closed: boolean;
}

interface RawWsConnection {
  conn: Deno.Conn;
  initialBytes: Uint8Array;
}

interface AttachedRawWsConnection extends RawWsConnection {
  downstreamBaseline: number;
  attachmentSequence: number;
}

/** Return the first received data event that predates confirmed attachment. */
export function eventAtOrBeforeAttachment(
  events: readonly { seq: number }[],
  attachmentSequence: number,
): { seq: number } | undefined {
  return events.find((event) => event.seq <= attachmentSequence);
}

/** Whether relay subscriber state proves a connection has detached. */
export function downstreamConnectionsReleased(
  observedConnections: number,
  baselineConnections: number,
): boolean {
  return observedConnections <= baselineConnections;
}

/** Count user-perceived grapheme clusters under the feed-record constraint. */
export function graphemeCount(text: string): number {
  return Array.from(
    new Intl.Segmenter("en", { granularity: "grapheme" }).segment(text),
  ).length;
}

/** Build a lexicon-valid, pressure-generating slow-consumer post body. */
export function slowConsumerPostText(index: number, nonce: string): string {
  const prefix = `z${index}-${nonce}-`;
  const prefixGraphemes = graphemeCount(prefix);
  const clusterCount = SLOW_CONSUMER_TEXT_TARGET_GRAPHEMES - prefixGraphemes;
  if (clusterCount <= 0) {
    throw new Error("Slow-consumer post prefix exhausts its grapheme budget");
  }
  const cluster = "x" +
    "\u0301".repeat(SLOW_CONSUMER_COMBINING_MARKS_PER_CLUSTER);
  const text = prefix + cluster.repeat(clusterCount);
  const utf8Bytes = new TextEncoder().encode(text).length;
  if (
    utf8Bytes > SLOW_CONSUMER_TEXT_MAX_UTF8_BYTES ||
    graphemeCount(text) > SLOW_CONSUMER_TEXT_MAX_GRAPHEMES ||
    utf8Bytes < SLOW_CONSUMER_TEXT_MIN_UTF8_BYTES
  ) {
    throw new Error(
      "Slow-consumer post does not satisfy server byte/grapheme pressure bounds",
    );
  }
  return text;
}

/** Typed relay state exposed by the health endpoint. */
export interface RelayHealthState {
  currentSequence: number;
  downstreamConnections: number;
}

/** Parse the relay fields used as scenario synchronization barriers. */
export function parseRelayHealthState(health: unknown): RelayHealthState {
  if (!health || typeof health !== "object") {
    throw new Error("Relay health response was not an object");
  }
  const response = health as Record<string, unknown>;
  const currentSequence = response.currentSequence;
  if (
    typeof currentSequence !== "number" ||
    !Number.isSafeInteger(currentSequence) ||
    currentSequence < 0
  ) {
    throw new Error(
      "Relay health response did not contain a non-negative integer currentSequence",
    );
  }
  const downstreamConnections = response.downstreamConnections;
  if (
    typeof downstreamConnections !== "number" ||
    !Number.isSafeInteger(downstreamConnections) || downstreamConnections < 0
  ) {
    throw new Error(
      "Relay health response did not contain a non-negative integer downstreamConnections",
    );
  }
  return { currentSequence, downstreamConnections };
}

/** Extract the monotonic output sequence from the relay health response. */
export function relayCurrentSequence(health: unknown): number {
  return parseRelayHealthState(health).currentSequence;
}

/** Whether repeated observations establish that the relay has quiesced. */
export function relaySequenceIsStable(
  observations: readonly number[],
  requiredObservations = RELAY_QUIESCENCE_POLLS,
): boolean {
  if (observations.length < requiredObservations) return false;
  const recent = observations.slice(-requiredObservations);
  return recent.every((sequence) => sequence === recent[0]);
}

async function relayHealthState(relay: XrpcClient): Promise<RelayHealthState> {
  return parseRelayHealthState(await relay.raw.httpGet("/api/relay/health"));
}

/** Poll relay health until its output sequence includes the named writes. */
async function waitForRelaySequence(
  relay: XrpcClient,
  minimumSequence: number,
): Promise<number> {
  const deadline = Date.now() + RELAY_CATCH_UP_DEADLINE_MS;
  let observed = -1;
  while (Date.now() < deadline) {
    observed = (await relayHealthState(relay)).currentSequence;
    if (observed >= minimumSequence) return observed;
    await new Promise((resolve) => setTimeout(resolve, RELAY_CATCH_UP_POLL_MS));
  }
  throw new Error(
    `Relay currentSequence=${observed} did not reach ${minimumSequence} within ` +
      `${RELAY_CATCH_UP_DEADLINE_MS}ms`,
  );
}

/** Wait for account/identity propagation to stop changing relay output. */
async function waitForRelayQuiescence(relay: XrpcClient): Promise<number> {
  const deadline = Date.now() + RELAY_CATCH_UP_DEADLINE_MS;
  const observations: number[] = [];
  while (Date.now() < deadline) {
    observations.push((await relayHealthState(relay)).currentSequence);
    if (relaySequenceIsStable(observations)) return observations.at(-1)!;
    await new Promise((resolve) => setTimeout(resolve, RELAY_CATCH_UP_POLL_MS));
  }
  throw new Error(
    `Relay currentSequence did not stabilize across ${RELAY_QUIESCENCE_POLLS} polls: ` +
      observations.slice(-RELAY_QUIESCENCE_POLLS).join(","),
  );
}

/** Wait until a raw WebSocket upgrade is visible in relay subscriber state. */
async function waitForRelayDownstreamConnections(
  relay: XrpcClient,
  minimumConnections: number,
): Promise<number> {
  const deadline = Date.now() + RELAY_CATCH_UP_DEADLINE_MS;
  let observed = -1;
  while (Date.now() < deadline) {
    observed = (await relayHealthState(relay)).downstreamConnections;
    if (observed >= minimumConnections) return observed;
    await new Promise((resolve) => setTimeout(resolve, RELAY_CATCH_UP_POLL_MS));
  }
  throw new Error(
    `Relay downstreamConnections=${observed} did not reach ${minimumConnections} within ` +
      `${RELAY_CATCH_UP_DEADLINE_MS}ms`,
  );
}

/** Wait for a closed test subscriber to disappear from relay state. */
async function waitForRelayDownstreamRelease(
  relay: XrpcClient,
  baselineConnections: number,
): Promise<number> {
  const deadline = Date.now() + RELAY_CATCH_UP_DEADLINE_MS;
  let observed = -1;
  while (Date.now() < deadline) {
    observed = (await relayHealthState(relay)).downstreamConnections;
    if (downstreamConnectionsReleased(observed, baselineConnections)) {
      return observed;
    }
    await new Promise((resolve) => setTimeout(resolve, RELAY_CATCH_UP_POLL_MS));
  }
  throw new Error(
    `Relay downstreamConnections=${observed} did not return to baseline ` +
      `${baselineConnections} within ${RELAY_CATCH_UP_DEADLINE_MS}ms`,
  );
}

/** Splits a complete HTTP upgrade response from any coalesced WebSocket bytes. */
export function splitWebSocketUpgradeResponse(
  bytes: Uint8Array,
): { header: string; remaining: Uint8Array } | undefined {
  for (let index = 0; index + 3 < bytes.length; index++) {
    if (
      bytes[index] === 0x0d && bytes[index + 1] === 0x0a &&
      bytes[index + 2] === 0x0d && bytes[index + 3] === 0x0a
    ) {
      return {
        header: new TextDecoder().decode(bytes.subarray(0, index + 4)),
        remaining: bytes.slice(index + 4),
      };
    }
  }
  return undefined;
}

async function readWebSocketUpgrade(
  conn: Deno.Conn,
): Promise<Uint8Array> {
  let responseBytes = new Uint8Array(0);
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      conn.close();
    } catch {
      // The peer may already have closed the connection.
    }
  }, UPGRADE_HEADER_DEADLINE_MS);
  const buffer = new Uint8Array(4096);
  try {
    while (!timedOut && responseBytes.length < UPGRADE_HEADER_MAX_BYTES) {
      const count = await conn.read(buffer);
      if (count === null || count === 0) break;
      const combined = new Uint8Array(responseBytes.length + count);
      combined.set(responseBytes);
      combined.set(buffer.subarray(0, count), responseBytes.length);
      responseBytes = combined;
      const response = splitWebSocketUpgradeResponse(responseBytes);
      if (response) {
        if (!/^HTTP\/1\.1 101(?:\s|$)/.test(response.header)) {
          throw new Error(`WebSocket upgrade failed: ${response.header}`);
        }
        return response.remaining;
      }
    }
  } finally {
    clearTimeout(timer);
  }
  if (timedOut) {
    throw new Error(
      `WebSocket upgrade timed out after ${UPGRADE_HEADER_DEADLINE_MS}ms`,
    );
  }
  if (responseBytes.length >= UPGRADE_HEADER_MAX_BYTES) {
    throw new Error(
      `WebSocket upgrade headers exceeded ${UPGRADE_HEADER_MAX_BYTES} bytes`,
    );
  }
  throw new Error("WebSocket closed before completing its upgrade response");
}

async function connectRawWs(
  serviceUrl: string,
  cursor?: number,
): Promise<RawWsConnection> {
  const url = new URL(`${serviceUrl}/xrpc/com.atproto.sync.subscribeRepos`);
  if (cursor !== undefined) url.searchParams.set("cursor", String(cursor));
  const port = Number(url.port || "80");
  const conn = await Deno.connect({ hostname: url.hostname, port });
  const key = btoa(
    String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))),
  );
  const request = `GET ${url.pathname}${url.search} HTTP/1.1\r\n` +
    `Host: ${url.hostname}:${port}\r\n` +
    "Upgrade: websocket\r\n" +
    "Connection: Upgrade\r\n" +
    `Sec-WebSocket-Key: ${key}\r\n` +
    "Sec-WebSocket-Version: 13\r\n\r\n";

  await conn.write(new TextEncoder().encode(request));
  try {
    return { conn, initialBytes: await readWebSocketUpgrade(conn) };
  } catch (error) {
    conn.close();
    throw error;
  }
}

/** Upgrade a subscription and wait for the relay to publish its attachment. */
async function connectAttachedRawWs(
  relay: XrpcClient,
  cursor?: number,
): Promise<AttachedRawWsConnection> {
  const before = (await relayHealthState(relay)).downstreamConnections;
  const connection = await connectRawWs(SERVICE_URLS.relay, cursor);
  try {
    await waitForRelayDownstreamConnections(relay, before + 1);
    return {
      ...connection,
      downstreamBaseline: before,
      attachmentSequence: (await relayHealthState(relay)).currentSequence,
    };
  } catch (error) {
    try {
      connection.conn.close();
    } catch {
      // The connection may have already been closed by the relay.
    }
    await waitForRelayDownstreamRelease(relay, before);
    throw error;
  }
}

/** Close a test subscriber and make its relay lifecycle observable before reuse. */
async function closeAttachedRawWs(
  relay: XrpcClient,
  connection: AttachedRawWsConnection,
): Promise<void> {
  try {
    connection.conn.close();
  } catch {
    // A slow-consumer close can win this race; relay state is still checked.
  }
  await waitForRelayDownstreamRelease(relay, connection.downstreamBaseline);
}

class RawWsFrameReader {
  #conn: Deno.Conn;
  #buffer: Uint8Array<ArrayBufferLike> = new Uint8Array(0);

  constructor(
    conn: Deno.Conn,
    initialBytes: Uint8Array<ArrayBufferLike> = new Uint8Array(0),
  ) {
    this.#conn = conn;
    this.#buffer = initialBytes;
  }

  #append(chunk: Uint8Array<ArrayBufferLike>): void {
    const combined = new Uint8Array(this.#buffer.length + chunk.length);
    combined.set(this.#buffer);
    combined.set(chunk, this.#buffer.length);
    this.#buffer = combined;
  }

  #nextFrame(): ParsedFrame | undefined {
    if (this.#buffer.length < 2) return undefined;
    const opcode = this.#buffer[0] & 0x0f;
    let payloadLength = this.#buffer[1] & 0x7f;
    const masked = (this.#buffer[1] & 0x80) !== 0;
    let offset = 2;
    if (payloadLength === 126) {
      if (this.#buffer.length < 4) return undefined;
      payloadLength = (this.#buffer[2] << 8) | this.#buffer[3];
      offset = 4;
    } else if (payloadLength === 127) {
      if (this.#buffer.length < 10) return undefined;
      payloadLength = (this.#buffer[6] << 24) | (this.#buffer[7] << 16) |
        (this.#buffer[8] << 8) | this.#buffer[9];
      offset = 10;
    }
    const maskLength = masked ? 4 : 0;
    const total = offset + maskLength + payloadLength;
    if (this.#buffer.length < total) return undefined;

    let payload = this.#buffer.slice(offset + maskLength, total);
    if (masked) {
      const mask = this.#buffer.slice(offset, offset + 4);
      payload = payload.map((byte, index) => byte ^ mask[index % 4]);
    }
    this.#buffer = this.#buffer.slice(total);
    return { opcode, payload };
  }

  async readUntil(
    deadlineMs: number,
    predicate: (events: RelayEvent[]) => boolean,
  ): Promise<ReadResult> {
    const events: RelayEvent[] = [];
    let closed = false;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        this.#conn.close();
      } catch {
        // The peer may already have closed the connection.
      }
    }, deadlineMs);
    const readBuffer = new Uint8Array(64 * 1024);
    try {
      while (!timedOut) {
        let frame = this.#nextFrame();
        while (frame) {
          if (frame.opcode === WS_OPCODE_CLOSE) closed = true;
          if (
            frame.opcode === WS_OPCODE_BINARY || frame.opcode === WS_OPCODE_TEXT
          ) {
            try {
              const decoded = firehoseEventFromFrame(
                parseFirehoseFrame(frame.payload),
              );
              events.push({
                seq: decoded.seq,
                type: decoded.type,
                body: decoded.body,
              });
            } catch {
              // A non-firehose control payload is irrelevant to this assertion.
            }
          }
          if (closed || predicate(events)) return { events, closed };
          frame = this.#nextFrame();
        }
        const count = await this.#conn.read(readBuffer);
        if (count === null || count === 0) {
          closed = true;
          break;
        }
        this.#append(readBuffer.subarray(0, count));
      }
    } catch {
      if (!timedOut) closed = true;
    } finally {
      clearTimeout(timer);
    }
    return { events, closed: closed && !timedOut };
  }
}

function eventContainsRkey(event: RelayEvent, rkey: string): boolean {
  if (event.type !== "#commit" || !Array.isArray(event.body.ops)) return false;
  return event.body.ops.some((operation) =>
    typeof operation === "object" && operation !== null &&
    (operation as Record<string, unknown>).path === `app.bsky.feed.post/${rkey}`
  );
}

function rkeyFromUri(uri: string): string {
  const rkey = uri.split("/").at(-1);
  if (!rkey) throw new Error(`Record URI has no rkey: ${uri}`);
  return rkey;
}

async function createPost(
  client: XrpcClient,
  did: string,
  accessJwt: string,
  text: string,
): Promise<string> {
  const created = await client.records.createRecord(did, "app.bsky.feed.post", {
    $type: "app.bsky.feed.post",
    text,
    createdAt: now(),
  }, accessJwt) as { uri: string };
  return rkeyFromUri(created.uri);
}

async function assertLiveOnlySubscription(
  relay: XrpcClient,
  client: XrpcClient,
  did: string,
  accessJwt: string,
  label: string,
): Promise<{ sentinelRkey: string; observed: RelayEvent[] }> {
  const connection = await connectAttachedRawWs(relay);
  const reader = new RawWsFrameReader(connection.conn, connection.initialBytes);
  try {
    const sentinelRkey = await createPost(
      client,
      did,
      accessJwt,
      `zuk-no-cursor-sentinel-${label}-${crypto.randomUUID()}`,
    );
    const read = await reader.readUntil(
      EVENT_DEADLINE_MS,
      (events) =>
        events.some((event) => eventContainsRkey(event, sentinelRkey)),
    );
    if (read.closed) {
      throw new Error(
        `Subscription closed before sentinel ${sentinelRkey} arrived`,
      );
    }
    if (!read.events.some((event) => eventContainsRkey(event, sentinelRkey))) {
      throw new Error(
        `Sentinel ${sentinelRkey} did not arrive before ${EVENT_DEADLINE_MS}ms`,
      );
    }
    const replayedEvent = eventAtOrBeforeAttachment(
      read.events,
      connection.attachmentSequence,
    );
    if (replayedEvent) {
      throw new Error(
        `No-cursor subscription received seq=${replayedEvent.seq} at or before ` +
          `confirmed attachment sequence=${connection.attachmentSequence}`,
      );
    }
    return { sentinelRkey, observed: read.events };
  } finally {
    await closeAttachedRawWs(relay, connection);
  }
}

/** Runs the Zuk omitted-cursor containment regression scenario. */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Zuk Cursor Containment");
  result.start();
  const pds = new XrpcClient(PDS1);
  const relay = new XrpcClient(SERVICE_URLS.relay);

  await timedCall(result, "PDS and relay health checks", async () => {
    await pds.waitForHealthy(30);
    await relay.raw.httpGet("/api/relay/health");
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const actor = getActor("volt");
  const session = await timedCall(
    result,
    "Create cursor containment account",
    () => createAccountOrLogin(pds, actor),
    (value) => `did=${value.did}`,
  );
  if (!session) {
    result.finish();
    return result;
  }
  actor.did = session.did;
  actor.accessJwt = session.accessJwt;

  const sequenceBeforeSeed = await timedCall(
    result,
    "Wait for relay account propagation to quiesce",
    () => waitForRelayQuiescence(relay),
    (sequence) => `current_sequence=${sequence}`,
  );
  if (sequenceBeforeSeed === null) {
    result.finish();
    return result;
  }

  const seedRkeys = new Set<string>();
  await timedCall(
    result,
    "Seed more events than relay replay window",
    async () => {
      for (let index = 0; index < SEED_COUNT; index++) {
        seedRkeys.add(
          await createPost(
            pds,
            actor.did!,
            actor.accessJwt!,
            `zuk-retained-seed-${index}-${crypto.randomUUID()}`,
          ),
        );
      }
      return seedRkeys.size;
    },
    (count) => `seeded=${count} replay_window=${REPLAY_WINDOW}`,
  );
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Wait for relay to ingest retained seed",
    () => waitForRelaySequence(relay, sequenceBeforeSeed + SEED_COUNT),
    (sequence) =>
      `current_sequence=${sequence} required=${
        sequenceBeforeSeed + SEED_COUNT
      }`,
  );
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Explicit cursor zero still reads the small replay window",
    async () => {
      const replayConnection = await connectAttachedRawWs(relay, 0);
      try {
        const replay = await new RawWsFrameReader(
          replayConnection.conn,
          replayConnection.initialBytes,
        ).readUntil(
          EVENT_DEADLINE_MS,
          (events) =>
            [...seedRkeys].some((rkey) =>
              events.some((event) => eventContainsRkey(event, rkey))
            ),
        );
        if (
          !replay.events.some((event) =>
            [...seedRkeys].some((rkey) => eventContainsRkey(event, rkey))
          )
        ) {
          throw new Error(
            "Explicit cursor zero did not return any seeded relay event",
          );
        }
        return replay.events.length;
      } finally {
        await closeAttachedRawWs(relay, replayConnection);
      }
    },
    (observed) => `replayed=${observed} configured_window=${REPLAY_WINDOW}`,
  );
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const first = await timedCall(
    result,
    "No-cursor subscription receives only its live sentinel",
    () =>
      assertLiveOnlySubscription(
        relay,
        pds,
        actor.did!,
        actor.accessJwt!,
        "initial",
      ),
    (value) =>
      `sentinel=${value.sentinelRkey} observed=${value.observed.length}`,
  );
  if (!first) {
    result.finish();
    return result;
  }

  const reconnects = await timedCall(
    result,
    "Twenty-five no-cursor reconnects remain live-only",
    async () => {
      const sentinels: string[] = [];
      for (let index = 1; index <= RECONNECT_COUNT; index++) {
        const observation = await assertLiveOnlySubscription(
          relay,
          pds,
          actor.did!,
          actor.accessJwt!,
          `reconnect-${index}`,
        );
        sentinels.push(observation.sentinelRkey);
      }
      return sentinels;
    },
    (sentinels) => `reconnects=${sentinels.length}`,
  );
  if (!reconnects) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Slow consumer is closed by bounded relay output",
    async () => {
      const slowConnection = await connectAttachedRawWs(relay);
      try {
        // Deliberately do not read while producing frames. Only after the writes
        // complete does the bounded reader poll for close/EOF with a deadline.
        for (let index = 0; index < SLOW_CONSUMER_POST_COUNT; index++) {
          await createPost(
            pds,
            actor.did!,
            actor.accessJwt!,
            slowConsumerPostText(index, crypto.randomUUID()),
          );
        }
        const read = await new RawWsFrameReader(
          slowConnection.conn,
          slowConnection.initialBytes,
        ).readUntil(
          SLOW_CONSUMER_DEADLINE_MS,
          () => false,
        );
        if (!read.closed) {
          throw new Error(
            `Slow subscriber remained open after ${SLOW_CONSUMER_DEADLINE_MS}ms ` +
              "with PDS_FIREHOSE_MAX_PENDING_SENDS=4 and PDS_FIREHOSE_MAX_PENDING_BYTES=10000",
          );
        }
        return read.events.length;
      } finally {
        await closeAttachedRawWs(relay, slowConnection);
      }
    },
    (observed) => `closed=true events_observed_after_poll=${observed}`,
  );

  await timedCall(
    result,
    "Relay remains healthy after bounded consumers",
    async () => {
      await relay.raw.httpGet("/api/relay/health");
    },
  );

  result.recordArtifact("zuk_cursor_containment", {
    replay_window: REPLAY_WINDOW,
    seeded_events: seedRkeys.size,
    reconnects: reconnects.length,
    slow_consumer_post_count: SLOW_CONSUMER_POST_COUNT,
    queue_overflow_metric:
      "not exposed by the current relay HTTP API; closure is asserted instead",
  });
  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  result.printSummary();
  Deno.exit(result.ok ? 0 : 1);
}
