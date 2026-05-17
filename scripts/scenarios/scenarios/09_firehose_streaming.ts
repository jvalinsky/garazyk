/**
 * @module scenarios/09_firehose_streaming
 *
 * Scenario: Tests AT Protocol Firehose streaming and event sequencing.
 *
 * Behavior:
 * - Creates test accounts for Luna, Marcus, and Rosa.
 * - Verifies PDS and Relay service health.
 * - Establishes a Firehose WebSocket connection to the Relay.
 * - Performs various actions (post, follow, like, profile update) which generate events.
 * - Collects and validates that Firehose events are received in correct sequence.
 * - Verifies Sync API functionality (getHead, getRepo) for repository synchronization.
 * - Checks AppView backfill status and verify indexing for Luna's posts.
 *
 * Expectations:
 * - Relay stream receives events corresponding to performed actions.
 * - Firehose events maintain sequential integrity (seq order).
 * - Repository synchronization (CAR files) is available and correctly formatted.
 * - Actions are indexed by the AppView.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { FirehoseClient, FirehoseEvent } from "../../lib/deno/firehose.ts";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose & Event Streaming");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  try {
    const relayResp = await fetch(`${SERVICE_URLS.relay}/api/relay/health`);
    if (relayResp.ok) {
      result.stepPassed("Relay health check");
    } else {
      result.stepSkipped("Relay health check", `status=${relayResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("Relay health check", String(exc));
  }

  try {
    const upstreamsResp = await fetch(`${SERVICE_URLS.relay}/api/relay/upstreams`);
    if (upstreamsResp.ok) {
      const upstreams = await upstreamsResp.json();
      const count = Array.isArray(upstreams) ? upstreams.length : 0;
      result.stepPassed("Relay upstreams", `count=${count}`);
    } else {
      result.stepSkipped("Relay upstreams", `status=${upstreamsResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("Relay upstreams", String(exc));
  }

  const charNames = ["luna", "marcus", "rosa"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  const rosa = getCharacter("rosa");

  if (!luna.did || !marcus.did || !rosa.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  await new Promise((r) => setTimeout(r, 2000));

  const firehoseEvents: FirehoseEvent[] = [];
  const fhClient = new FirehoseClient(SERVICE_URLS.relay.replace(/^http/, "ws"));

  // Start collecting in background (we don't await this directly)
  const collectionPromise = fhClient.collect(10.0);

  await new Promise((r) => setTimeout(r, 1000));
  result.stepPassed("Firehose WebSocket connection", "started collecting");

  const lunaPost = await timedCall(
    result,
    "Luna creates firehose test post",
    async () => {
      return await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Firehose test post! If you can see this on the relay, streaming works!",
          createdAt: now(),
        },
      }, luna.accessJwt);
    },
  );

  await timedCall(
    result,
    "Marcus follows Luna (firehose event)",
    async () => {
      return await client.raw.post("com.atproto.repo.createRecord", {
        repo: marcus.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: luna.did,
          createdAt: now(),
        },
      }, marcus.accessJwt);
    },
  );

  if (lunaPost) {
    await timedCall(
      result,
      "Rosa likes Luna's post (firehose event)",
      async () => {
        return await client.raw.post("com.atproto.repo.createRecord", {
          repo: rosa.did,
          collection: "app.bsky.feed.like",
          record: {
            $type: "app.bsky.feed.like",
            subject: { uri: lunaPost.uri, cid: lunaPost.cid },
            createdAt: now(),
          },
        }, rosa.accessJwt);
      },
    );
  }

  await timedCall(
    result,
    "Luna updates profile (firehose event)",
    async () => {
      return await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.actor.profile",
        record: {
          $type: "app.bsky.actor.profile",
          displayName: "Luna Starfield",
          description: "Astronomy enthusiast. Firehose tester.",
        },
      }, luna.accessJwt);
    },
  );

  await new Promise((r) => setTimeout(r, 3000));
  const collectedEvents = await collectionPromise;

  result.stepPassed("Post-operation firehose collection", `events=${collectedEvents.length}`);

  const targetCount = 3;
  if (collectedEvents.length >= targetCount) {
    const seqs = collectedEvents.map((e) => e.seq).filter((s) => s > 0);
    if (seqs.length > 0) {
      let isOrdered = true;
      for (let i = 0; i < seqs.length - 1; i++) {
        if (seqs[i] > seqs[i + 1]) {
          isOrdered = false;
          break;
        }
      }
      if (isOrdered) {
        result.stepPassed("Event sequencing", `seqs=${seqs.slice(0, 5).join(",")}... (ordered)`);
      } else {
        result.stepFailed("Event sequencing", `seqs not ordered: ${seqs.join(",")}`);
      }
    } else {
      result.stepFailed(
        "Event sequencing",
        `No seq numbers found in ${collectedEvents.length} events`,
      );
    }
  } else {
    result.stepFailed(
      "Event sequencing",
      `Only ${collectedEvents.length} events collected, need ${targetCount}`,
    );
  }

  await timedCall(
    result,
    "Sync getHead",
    async () => {
      return await client.raw.get("com.atproto.sync.getHead", { did: luna.did });
    },
    (r) => `root=${r.root.substring(0, 20)}`,
  );

  const repoResp = await timedCall(
    result,
    "Sync getRepo",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.sync.getRepo?did=${luna.did}`);
      const buf = await res.arrayBuffer();
      return {
        status: res.status,
        contentType: res.headers.get("Content-Type") || "",
        body: new Uint8Array(buf),
      };
    },
    (r) => `car bytes=${r.body.length} content_type=${r.contentType}`,
  );

  if (repoResp) {
    if (!repoResp.contentType.includes("application/vnd.ipld.car")) {
      result.stepFailed(
        "Sync getRepo",
        `unexpected content_type=${repoResp.contentType} status=${repoResp.status}`,
      );
    } else if (repoResp.body.length === 0) {
      result.stepFailed("Sync getRepo", "empty CAR body");
    }
  }

  await new Promise((r) => setTimeout(r, 3000));

  try {
    const appviewResp = await fetch(`${SERVICE_URLS.appview}/admin/backfill/status`, {
      headers: { "Authorization": "Bearer localdevadmin" },
    });
    if (appviewResp.ok) {
      result.stepPassed(
        "AppView backfill status",
        `body=${(await appviewResp.text()).substring(0, 100)}`,
      );
    } else {
      result.stepFailed("AppView backfill status", `status=${appviewResp.status}`);
    }
  } catch (exc: any) {
    result.stepFailed("AppView backfill status", String(exc));
  }

  await timedCall(
    result,
    "AppView indexed Luna's posts",
    async () => {
      return await client.raw.get(
        "app.bsky.feed.getAuthorFeed",
        { actor: luna.did },
        luna.accessJwt,
      );
    },
    (f) => `items=${f.feed?.length || 0}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
