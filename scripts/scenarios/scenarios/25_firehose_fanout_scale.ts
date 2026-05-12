import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";
import { FirehoseClient } from "../../lib/deno/firehose.ts";
import { createRunContext } from "../../lib/deno/diagnostics.ts";
import {
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
  InstrumentationReport,
} from "../../lib/deno/instrumentation.ts";
import { join } from "@std/path";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Fan-Out at Scale");
  result.start();

  const client = new XrpcClient(PDS1);
  const timer = new OperationTimer();
  const phaseTimer = new PhaseTimer();

  phaseTimer.startPhase("setup");

  const promEndpoints = {
    pds: `${SERVICE_URLS.pds}/metrics`,
    relay: `${SERVICE_URLS.relay}/api/relay/metrics`,
  };
  const promScraper = new PrometheusScraper(promEndpoints);
  promScraper.start();

  await timedCall(result, "Server health check", async () => {
    await client.wait_for_healthy(30);
  });

  if (result.failed > 0) {
    await promScraper.stop();
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt", "quiet"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        return await timer.measure("create_account", () =>
          client.accounts.createAccount(char.handle, char.email, char.password)
        );
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter(n => getCharacter(n).did);
  phaseTimer.endPhase();

  phaseTimer.startPhase("subscriber_rampup");

  const NUM_SUBSCRIBERS = 50;
  const subscriberEvents: any[] = [];
  const subscriberStop = { stopped: false };
  const relayUrl = SERVICE_URLS.relay;

  const startSubscriber = async (id: number) => {
    const fh = new FirehoseClient(relayUrl);
    while (!subscriberStop.stopped) {
      try {
        await fh.subscribe((ev) => {
          (ev as any)._subscriber_id = id;
          (ev as any)._received_at = Date.now() / 1000;
          subscriberEvents.push(ev);
        }, 60);
      } catch {
        if (!subscriberStop.stopped) await new Promise(r => setTimeout(r, 1000));
      }
    }
  };

  const subscriberPromises = [];
  for (let i = 0; i < NUM_SUBSCRIBERS; i++) {
    subscriberPromises.push(startSubscriber(i));
  }

  await new Promise(r => setTimeout(r, 3000));
  result.stepPassed("Subscriber ramp-up", `Started ${NUM_SUBSCRIBERS} firehose subscribers`);
  phaseTimer.endPhase();

  phaseTimer.startPhase("event_production");

  const POSTS_PER_USER = 20;
  let totalPosts = 0;

  const postPromises = active.flatMap(name => {
    const char = getCharacter(name);
    return Array.from({ length: POSTS_PER_USER }).map(async (_, i) => {
      try {
        await timer.measure("create_post", () =>
          client.records.createRecord(
            char.did!, "app.bsky.feed.post",
            { $type: "app.bsky.feed.post", text: `Fanout post ${i + 1} from ${char.name}`, createdAt: now() },
            char.accessJwt!
          )
        );
        totalPosts++;
      } catch { /* ignore */ }
    });
  });

  await Promise.all(postPromises);
  result.stepPassed("Event production", `created=${totalPosts}`);
  phaseTimer.endPhase();

  await new Promise(r => setTimeout(r, 5000));

  phaseTimer.startPhase("backpressure_test");
  const extraPromises = [];
  for (let i = 0; i < NUM_SUBSCRIBERS; i++) {
    extraPromises.push(startSubscriber(NUM_SUBSCRIBERS + i));
  }

  await new Promise(r => setTimeout(r, 3000));

  const BURST_PER_USER = 40;
  let burstPosts = 0;
  const burstPromises = active.flatMap(name => {
    const char = getCharacter(name);
    return Array.from({ length: BURST_PER_USER }).map(async (_, i) => {
      try {
        await timer.measure("create_post_burst", () =>
          client.records.createRecord(
            char.did!, "app.bsky.feed.post",
            { $type: "app.bsky.feed.post", text: `Burst post ${i + 1} from ${char.name}`, createdAt: now() },
            char.accessJwt!
          )
        );
        burstPosts++;
      } catch { /* ignore */ }
    });
  });

  await Promise.all(burstPromises);
  result.stepPassed("Backpressure burst", `created=${burstPosts}`);

  try {
    const res = await fetch(`${SERVICE_URLS.pds}/metrics`);
    const text = await res.text();
    let bpWarnings = 0;
    let bpCritical = 0;
    for (const line of text.split("\n")) {
      if (line.includes("pds_websocket_backpressure_warnings_total")) bpWarnings = parseInt(line.split(" ").pop() || "0");
      if (line.includes("pds_websocket_backpressure_critical_total")) bpCritical = parseInt(line.split(" ").pop() || "0");
    }
    result.stepPassed("Backpressure metrics", `warnings=${bpWarnings}, critical=${bpCritical}`);
  } catch { /* ignore */ }

  await new Promise(r => setTimeout(r, 5000));
  phaseTimer.endPhase();

  phaseTimer.startPhase("subscriber_teardown");
  subscriberStop.stopped = true;
  // We don't await subscriberPromises/extraPromises as they might be stuck in read
  result.stepPassed("Subscriber teardown", `total_events=${subscriberEvents.length}`);
  phaseTimer.endPhase();

  phaseTimer.startPhase("instrumentation");
  const metricsTs = await promScraper.stop();
  const ctx = await createRunContext();
  const report = new InstrumentationReport(
    timer.toDict(),
    metricsTs,
    {},
    {},
    phaseTimer.toDict()
  );
  result.recordArtifact("instrumentation", report.toDict());
  await report.writeJson(join(ctx.reportsDir, "instrumentation-25.json"));
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
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
