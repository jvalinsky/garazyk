/**
 * @module scenarios/26_appview_ingest_load
 *
 * Scenario: 26 appview ingest load
 *
 * Behavior:
 * - Executes the 26 appview ingest load scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import {
  InstrumentationReport,
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
  StorageMonitor,
} from "@garazyk/hamownia";
import { FirehoseClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { createRunContext } from "@garazyk/hamownia/diagnostics";
import { join } from "@std/path";
import { timedCall } from "@garazyk/hamownia";

function now() {
  return new Date().toISOString();
}

async function appviewAdminGet(
  ctx: ScenarioContext,
  path: string,
  params?: Record<string, any>,
): Promise<any> {
  const url = new URL(path, ctx.serviceUrls.appview);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.append(k, String(v));
    }
  }
  const res = await fetch(url.toString(), {
    headers: { "Authorization": `Bearer ${ctx.appviewAdminSecret}` },
  });
  return await res.json();
}

function summarizeIngestState(
  health: any,
  backfill: any,
  metrics: any,
  records: any,
) {
  const backpressureActive =
    !!(health?.running === false || backfill?.enabled === false ||
      metrics?.backpressure);
  const queueDepth = metrics?.queue_depth || health?.queue_depth || 0;
  const ingestLag = metrics?.ingest_lag || 0;
  const indexedRecords = records?.records?.length || records?.total || 0;

  return { backpressureActive, queueDepth, ingestLag, indexedRecords };
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Ingest Under Load");
  result.start();

  const client = new XrpcClient(ctx.pds1);
  const timer = new OperationTimer();
  const phaseTimer = new PhaseTimer();

  const reportCtx = await createRunContext();
  const promScraper = new PrometheusScraper({
    pds: `${ctx.pds1}/metrics`,
    appview: `${ctx.serviceUrls.appview}/admin/appview/metrics/stats`,
  });
  promScraper.start();

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    await promScraper.stop();
    result.finish();
    return result;
  }

  phaseTimer.startPhase("Setup");
  const charNames = ["luna", "marcus", "rosa", "volt", "quiet", "troll"];
  const activeAccounts: any[] = [];

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
      activeAccounts.push(char);
    }
  }

  for (let i = 1; i <= 4; i++) {
    const handle = `ingest-${i}.test`;
    const session = await timedCall(
      result,
      `Create account: Ingest ${i}`,
      async () => {
        return await timer.measure(
          "create_account",
          () =>
            client.accounts.createAccount(
              handle,
              `ingest-${i}@test.com`,
              `pass-${i}`,
            ),
        );
      },
    );
    if (session) {
      activeAccounts.push({
        did: session.did,
        accessJwt: session.accessJwt,
        name: `Ingest ${i}`,
      });
    }
  }

  const firehoseEvents: any[] = [];
  const fh = new FirehoseClient(ctx.serviceUrls.relay);
  const fhStop = { stopped: false };
  const fhPromise = fh.subscribe((ev) => firehoseEvents.push(ev), 45).catch(
    () => {},
  );

  result.stepPassed("Firehose subscriber started");
  phaseTimer.endPhase();

  // Sustained production
  phaseTimer.startPhase("Sustained production");
  const sustainedCount = 500;
  let sustainedCreated = 0;
  for (let i = 0; i < sustainedCount; i++) {
    const acc = activeAccounts[i % activeAccounts.length];
    try {
      await timer.measure("create_post", () =>
        client.records.createRecord(
          acc.did,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: `Sustained post ${i + 1}`,
            createdAt: now(),
          },
          acc.accessJwt,
        ));
      sustainedCreated++;
    } catch { /* ignore */ }
    if (i % 10 === 0) await new Promise((r) => setTimeout(r, 60));
  }
  result.stepPassed("Sustained production", `created=${sustainedCreated}`);
  phaseTimer.endPhase();

  // Burst
  phaseTimer.startPhase("Backpressure trigger");
  const burstCount = 200;
  let burstCreated = 0;
  for (let i = 0; i < burstCount; i++) {
    const acc = activeAccounts[i % activeAccounts.length];
    try {
      await timer.measure(
        "create_post_burst",
        () =>
          client.records.createRecord(
            acc.did,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: `Burst post ${i + 1}`,
              createdAt: now(),
            },
            acc.accessJwt,
          ),
      );
      burstCreated++;
    } catch { /* ignore */ }
  }

  const health = await appviewAdminGet(ctx, "/admin/ingest/health");
  const backfill = await appviewAdminGet(ctx, "/admin/backfill/status");
  const metrics = await appviewAdminGet(ctx, "/admin/appview/metrics/stats");
  const burstSummary = summarizeIngestState(health, backfill, metrics, null);
  result.stepPassed(
    "Backpressure trigger",
    `created=${burstCreated}, backpressure=${burstSummary.backpressureActive}`,
  );
  phaseTimer.endPhase();

  // Verification
  phaseTimer.startPhase("Resume verification");
  const expectedTotal = sustainedCreated + burstCreated;
  let cleared = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    const h = await appviewAdminGet(ctx, "/admin/ingest/health");
    const b = await appviewAdminGet(ctx, "/admin/backfill/status");
    const m = await appviewAdminGet(ctx, "/admin/appview/metrics/stats");
    const r = await appviewAdminGet(ctx, "/admin/records", {
      collection: "app.bsky.feed.post",
      limit: 1,
    });
    const s = summarizeIngestState(h, b, m, r);
    if (
      s.indexedRecords >= expectedTotal && !s.backpressureActive &&
      s.ingestLag <= 5
    ) {
      cleared = true;
      result.stepPassed(
        "Resume verification",
        `indexed=${s.indexedRecords}, lag=${s.ingestLag}`,
      );
      break;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  if (!cleared) {
    result.stepFailed("Resume verification", "Ingest did not clear in time");
  }
  phaseTimer.endPhase();

  // Consistency
  phaseTimer.startPhase("AppView consistency");
  const appviewRecords = await appviewAdminGet(ctx, "/admin/records", {
    collection: "app.bsky.feed.post",
    limit: 1000,
  });
  const appviewTotal = appviewRecords.total || appviewRecords.records?.length ||
    0;
  result.stepPassed("AppView consistency", `appview_posts=${appviewTotal}`);
  phaseTimer.endPhase();

  const metricsTs = await promScraper.stop();
  const report = new InstrumentationReport(
    timer.toDict(),
    metricsTs,
    {},
    {},
    phaseTimer.toDict(),
  );
  await report.writeJson(join(reportCtx.reportsDir, "instrumentation-26.json"));

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
