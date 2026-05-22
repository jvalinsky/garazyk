/**
 * @module scenarios/65_firehose_fuzzing
 *
 * Scenario: Adversarial firehose frame fuzzing with gap, regression, and time-travel frames.
 *
 * Behavior:
 * - Feeds crafted DAG-CBOR frames through FirehoseClient.handleMessage() with adversarial seq and time values.
 * - Validates no crash under gap sequences, correct high-water mark under regression, and no crash under time-travel.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { encode } from "cborg";
import { FirehoseClient } from "../../lib/deno/firehose.ts";
import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";

function now(): string {
  return new Date().toISOString();
}

function craftFrame(seq: number, time?: string): Uint8Array {
  const headerBytes = encode({ op: 1, t: "#commit" });
  const bodyBytes = encode({
    seq,
    time: time ?? now(),
    repo: "did:plc:test",
    commit: {},
  });
  return new Uint8Array([...headerBytes, ...bodyBytes]);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Fuzzing");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const troll = getCharacter("troll");
  const session = await timedCall(result, "Create troll account", async () => {
    try {
      return await client.accounts.createAccount(troll.handle, troll.email, troll.password);
    } catch (e: any) {
      if (e.message?.includes("already exists")) {
        return await client.accounts.createSession(troll.handle, troll.password);
      }
      throw e;
    }
  });

  if (!session) {
    result.finish();
    return result;
  }

  troll.did = session.did;
  troll.accessJwt = session.accessJwt;

  const fh = new FirehoseClient();
  const events: any[] = [];
  const cb = (e: any) => { events.push(e); };

  // ── Phase A: Gap fuzzing ──────────────────────────────────────────────────
  await timedCall(result, "Phase A: Gap frames (seq=100, seq=1e12)", async () => {
    const frame1 = craftFrame(100);
    const frame2 = craftFrame(1_000_000_000_000);

    fh.handleMessage(frame1, cb);
    fh.handleMessage(frame2, cb);

    assert.isTrue(events.length >= 2, `Expected at least 2 events, got ${events.length}`);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── Phase B: Sequence regression ──────────────────────────────────────────
  await timedCall(result, "Phase B: Sequence regression (seq=105, seq=102)", async () => {
    const frameHigh = craftFrame(105);
    const frameLow = craftFrame(102);

    fh.handleMessage(frameHigh, cb);
    fh.handleMessage(frameLow, cb);

    assert.isTrue(fh.lastSeq === 105, `High-water mark regression: expected lastSeq=105, got ${fh.lastSeq}`);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── Phase C: Time-travel frame ────────────────────────────────────────────
  await timedCall(result, "Phase C: Time-travel frame (year 2099)", async () => {
    const frame = craftFrame(200, "2099-12-31T23:59:59.000Z");

    fh.handleMessage(frame, cb);

    assert.isTrue(events.length >= 4, `Expected at least 4 events, got ${events.length}`);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── Verify event tracking consistency ─────────────────────────────────────
  await timedCall(result, "Verify event tracking consistency", async () => {
    assert.isTrue(events.length > 0, "Expected events to be collected");
    const seqs = events.map((e: any) => e.seq);
    assert.isTrue(seqs.length >= 4, `Expected at least 4 events, got ${seqs.length}`);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── Final PDS health check ────────────────────────────────────────────────
  await timedCall(result, "Final PDS health check", async () => {
    await client.waitForHealthy(10);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
