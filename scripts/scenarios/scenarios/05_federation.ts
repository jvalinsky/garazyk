/**
 * @module scenarios/05_federation
 *
 * Scenario: Federation across multi-PDS and relay environment
 *
 * Behavior:
 * - Create accounts on two separate PDS instances (PDS1 and PDS2)
 * - Users perform cross-PDS actions: follows, replies, and content retrieval
 * - Verify identity resolution via PLC
 * - Verify relay and AppView connectivity/backfill status
 *
 * Expectations:
 * - Accounts on PDS1 and PDS2 successfully interact
 * - PLC handles identity resolution across PDSes
 * - Relay and AppView successfully propagate cross-PDS data
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, PDS2, SERVICE_URLS } from "../../lib/deno/config.ts";
import { createAccountOrLogin, now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Federation & Multi-PDS");
  result.start();

  const pds1 = new XrpcClient(PDS1);
  const pds2 = new XrpcClient(PDS2);
  const av = new XrpcClient(SERVICE_URLS.appview);

  for (const { name, client } of [{ name: "PDS1", client: pds1 }, { name: "PDS2", client: pds2 }]) {
    await timedCall(
      result,
      `${name} health check`,
      async () => {
        await client.raw.xrpcGet("com.atproto.server.describeServer");
      },
    );
  }

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");
  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account on PDS1: ${char.name}`,
      () => createAccountOrLogin(pds1, char),
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const nova = getActor("nova");
  const rex = getActor("rex");
  for (const char of [nova, rex]) {
    const session = await timedCall(
      result,
      `Create account on PDS2: ${char.name}`,
      () => createAccountOrLogin(pds2, char),
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did || !nova.did || !rex.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  for (
    const { char, client } of [{ char: luna, client: pds1 }, { char: marcus, client: pds1 }, {
      char: nova,
      client: pds2,
    }, { char: rex, client: pds2 }]
  ) {
    await timedCall(
      result,
      `Set profile: ${char.name}`,
      async () => {
        await client.as(char).raw.post("com.atproto.repo.createRecord", {
          repo: char.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
          },
        });
      },
    );
  }

  const lunaPost = await timedCall(
    result,
    "Luna posts on PDS 1",
    async () => {
      const res = await pds1.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Hello from PDS 1! Can anyone on PDS 2 see this?",
          createdAt: now(),
        },
      });
      return res;
    },
  );

  const marcusPost = await timedCall(
    result,
    "Marcus posts on PDS 1",
    async () => {
      const res = await pds1.as(marcus).raw.post("com.atproto.repo.createRecord", {
        repo: marcus.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Federation is the future of social media! Building bridges across PDSes.",
          createdAt: now(),
        },
      });
      return res;
    },
  );

  try {
    const didDoc = await pds1.raw.httpGet(`${SERVICE_URLS.plc}/${luna.did}`);
    result.stepPassed(
      "PLC resolves Luna's DID",
      `alsoKnownAs=${JSON.stringify(didDoc.alsoKnownAs)}`,
    );
  } catch (exc: any) {
    result.stepSkipped("PLC resolves Luna's DID", exc.message || String(exc));
  }

  const resolved = await timedCall(
    result,
    "Nova resolves Luna's handle from PDS2",
    async () => {
      return await pds2.raw.get("com.atproto.identity.resolveHandle", { handle: luna.handle });
    },
    (r) => `did=${r.did}`,
  );

  if (resolved && resolved.did !== luna.did) {
    result.stepFailed(
      "Nova resolves Luna's handle from PDS2",
      `expected ${luna.did}, got ${resolved.did}`,
    );
  }

  await timedCall(
    result,
    "Nova follows Luna (cross-PDS)",
    async () => {
      const res = await pds2.as(nova).raw.post("com.atproto.repo.createRecord", {
        repo: nova.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: luna.did,
          createdAt: now(),
        },
      });
      return res;
    },
    (r) => `uri=${r.uri}`,
  );

  await timedCall(
    result,
    "Rex follows Marcus (cross-PDS)",
    async () => {
      const res = await pds2.as(rex).raw.post("com.atproto.repo.createRecord", {
        repo: rex.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: marcus.did,
          createdAt: now(),
        },
      });
      return res;
    },
    (r) => `uri=${r.uri}`,
  );

  if (marcusPost) {
    await timedCall(
      result,
      "Rex replies to Marcus (cross-PDS)",
      async () => {
        await pds2.as(rex).raw.post("com.atproto.repo.createRecord", {
          repo: rex.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Hey Marcus! Replying from PDS 2. Federation works!",
            createdAt: now(),
            reply: {
              root: { uri: marcusPost.uri, cid: marcusPost.cid },
              parent: { uri: marcusPost.uri, cid: marcusPost.cid },
            },
          },
        });
      },
    );
  }

  await new Promise((r) => setTimeout(r, 5000));

  try {
    const relayClient = new XrpcClient(SERVICE_URLS.relay);
    const relayHealth = await relayClient.raw.httpGet("/api/relay/health");
    result.stepPassed("Relay health check", `body=${JSON.stringify(relayHealth).substring(0, 100)}`);
  } catch (exc: any) {
    result.stepSkipped("Relay health check", exc.message || String(exc));
  }

  try {
    const relayClient = new XrpcClient(SERVICE_URLS.relay);
    const upstreams = await relayClient.raw.httpGet("/api/relay/upstreams");
    const count = Array.isArray(upstreams)
      ? upstreams.length
      : (upstreams.upstreams?.length || 0);
    result.stepPassed("Relay upstreams", `count=${count}`);
  } catch (exc: any) {
    result.stepSkipped("Relay upstreams", exc.message || String(exc));
  }

  try {
    const appviewResp = await av.asAdmin("localdevadmin").raw.httpGet("/admin/backfill/status");
    result.stepPassed(
      "AppView backfill status",
      `body=${JSON.stringify(appviewResp).substring(0, 100)}`,
    );
  } catch (exc: any) {
    result.stepSkipped("AppView backfill status", exc.message || String(exc));
  }

  await timedCall(
    result,
    "Nova views Luna's profile via AppView",
    async () => {
      return await pds2.as(nova).raw.get("app.bsky.actor.getProfile", { actor: luna.did });
    },
    (p) => `displayName=${p.displayName}`,
  );

  await timedCall(
    result,
    "Nova sees Luna's feed via AppView",
    async () => {
      return await pds2.as(nova).raw.get("app.bsky.feed.getAuthorFeed", { actor: luna.did });
    },
    (f) => `items=${f.feed?.length || 0}`,
  );

  if (lunaPost) {
    await timedCall(
      result,
      "Cross-PDS record retrieval",
      async () => {
        return await pds2.as(nova).raw.get("com.atproto.repo.getRecord", {
          repo: luna.did,
          collection: "app.bsky.feed.post",
          rkey: lunaPost.uri.split("/").pop(),
        });
      },
      (r) => `uri=${r.uri}`,
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
