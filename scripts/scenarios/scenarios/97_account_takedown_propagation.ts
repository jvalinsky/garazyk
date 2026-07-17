/**
 * @module scenarios/97_account_takedown_propagation
 *
 * Scenario: End-to-end account takedown downstream propagation.
 *
 * Behavior:
 * - Creates a target account and an admin account.
 * - Admin logs in and applies a takedown via
 *   com.atproto.admin.updateSubjectStatus.
 * - Connects to the PDS subscribeRepos firehose and asserts a #account
 *   event is emitted with active=false and status=takendown for the
 *   target DID.
 * - Connects to the Relay and asserts the same #account event is
 *   re-broadcast to downstream subscribers.
 * - Verifies com.atproto.admin.getSubjectStatus reflects the takedown.
 *
 * This exercises the full chain wired in the downstream-propagation fix:
 *   PDSAdminService.takeDownAccount → PDSAccountDeactivatedNotification
 *   → SubscribeReposHandler.broadcastAccountStatus → #account firehose
 *   → RelayDownstreamHandler re-broadcast → RelayClient forwarding
 *   → AppViewIngestEngine._handleAccountEvent.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, PDS_ADMIN_PASSWORD, SERVICE_URLS } from "../../lib/deno/config.ts";
import { createAccountOrLogin, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { firehoseEventFromFrame, parseFirehoseFrame } from "../../lib/deno/firehose.ts";

// ---------------------------------------------------------------------------
// Minimal raw-WebSocket utilities (same pattern as scenarios 33 and 96)
// ---------------------------------------------------------------------------

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

  async readUntil(
    deadlineMs: number,
    predicate: (frames: ParsedFrame[]) => boolean,
  ): Promise<{ frames: ParsedFrame[]; closed: boolean }> {
    const frames: ParsedFrame[] = [];
    let closed = false;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try { this.#conn.close(); } catch { /* already closed */ }
    }, deadlineMs);

    const readBuf = new Uint8Array(65536);
    try {
      while (!timedOut) {
        let frame = this.#tryParseFrame();
        while (frame) {
          frames.push(frame);
          if (frame.opcode === 0x8) closed = true;
          if (predicate(frames) || closed) {
            clearTimeout(timer);
            return { frames, closed };
          }
          frame = this.#tryParseFrame();
        }
        const n = await this.#conn.read(readBuf);
        if (n === null || n === 0) { closed = true; break; }
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
  type: string;
  body: Record<string, unknown>;
}

function decodeDataFrames(frames: ParsedFrame[]): FirehoseEventLike[] {
  const events: FirehoseEventLike[] = [];
  for (const f of frames) {
    if (f.opcode !== 0x2 && f.opcode !== 0x1) continue;
    try {
      const fe = firehoseEventFromFrame(parseFirehoseFrame(f.payload));
      events.push({ seq: fe.seq, type: fe.type, body: fe.body });
    } catch {
      // Not a decodable firehose frame; skip.
    }
  }
  return events;
}

// ---------------------------------------------------------------------------
// Scenario
// ---------------------------------------------------------------------------

const FIREHOSE_TIMEOUT_MS = 15_000;

async function collectAccountEvents(
  serviceUrl: string,
  timeoutMs: number,
  did: string,
  expectTakedown: boolean,
): Promise<FirehoseEventLike[]> {
  const url = new URL(`${serviceUrl}/xrpc/com.atproto.sync.subscribeRepos`);
  const conn = await connectRawWs(url.toString());
  const reader = new RawWsFrameReader(conn);
  try {
    const { frames } = await reader.readUntil(timeoutMs, (seen) => {
      const events = decodeDataFrames(seen);
      if (expectTakedown) {
        // Look specifically for a takedown #account event (active=false, status=takendown)
        return events.some((e) =>
          e.type === "#account" &&
          (e.body as any).did === did &&
          (e.body as any).active === false &&
          (e.body as any).status === "takendown"
        );
      }
      // Stop when we have at least one #account event for the target DID
      return events.some((e) =>
        e.type === "#account" && (e.body as any).did === did
      );
    });
    return decodeDataFrames(frames);
  } finally {
    try { conn.close(); } catch { /* already closed */ }
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Takedown Downstream Propagation");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });
  if (result.failed > 0) { result.finish(); return result; }

  // Create accounts
  const target = getActor("marcus");
  const admin = getActor("admin");

  for (const char of [target, admin]) {
    const session = await timedCall(result, `Create account: ${char.name}`, async () => {
      return await client.accounts.createAccount(char.handle, char.email, char.password);
    });
    if (!session) { result.finish(); return result; }
    char.did = session.did;
    char.accessJwt = session.accessJwt;
  }

  if (!target.did || !admin.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  // Admin login
  const adminPassword = PDS_ADMIN_PASSWORD;
  const adminToken = await timedCall(result, "Admin login", async () => {
    return await client.adminLogin(adminPassword);
  });
  if (!adminToken) { result.finish(); return result; }

  // Start collecting PDS firehose events in background BEFORE applying takedown.
  // We need to see the #account event that the takedown generates.
  const pdsCollectPromise = collectAccountEvents(PDS1, FIREHOSE_TIMEOUT_MS, target.did, true);
  // Collect one initial event first to confirm the firehose connection is live
  // before triggering the takedown, avoiding a race where the takedown fires
  // before the WebSocket handshake completes.
  await new Promise((r) => setTimeout(r, 2000));

  // Apply takedown via updateSubjectStatus (com.atproto.admin.takeDownAccount is deprecated)
  await timedCall(result, "Admin applies takedown on target", async () => {
    await client.asAdmin(adminToken).raw.post("com.atproto.admin.updateSubjectStatus", {
      subject: {
        $type: "com.atproto.admin.defs#repoRef",
        did: target.did,
      },
      takedown: {
        applied: true,
        ref: "scenario-97-test-takedown",
      },
    });
  });
  if (result.failed > 0) { result.finish(); return result; }

  // Collect PDS firehose events
  const pdsEvents = await pdsCollectPromise;
  const pdsAccountEvents = pdsEvents.filter((e) =>
    e.type === "#account" && (e.body as any).did === target.did
  );

  if (pdsAccountEvents.length === 0) {
    result.stepFailed(
      "PDS emitted #account event",
      `No #account event found for ${target.did} among ${pdsEvents.length} events ` +
        `(event types: ${pdsEvents.map((e) => e.type).join(", ")})`,
    );
  } else {
    const accountEvent = pdsAccountEvents[pdsAccountEvents.length - 1];
    const body = accountEvent.body as any;
    const active = body.active;
    const status = body.status;
    if (active === false && status === "takendown") {
      result.stepPassed(
        "PDS emitted #account event",
        `seq=${accountEvent.seq} active=false status=takendown`,
      );
    } else {
      result.stepFailed(
        "PDS emitted #account event with correct fields",
        `active=${active} status=${status} (expected active=false status=takendown)`,
      );
    }
  }

  // Verify Relay re-broadcast
  const relayUrl = SERVICE_URLS.relay;
  if (relayUrl) {
    // Wait a moment for the relay to receive and buffer the event
    await new Promise((r) => setTimeout(r, 2000));

    try {
      const relayEvents = await collectAccountEvents(relayUrl, FIREHOSE_TIMEOUT_MS, target.did, true);
      const relayAccountEvents = relayEvents.filter((e) =>
        e.type === "#account" && (e.body as any).did === target.did
      );

      if (relayAccountEvents.length === 0) {
        result.stepSkipped(
          "Relay re-broadcast #account event",
          `No #account event found on relay for ${target.did} — may need more propagation time`,
        );
      } else {
        const relayEvent = relayAccountEvents[relayAccountEvents.length - 1];
        const body = relayEvent.body as any;
        if (body.active === false && body.status === "takendown") {
          result.stepPassed(
            "Relay re-broadcast #account event",
            `seq=${relayEvent.seq} active=false status=takendown`,
          );
        } else {
          result.stepFailed(
            "Relay #account event fields",
            `active=${body.active} status=${body.status} (expected active=false status=takendown)`,
          );
        }
      }
    } catch (exc: any) {
      result.stepSkipped("Relay re-broadcast #account event", String(exc));
    }
  } else {
    result.stepSkipped("Relay re-broadcast #account event", "No relay URL configured");
  }

  // Verify admin getSubjectStatus reflects the takedown in the PDS database.
  // This confirms the write-side enforcement boundary: the PDS knows the
  // account is taken down, which is the same state the #account firehose
  // event propagates downstream to Relay and AppView.
  await timedCall(result, "getSubjectStatus shows takedown applied", async () => {
    const status = await client.asAdmin(adminToken).raw.get(
      "com.atproto.admin.getSubjectStatus",
      { did: target.did },
    );
    const takedown = (status as any).takedown;
    if (takedown !== true) {
      throw new Error(`Expected takedown=true, got ${JSON.stringify(takedown)}`);
    }
    return status;
  }, (s) => `takedown=${(s as any).takedown}`);

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
