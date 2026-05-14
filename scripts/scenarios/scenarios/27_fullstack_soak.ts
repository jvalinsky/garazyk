import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, APPVIEW_ADMIN_SECRET, getCharacter, Character } from "../../lib/deno/config.ts";
import { createRunContext } from "../../lib/deno/diagnostics.ts";
import {
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
  StorageMonitor,
  InstrumentationReport,
} from "../../lib/deno/instrumentation.ts";
import { join } from "@std/path";

const WORKLOAD_SECONDS = 120;
const WORKER_COUNT = 10;
const POSTS_PER_ACCOUNT = 5;

function now() {
  return new Date().toISOString();
}

function makeSoakCharacter(index: number): Character {
  return new Character(
    `Soak ${index}`,
    `soak-${index}.test`,
    `soak-${index}@test.local`,
    `soak_pass_${index}`,
    `High-volume soak test account ${index}`
  );
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Full-Stack Soak");
  result.start();

  const client = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const adminToken = APPVIEW_ADMIN_SECRET;

  const timer = new OperationTimer();
  const phaseTimer = new PhaseTimer();

  const promScraper = new PrometheusScraper({
    pds: `${PDS1}/metrics`,
    relay: `${SERVICE_URLS.relay}/api/relay/metrics`,
    appview: `${SERVICE_URLS.appview}/admin/appview/metrics/stats`,
  });
  promScraper.start();

  const pdsDataDir = Deno.env.get("PDS_DATA_DIR") || "/tmp/garazyk-atproto-e2e/pds-data";
  const avDataDir = Deno.env.get("APPVIEW_DATA_DIR") || "/tmp/garazyk-atproto-e2e/appview";
  const storageMonitor = new StorageMonitor({
    pds: [join(pdsDataDir, "pds.db"), join(pdsDataDir, "pds.db-wal")],
    appview: [join(avDataDir, "appview.db"), join(avDataDir, "appview.db-wal")],
  });
  storageMonitor.start();

  try {
    phaseTimer.startPhase("Setup");
    await timedCall(result, "PDS health check", async () => {
      await client.waitForHealthy(30);
    });

    if (result.failed > 0) return result;

    const accounts: Character[] = [];
    for (const name of ["luna", "marcus", "rosa", "volt", "quiet"]) {
      accounts.push(getCharacter(name));
    }
    for (let i = 1; i <= 12; i++) {
      accounts.push(makeSoakCharacter(i));
    }

    const activeAccounts: Character[] = [];
    for (const acc of accounts) {
      const session = await timedCall(
        result, `Create account: ${acc.name}`,
        async () => {
          return await timer.measure("create_account", () =>
            client.accounts.createAccount(acc.handle, acc.email, acc.password)
          );
        }
      );
      if (session) {
        acc.did = session.did;
        acc.accessJwt = session.accessJwt;
        activeAccounts.push(acc);
        
        await timer.measure("setup_profile", () =>
          client.records.putRecord(acc.did, "app.bsky.actor.profile", "self", {
            $type: "app.bsky.actor.profile",
            displayName: acc.name,
            description: acc.persona
          }, acc.accessJwt)
        );
      }
    }

    if (activeAccounts.length < accounts.length) {
      result.stepFailed("Account setup", `created=${activeAccounts.length}/${accounts.length}`);
    }

    phaseTimer.endPhase();

    phaseTimer.startPhase("Sustained mixed workload");
    const workloadStart = Date.now();
    const deadline = workloadStart + WORKLOAD_SECONDS * 1000;

    const workerLoop = async (id: number) => {
      const workerClient = new XrpcClient(PDS1);
      const postPool: any[] = [];
      
      while (Date.now() < deadline) {
        const acc = activeAccounts[Math.floor(Math.random() * activeAccounts.length)];
        const op = Math.random();
        
        try {
          if (op < 0.3) { // Post
            const resp = await timer.measure("create_post", () =>
              workerClient.records.createRecord(acc.did, "app.bsky.feed.post", {
                $type: "app.bsky.feed.post",
                text: `Soak post from worker ${id} at ${now()}`,
                createdAt: now()
              }, acc.accessJwt)
            );
            postPool.push({ uri: resp.uri, cid: resp.cid, author: acc.did });
          } else if (op < 0.5 && postPool.length > 0) { // Like
            const post = postPool[Math.floor(Math.random() * postPool.length)];
            await timer.measure("create_like", () =>
              workerClient.records.createRecord(acc.did, "app.bsky.feed.like", {
                $type: "app.bsky.feed.like",
                subject: { uri: post.uri, cid: post.cid },
                createdAt: now()
              }, acc.accessJwt)
            );
          } else if (op < 0.7) { // Timeline
            await timer.measure("get_timeline", () =>
              workerClient.feed.getTimeline(acc.accessJwt, 50)
            );
          } else { // Notifications
            await timer.measure("list_notifications", () =>
              workerClient.notifications.listNotifications(acc.accessJwt, 50)
            );
          }
        } catch { /* ignore workload errors */ }
        
        await new Promise(r => setTimeout(r, 100 + Math.random() * 200));
      }
    };

    const workerPromises = Array.from({ length: WORKER_COUNT }).map((_, i) => workerLoop(i));
    await Promise.all(workerPromises);
    phaseTimer.endPhase();

    phaseTimer.startPhase("Consistency verification");
    // Wait for indexing
    await new Promise(r => setTimeout(r, 5000));
    
    await timedCall(result, "PDS check", async () => {
      const resp = await client.accounts.describeServer();
      assert(resp.availableUserDomains.length > 0);
    });

    await timedCall(result, "AppView check", async () => {
      return await appview.raw.httpGet("/admin/backfill/status", undefined, adminToken);
    });
    phaseTimer.endPhase();

  } finally {
    const metricsTs = await promScraper.stop();
    const storageData = await storageMonitor.stop();
    const ctx = await createRunContext();

    const report = new InstrumentationReport(
      timer.toDict(),
      metricsTs,
      {},
      storageData,
      phaseTimer.toDict()
    );

    result.recordArtifact("instrumentation", report.toDict());
    await report.writeJson(join(ctx.reportsDir, "instrumentation-27.json"));

    result.finish();
  }

  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
