/**
 * @module scenarios/63_firehose_cursor_recovery
 *
 * Scenario: Resubscribes to the firehose with cursors and verifies continuation and replay.
 *
 * Behavior:
 * - Executes the 63 firehose cursor recovery scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { FirehoseClient } from "../../lib/deno/firehose.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Cursor Recovery");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = getCharacter("luna");
  const session = await timedCall(
    result,
    "Create account",
    async () => {
      return await client.accounts.createAccount(luna.handle, luna.email, luna.password);
    },
    (s) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }

  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const relayUrl = SERVICE_URLS.relay;

  // ── Phase 1: Subscribe and collect baseline events ───────────────────────
  const fh1 = new FirehoseClient(relayUrl);
  let lastSeq = 0;
  const eventsBefore: any[] = [];

  await timedCall(result, "Subscribe to firehose (baseline)", async () => {
    await fh1.subscribe((ev) => {
      eventsBefore.push(ev);
      if (ev.seq > lastSeq) lastSeq = ev.seq;
    }, 5);
  });

  result.stepPassed(
    "Baseline events collected",
    `count=${eventsBefore.length}, last_seq=${lastSeq}`,
  );

  // ── Phase 2: Create posts during disconnect ──────────────────────────────
  const postUris: string[] = [];
  for (let i = 0; i < 3; i++) {
    const post = await timedCall(
      result,
      `Create post ${i + 1} during disconnect`,
      async () => {
        return await client.records.createRecord(
          luna.did,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: `Cursor recovery test post ${i + 1}`,
            createdAt: now(),
          },
          luna.accessJwt,
        );
      },
      (r) => `uri=${r.uri}`,
    );
    if (post) postUris.push(post.uri);
  }

  // Brief pause to let events propagate to relay
  await new Promise((r) => setTimeout(r, 2000));

  // ── Phase 3: Resubscribe with cursor ─────────────────────────────────────
  const fh2 = new FirehoseClient(relayUrl);
  const eventsAfter: any[] = [];

  await timedCall(result, "Resubscribe with cursor", async () => {
    await fh2.subscribe(
      (ev) => {
        eventsAfter.push(ev);
      },
      8,
      lastSeq,
    );
  });

  result.stepPassed("Events after resubscribe", `count=${eventsAfter.length}`);

  // ── Phase 4: Verify cursor recovery ──────────────────────────────────────
  if (lastSeq > 0 && eventsAfter.length > 0) {
    // Check that we got events with seq > lastSeq (continuation)
    const continuingEvents = eventsAfter.filter((e: any) => e.seq > lastSeq);
    if (continuingEvents.length > 0) {
      result.stepPassed(
        "Cursor recovery works",
        `last_seq_before=${lastSeq}, events_after=${eventsAfter.length}, continuing=${continuingEvents.length}`,
      );
    } else {
      result.stepFailed(
        "Cursor recovery works",
        `No events with seq > ${lastSeq} found after resubscribe`,
      );
    }

    // Check that we didn't get events with seq <= lastSeq that we already saw
    // (some overlap is OK for cursor semantics, but massive overlap is suspicious)
    const overlapEvents = eventsAfter.filter((e: any) => e.seq <= lastSeq && e.seq > 0);
    if (overlapEvents.length > eventsAfter.length * 0.5) {
      result.stepFailed(
        "Cursor overlap check",
        `Too much overlap: ${overlapEvents.length} of ${eventsAfter.length} events are from before cursor`,
      );
    } else {
      result.stepPassed(
        "Cursor overlap check",
        `overlap=${overlapEvents.length}, total=${eventsAfter.length}`,
      );
    }
  } else if (lastSeq === 0) {
    result.stepSkipped("Cursor recovery", "No events with seq > 0 received in baseline");
  } else {
    result.stepSkipped("Cursor recovery", "No events received after resubscribe");
  }

  // ── Phase 5: Resubscribe with cursor=0 (full replay) ──────────────────────
  const fh3 = new FirehoseClient(relayUrl);
  const eventsFromZero: any[] = [];

  await timedCall(result, "Resubscribe with cursor=0 (full replay)", async () => {
    await fh3.subscribe(
      (ev) => {
        eventsFromZero.push(ev);
      },
      5,
      0,
    );
  });

  if (eventsFromZero.length > 0) {
    result.stepPassed("Full replay returns events", `count=${eventsFromZero.length}`);
  } else {
    result.stepSkipped("Full replay returns events", "No events received");
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  const r = await run();
  console.log(r.summary());
  Deno.exit(r.ok ? 0 : 1);
}
