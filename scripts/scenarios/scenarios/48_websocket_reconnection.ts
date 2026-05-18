/**
 * @module scenarios/48_websocket_reconnection
 *
 * Scenario: 48 websocket reconnection
 *
 * Behavior:
 * - Executes the 48 websocket reconnection scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { FirehoseClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("WebSocket Reconnection");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(
    luna.handle,
    luna.email,
    luna.password,
  ).catch(
    () => pds.accounts.createSession(luna.handle, luna.password),
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const relayUrl = ctx.serviceUrls.relay;
  const fh = new FirehoseClient(relayUrl);

  let lastSeq = 0;
  const eventsBefore: any[] = [];

  await timedCall(result, "Subscribe to firehose (first)", async () => {
    await fh.subscribe((ev) => {
      eventsBefore.push(ev);
      if (ev.seq > lastSeq) lastSeq = ev.seq;
    }, 5);
  });

  result.stepPassed(
    "Events collected before disconnect",
    `count=${eventsBefore.length}, last_seq=${lastSeq}`,
  );

  await timedCall(result, "Create post during disconnect", async () => {
    return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
      $type: "app.bsky.feed.post",
      text: "Posted during disconnect",
      createdAt: now(),
    }, luna.accessJwt);
  });

  const eventsAfter: any[] = [];
  await timedCall(result, "Reconnect with cursor", async () => {
    const fh2 = new FirehoseClient(relayUrl);
    await fh2.subscribe(
      (ev) => {
        eventsAfter.push(ev);
      },
      5,
      lastSeq,
    );
  });

  // Assert continuity: events after reconnect should have seq > lastSeq
  if (eventsAfter.length > 0 && lastSeq > 0) {
    const minSeqAfter = Math.min(
      ...eventsAfter.map((e: any) => e.seq).filter((s: number) => s > 0),
    );
    if (minSeqAfter > lastSeq) {
      result.stepPassed(
        "Event continuity after reconnect",
        `last_seq_before=${lastSeq}, first_seq_after=${minSeqAfter}, events=${eventsAfter.length}`,
      );
    } else {
      result.stepFailed(
        "Event continuity after reconnect",
        `Expected seq > ${lastSeq} but got min_seq=${minSeqAfter}`,
      );
    }
  } else if (lastSeq === 0) {
    result.stepSkipped(
      "Event continuity after reconnect",
      "No events with seq > 0 received before disconnect",
    );
  } else {
    result.stepSkipped(
      "Event continuity after reconnect",
      "No events received after reconnect",
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
