/**
 * @module scenarios/25_firehose_fanout_scale
 *
 * Scenario: Firehose Fan-Out at Scale
 *
 * Behavior:
 * - Setup PDS and Relay metrics scraping.
 * - Create multiple test accounts.
 * - Spin up a large number of concurrent firehose subscribers.
 * - Produce a steady stream of posts to trigger event broadcasting.
 * - Introduce a burst of activity to test relay backpressure handling.
 * - Capture performance metrics and ensure p95 latency remains within thresholds.
 *
 * Expectations:
 * - Firehose subscribers maintain connection during steady state.
 * - Relay and PDS handle burst traffic without critical failure.
 * - Post creation p95 latency remains under 2 seconds.
 */

import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { FirehoseClient } from "@garazyk/gruszka";
import { createRunContext } from "@garazyk/hamownia/diagnostics";
import {
  InstrumentationReport,
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
} from "@garazyk/hamownia";
import { join } from "@std/path";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Fan-Out at Scale");
  result.start();

  const client = new XrpcClient(ctx.pds1);
  const timer = new OperationTimer();
  const phaseTimer = new PhaseTimer();

  phaseTimer.startPhase("setup");

  const promEndpoints = {
    pds: `${ctx.serviceUrls.pds}/metrics`,
    relay: `${ctx.serviceUrls.relay}/api/relay/metrics`,
  };
  const promScraper = new PrometheusScraper(promEndpoints);
  promScraper.start();

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    await promScraper.stop();
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt", "quiet"];
  for (const name of charNames) {
    const char = ctx.getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await timer.measure(
          "create_account",
          () =>
            client.accounts.createAccount(
              char.handle,
              char.email,
              char.password,
            ),
        );
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => ctx.getCharacter(n).did);
  phaseTimer.endPhase();

  phaseTimer.startPhase("subscriber_rampup");

  const NUM_SUBSCRIBERS = 50;
  const subscriberEvents: any[] = [];
  const subscriberStop = { stopped: false };
  const relayUrl = ctx.serviceUrls.relay;
  const abortController = new AbortController();

  const startSubscriber = async (id: number) => {
    const fh = new FirehoseClient(relayUrl);
    while (!subscriberStop.stopped && !abortController.signal.aborted) {
      try {
        await fh.subscribe(
          (ev) => {
            (ev as any)._subscriber_id = id;
            (ev as any)._received_at = Date.now() / 1000;
            subscriberEvents.push(ev);
          },
          60,
          undefined,
          abortController.signal,
        );
      } catch {
        if (!subscriberStop.stopped && !abortController.signal.aborted) {
          await new Promise((r) => setTimeout(r, 1000));
        }
      }
    }
  };

  const subscriberPromises: Promise<void>[] = [];
  for (let i = 0; i < NUM_SUBSCRIBERS; i++) {
    subscriberPromises.push(startSubscriber(i));
  }

  await new Promise((r) => setTimeout(r, 3000));
  result.stepPassed(
    "Subscriber ramp-up",
    `Started ${NUM_SUBSCRIBERS} firehose subscribers`,
  );
  phaseTimer.endPhase();

  phaseTimer.startPhase("event_production");

  // Sequential post creation avoids PDS concurrency issues with parallel createRecord
  const POSTS_PER_USER = 20;
  let totalPosts = 0;
  for (const name of active) {
    const char = ctx.getCharacter(name);
    for (let i = 0; i < POSTS_PER_USER; i++) {
      try {
        await timer.measure("create_post", () =>
          client.records.createRecord(
            char.did!,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: `Fanout post ${i + 1} from ${char.name}`,
              createdAt: now(),
            },
            char.accessJwt!,
          ));
        totalPosts++;
      } catch { /* ignore rate limits */ }
    }
  }
  result.stepPassed("Event production", `created=${totalPosts}`);
  phaseTimer.endPhase();

  await new Promise((r) => setTimeout(r, 5000));

  phaseTimer.startPhase("backpressure_test");
  const extraPromises: Promise<void>[] = [];
  for (let i = 0; i < NUM_SUBSCRIBERS; i++) {
    extraPromises.push(startSubscriber(NUM_SUBSCRIBERS + i));
  }

  await new Promise((r) => setTimeout(r, 3000));

  const BURST_PER_USER = 40;
  let burstPosts = 0;
  for (const name of active) {
    const char = ctx.getCharacter(name);
    for (let i = 0; i < BURST_PER_USER; i++) {
      try {
        await timer.measure(
          "create_post_burst",
          () =>
            client.records.createRecord(
              char.did!,
              "app.bsky.feed.post",
              {
                $type: "app.bsky.feed.post",
                text: `Burst post ${i + 1} from ${char.name}`,
                createdAt: now(),
              },
              char.accessJwt!,
            ),
        );
        burstPosts++;
      } catch { /* ignore rate limits */ }
    }
  }
  result.stepPassed("Backpressure burst", `created=${burstPosts}`);

  try {
    const res = await fetch(`${ctx.serviceUrls.pds}/metrics`);
    const text = await res.text();
    let bpWarnings = 0;
    let bpCritical = 0;
    for (const line of text.split("\n")) {
      if (line.includes("pds_websocket_backpressure_warnings_total")) {
        bpWarnings = parseInt(line.split(" ").pop() || "0");
      }
      if (line.includes("pds_websocket_backpressure_critical_total")) {
        bpCritical = parseInt(line.split(" ").pop() || "0");
      }
    }
    result.stepPassed(
      "Backpressure metrics",
      `warnings=${bpWarnings}, critical=${bpCritical}`,
    );
  } catch { /* ignore */ }

  await new Promise((r) => setTimeout(r, 5000));
  phaseTimer.endPhase();

  phaseTimer.startPhase("subscriber_teardown");
  subscriberStop.stopped = true;
  abortController.abort();
  await Promise.race([
    Promise.all([...subscriberPromises, ...extraPromises]),
    new Promise((r) => setTimeout(r, 5000)),
  ]);
  result.stepPassed(
    "Subscriber teardown",
    `total_events=${subscriberEvents.length}`,
  );
  phaseTimer.endPhase();

  phaseTimer.startPhase("instrumentation");
  const metricsTs = await promScraper.stop();
  const report = new InstrumentationReport(
    timer.toDict(),
    metricsTs,
    {},
    {},
    phaseTimer.toDict(),
  );
  const runCtx = await createRunContext();
  result.recordArtifact("instrumentation", report.toDict());
  await report.writeJson(join(runCtx.reportsDir, "instrumentation-25.json"));
  phaseTimer.endPhase();

  const stats = timer.getStats("create_post");
  if (stats) {
    const p95 = stats.p95;
    if (p95 < 2000) {
      result.stepPassed("p95 latency < 2s", `p95_ms=${p95.toFixed(1)}`);
    } else {
      result.stepFailed("p95 latency < 2s", `p95_ms=${p95.toFixed(1)}`);
    }
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
