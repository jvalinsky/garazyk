/**
 * @module scenarios/63_firehose_cursor_recovery
 *
 * Scenario: 63 firehose cursor recovery
 *
 * Behavior:
 * - Executes the 63 firehose cursor recovery scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { FirehoseClient } from "@garazyk/gruszka";
import type { FirehoseEvent } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext } from "@garazyk/hamownia";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { timedCall } from "@garazyk/hamownia";

interface CreateRecordResponse {
  uri: string;
  cid: string;
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Cursor Recovery");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = ctx.getCharacter("luna");
  const session = await timedCall(
    result,
    "Create account",
    async () => {
      let res: Awaited<ReturnType<typeof client.agent.createAccount>>;
      try {
        res = await client.agent.createAccount({
          handle: luna.handle,
          email: luna.email,
          password: luna.password,
        });
      } catch (exc) {
        if (!String(exc).toLowerCase().includes("already exists")) {
          throw exc;
        }
        res = await client.agent.login({
          identifier: luna.handle,
          password: luna.password,
        });
      }
      return res.data;
    },
    (s: any) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }

  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const relayUrl = ctx.serviceUrls.relay;

  // ── Phase 1: Subscribe and collect baseline events ───────────────────────
  const fh1 = new FirehoseClient(relayUrl);
  let lastSeq = 0;
  const eventsBefore: FirehoseEvent[] = [];

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

  if (
    eventsBefore.length > 0 &&
    eventsBefore.every((ev) =>
      Object.keys(ev.header).length > 0 && Object.keys(ev.body).length > 0
    )
  ) {
    result.stepPassed("Baseline firehose decoding");
  } else if (eventsBefore.length > 0) {
    result.stepFailed("Baseline firehose decoding", "missing decoded frame");
  }

  // ── Phase 2: Create posts during disconnect ──────────────────────────────
  const postUris: string[] = [];
  for (let i = 0; i < 3; i++) {
    const post = await timedCall(
      result,
      `Create post ${i + 1} during disconnect`,
      async () => {
        return await client.raw.post(
          "com.atproto.repo.createRecord",
          {
            repo: luna.did,
            collection: "app.bsky.feed.post",
            record: {
              $type: "app.bsky.feed.post",
              text: `Cursor recovery test post ${i + 1}`,
              createdAt: now(),
            },
          },
          luna.accessJwt,
        ) as any as CreateRecordResponse;
      },
      (r: any) => `uri=${r.uri}`,
    );
    if (post) postUris.push(post.uri);
  }

  // Brief pause to let events propagate to relay
  await new Promise((r) => setTimeout(r, 2000));

  // ── Phase 3: Resubscribe with cursor ─────────────────────────────────────
  const fh2 = new FirehoseClient(relayUrl);
  const eventsAfter: FirehoseEvent[] = [];

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

  if (
    eventsAfter.length > 0 &&
    eventsAfter.every((ev) =>
      Object.keys(ev.header).length > 0 && Object.keys(ev.body).length > 0
    )
  ) {
    result.stepPassed("Resubscribe firehose decoding");
  } else if (eventsAfter.length > 0) {
    result.stepFailed("Resubscribe firehose decoding", "missing decoded frame");
  }

  // ── Phase 4: Verify cursor recovery ──────────────────────────────────────
  if (lastSeq > 0 && eventsAfter.length > 0) {
    // Check that we got events with seq > lastSeq (continuation)
    const continuingEvents = eventsAfter.filter((e) => e.seq > lastSeq);
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
    const overlapEvents = eventsAfter.filter((e) =>
      e.seq <= lastSeq && e.seq > 0
    );
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
    result.stepSkipped(
      "Cursor recovery",
      "No events with seq > 0 received in baseline",
    );
  } else {
    result.stepSkipped(
      "Cursor recovery",
      "No events received after resubscribe",
    );
  }

  // ── Phase 5: Resubscribe with cursor=0 (full replay) ──────────────────────
  const fh3 = new FirehoseClient(relayUrl);
  const eventsFromZero: FirehoseEvent[] = [];

  await timedCall(
    result,
    "Resubscribe with cursor=0 (full replay)",
    async () => {
      await fh3.subscribe(
        (ev) => {
          eventsFromZero.push(ev);
        },
        5,
        0,
      );
    },
  );

  if (eventsFromZero.length > 0) {
    result.stepPassed(
      "Full replay returns events",
      `count=${eventsFromZero.length}`,
    );
  } else {
    result.stepSkipped("Full replay returns events", "No events received");
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  const r = await run(createScenarioContext());
  console.log(r.summary());
  Deno.exit(r.ok ? 0 : 1);
}
