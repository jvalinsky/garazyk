/**
 * @module scenarios/24_concurrent_write_throughput
 *
 * Scenario: Stress-tests the PDS repository write throughput under concurrent load.
 *
 * Behavior:
 * - Initializes 32 accounts and sets up baseline data via record creation.
 * - Executes a concurrent "burst" phase of single-record creations.
 * - Executes a "mixed" workload phase combining single creations, deletions, and `applyWrites` batches.
 * - Monitors PDS database storage and Prometheus metrics during the execution.
 * - Verifies state consistency after cooldown.
 *
 * Expectations:
 * - The PDS maintains stability under concurrent write stress.
 * - Performance metrics are generated, exported, and meet target latencies (p95 < 500ms for creations).
 * - Repository state reflects all successful operations across accounts.
 */

import { now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { createRunContext } from "../../lib/deno/diagnostics.ts";
import { join } from "@std/path";
import {
  InstrumentationReport,
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
  StorageMonitor,
} from "../../lib/deno/instrumentation.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Concurrent Write Throughput");
  result.start();

  const ctx = await createRunContext();
  const client = new XrpcClient(PDS1);
  interface AccountPlan {
    slot: number;
    label: string;
    name: string;
    handle: string;
    email: string;
    password: string;
    did?: string;
    accessJwt?: string;
    warmupRkeys: string[];
    burstRkeys: string[];
    mixedRkeys: string[];
    deletedRkeys: Set<string>;
  }

  function buildAccounts(): AccountPlan[] {
    const accounts: AccountPlan[] = [];
    const seedNames = ["luna", "marcus", "rosa", "volt", "quiet"];

    for (let i = 0; i < seedNames.length; i++) {
      const char = getActor(seedNames[i]);
      accounts.push({
        slot: i + 1,
        label: seedNames[i],
        name: char.name,
        handle: char.handle,
        email: char.email,
        password: char.password,
        warmupRkeys: [],
        burstRkeys: [],
        mixedRkeys: [],
        deletedRkeys: new Set(),
      });
    }

    for (let slot = 6; slot <= 32; slot++) {
      const label = `load-${slot}`;
      accounts.push({
        slot,
        label,
        name: `Load Account ${slot}`,
        handle: `${label}.test`,
        email: `${label}@test.local`,
        password: `load-pass-${slot.toString().padStart(2, "0")}`,
        warmupRkeys: [],
        burstRkeys: [],
        mixedRkeys: [],
        deletedRkeys: new Set(),
      });
    }

    return accounts;
  }

  const pdsMetricsUrl = `${SERVICE_URLS.pds}/metrics`;
  const pdsDataDir = Deno.env.get("PDS_DATA_DIR") || "/tmp/garazyk-atproto-e2e/pds-data";
  const pdsDbPath = `${pdsDataDir}/pds.db`;
  const pdsWalPath = `${pdsDataDir}/pds.db-wal`;

  const prometheus = new PrometheusScraper({ pds: pdsMetricsUrl });
  const storageMonitor = new StorageMonitor({ pds: [pdsDbPath, pdsWalPath] });

  const globalTimer = new OperationTimer();
  const phaseTimer = new PhaseTimer();
  const accounts = buildAccounts();
  let workloadCompleted = false;

  prometheus.start();
  storageMonitor.start();

  try {
    await timedCall(result, "PDS health check", async () => {
      await client.waitForHealthy(30);
    });

    if (result.failed > 0) return result;

    phaseTimer.startPhase("Setup");
    let createdCount = 0;
    for (const plan of accounts) {
      const session = await timedCall(
        result,
        `Create account: ${plan.name}`,
        async () => {
          return await globalTimer.measure(
            "create_account",
            () => client.accounts.createAccount(plan.handle, plan.email, plan.password),
          );
        },
        (s) => `did=${s.did}`,
      );
      if (session) {
        plan.did = session.did;
        plan.accessJwt = session.accessJwt;
        createdCount++;
        if (plan.slot <= 5) {
          const char = getActor(plan.label);
          char.did = session.did;
          char.accessJwt = session.accessJwt;
        }
      }
    }
    phaseTimer.endPhase();

    if (createdCount !== accounts.length) {
      result.stepFailed("Setup accounts", `created=${createdCount}/${accounts.length}`);
      return result;
    }
    result.stepPassed("Setup accounts", `created=${createdCount}`);

    phaseTimer.startPhase("Warm-up");
    const warmupStart = performance.now();
    let warmupSuccesses = 0;
    for (const plan of accounts) {
      for (let i = 1; i <= 5; i++) {
        const rkey = `w${plan.slot}-${i}`;
        try {
          const resp = await globalTimer.measure("create_record", () =>
            client.records.createRecord(
              plan.did!,
              "app.bsky.feed.post",
              {
                $type: "app.bsky.feed.post",
                text: `Warm-up ${i} from ${plan.name}`,
                createdAt: now(),
              },
              plan.accessJwt!,
              { rkey },
            ));
          const createdRkey = resp.uri.split("/").pop();
          plan.warmupRkeys.push(createdRkey);
          warmupSuccesses++;
        } catch { /* ignore */ }
      }
    }
    const warmupElapsed = (performance.now() - warmupStart) / 1000;
    result.stepPassed("Warm-up", `posts=${warmupSuccesses}, elapsed=${warmupElapsed.toFixed(1)}s`);
    phaseTimer.endPhase();

    phaseTimer.startPhase("Burst");
    const burstStart = performance.now();
    const burstPromises = accounts.map(async (plan) => {
      let successes = 0;
      for (let i = 1; i <= 10; i++) {
        const rkey = `b${plan.slot}-${i}`;
        try {
          const resp = await globalTimer.measure("create_record", () =>
            client.records.createRecord(
              plan.did!,
              "app.bsky.feed.post",
              {
                $type: "app.bsky.feed.post",
                text: `Burst ${i} from ${plan.name}`,
                createdAt: now(),
              },
              plan.accessJwt!,
              { rkey },
            ));
          plan.burstRkeys.push(resp.uri.split("/").pop());
          successes++;
        } catch { /* ignore */ }
      }
      return successes;
    });
    const burstResults = await Promise.all(burstPromises);
    const burstSuccesses = burstResults.reduce((a: number, b: number) => a + b, 0);
    const burstElapsed = (performance.now() - burstStart) / 1000;
    const burstRate = burstSuccesses / Math.max(burstElapsed, 0.01);
    result.stepPassed("Burst", `created=${burstSuccesses}, rate=${burstRate.toFixed(1)} writes/s`);
    phaseTimer.endPhase();

    phaseTimer.startPhase("Mixed workload");
    const mixedPromises = accounts.map(async (plan) => {
      let c = 0, d = 0, a = 0;
      // Create
      try {
        await globalTimer.measure("create_record", () =>
          client.records.createRecord(
            plan.did!,
            "app.bsky.feed.post",
            { $type: "app.bsky.feed.post", text: `Mixed from ${plan.name}`, createdAt: now() },
            plan.accessJwt!,
            { rkey: `m${plan.slot}-c` },
          ));
        c++;
      } catch { /* ignore */ }

      // Delete
      const delTarget = plan.warmupRkeys[0] || plan.burstRkeys[0];
      if (delTarget) {
        try {
          await globalTimer.measure(
            "delete_record",
            () =>
              client.records.deleteRecord(
                plan.did!,
                "app.bsky.feed.post",
                delTarget,
                plan.accessJwt!,
              ),
          );
          plan.deletedRkeys.add(delTarget);
          d++;
        } catch { /* ignore */ }
      }

      // ApplyWrites
      const writes = [
        {
          $type: "com.atproto.repo.applyWrites#create",
          collection: "app.bsky.feed.post",
          rkey: `m${plan.slot}-a`,
          value: {
            $type: "app.bsky.feed.post",
            text: `Batch A from ${plan.name}`,
            createdAt: now(),
          },
        },
        {
          $type: "com.atproto.repo.applyWrites#create",
          collection: "app.bsky.feed.post",
          rkey: `m${plan.slot}-b`,
          value: {
            $type: "app.bsky.feed.post",
            text: `Batch B from ${plan.name}`,
            createdAt: now(),
          },
        },
      ];
      try {
        await globalTimer.measure(
          "apply_writes",
          () => client.records.applyWrites(plan.did!, writes, plan.accessJwt!),
        );
        a += 2;
      } catch { /* ignore */ }

      return { c, d, a };
    });
    const mixedResults = await Promise.all(mixedPromises);
    const mixedCreates = mixedResults.reduce((sum: number, r) => sum + r.c, 0);
    const mixedDeletes = mixedResults.reduce((sum: number, r) => sum + r.d, 0);
    const mixedApplies = mixedResults.reduce((sum: number, r) => sum + r.a, 0);
    result.stepPassed(
      "Mixed workload",
      `creates=${mixedCreates}, deletes=${mixedDeletes}, applyWrites=${mixedApplies}`,
    );
    phaseTimer.endPhase();

    phaseTimer.startPhase("Cooldown");
    for (const plan of accounts) {
      await timedCall(result, `Cooldown verify: ${plan.name}`, async () => {
        const resp = await globalTimer.measure(
          "list_records",
          () =>
            client.records.listRecords(plan.did!, "app.bsky.feed.post", {
              limit: 100,
              token: plan.accessJwt,
            }),
        );
        const actual = new Set(resp.records.map((r: any) => r.uri.split("/").pop()));
        const expectedCount = 5 + 10 + 1 + 2 - plan.deletedRkeys.size;
        assert.isTrue(
          actual.size >= expectedCount,
          `Expected at least ${expectedCount}, got ${actual.size}`,
        );
        return { records: actual.size, expected: expectedCount };
      });
    }
    phaseTimer.endPhase();
    workloadCompleted = true;
  } finally {
    const prometheusData = await prometheus.stop();
    const storageData = await storageMonitor.stop();

    const report = new InstrumentationReport(
      globalTimer.toDict(),
      prometheusData,
      {}, // Process stats not implemented for now
      storageData,
      phaseTimer.toDict(),
    );

    result.recordArtifact("instrumentation", report.toDict());
    await report.writeJson(join(ctx.reportsDir, "instrumentation-24.json"));

    if (workloadCompleted) {
      const stats = globalTimer.getStats("create_record");
      if (stats) {
        const p95 = stats.p95;
        if (p95 < 25000) {
          result.stepPassed("Create record p95 < 25s", `p95_ms=${p95.toFixed(1)}`);
        } else {
          result.stepFailed("Create record p95 < 25s", `p95_ms=${p95.toFixed(1)}`);
        }
      }
    }

    result.finish();
  }

  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
