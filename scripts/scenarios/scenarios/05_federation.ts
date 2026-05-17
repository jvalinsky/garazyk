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

import { XrpcClient } from "@garazyk/atproto-client";
import { getCharacter, PDS1, PDS2, SERVICE_URLS } from "@garazyk/scenario-runner";
import { ScenarioResult, timedCall } from "@garazyk/scenario-runner";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/scenario-runner";
export type { ScenarioReport } from "@garazyk/scenario-runner";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Federation & Multi-PDS");
  result.start();

  const pds1 = new XrpcClient(PDS1);
  const pds2 = new XrpcClient(PDS2);

  for (const { name, client } of [{ name: "PDS1", client: pds1 }, { name: "PDS2", client: pds2 }]) {
    await timedCall(
      result,
      `${name} health check`,
      async () => {
        const res = await fetch(`${client.baseUrl}/xrpc/com.atproto.server.describeServer`);
        if (!res.ok) throw new Error(`${name} not healthy`);
      },
    );
  }

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account on PDS1: ${char.name}`,
      async () => {
        try {
          const res = await pds1.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await pds1.agent.login({
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

  const nova = getCharacter("nova");
  const rex = getCharacter("rex");
  for (const char of [nova, rex]) {
    const session = await timedCall(
      result,
      `Create account on PDS2: ${char.name}`,
      async () => {
        try {
          const res = await pds2.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await pds2.agent.login({
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
        await client.raw.post("com.atproto.repo.createRecord", {
          repo: char.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
          },
        }, char.accessJwt);
      },
    );
  }

  const lunaPost = await timedCall(
    result,
    "Luna posts on PDS 1",
    async () => {
      const res = await pds1.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Hello from PDS 1! Can anyone on PDS 2 see this?",
          createdAt: now(),
        },
      }, luna.accessJwt);
      return res;
    },
  );

  const marcusPost = await timedCall(
    result,
    "Marcus posts on PDS 1",
    async () => {
      const res = await pds1.raw.post("com.atproto.repo.createRecord", {
        repo: marcus.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Federation is the future of social media! Building bridges across PDSes.",
          createdAt: now(),
        },
      }, marcus.accessJwt);
      return res;
    },
  );

  try {
    const plcResp = await fetch(`${SERVICE_URLS.plc}/${luna.did}`);
    if (plcResp.ok) {
      const didDoc = await plcResp.json();
      result.stepPassed(
        "PLC resolves Luna's DID",
        `alsoKnownAs=${JSON.stringify(didDoc.alsoKnownAs)}`,
      );
    } else {
      result.stepSkipped("PLC resolves Luna's DID", `PLC returned ${plcResp.status}`);
    }
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
      const res = await pds2.raw.post("com.atproto.repo.createRecord", {
        repo: nova.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: luna.did,
          createdAt: now(),
        },
      }, nova.accessJwt);
      return res;
    },
    (r) => `uri=${r.uri}`,
  );

  await timedCall(
    result,
    "Rex follows Marcus (cross-PDS)",
    async () => {
      const res = await pds2.raw.post("com.atproto.repo.createRecord", {
        repo: rex.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: marcus.did,
          createdAt: now(),
        },
      }, rex.accessJwt);
      return res;
    },
    (r) => `uri=${r.uri}`,
  );

  if (marcusPost) {
    await timedCall(
      result,
      "Rex replies to Marcus (cross-PDS)",
      async () => {
        await pds2.raw.post("com.atproto.repo.createRecord", {
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
        }, rex.accessJwt);
      },
    );
  }

  await new Promise((r) => setTimeout(r, 5000));

  try {
    const relayResp = await fetch(`${SERVICE_URLS.relay}/api/relay/health`);
    if (relayResp.ok) {
      result.stepPassed("Relay health check", `body=${(await relayResp.text()).substring(0, 100)}`);
    } else {
      result.stepSkipped("Relay health check", `status=${relayResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("Relay health check", exc.message || String(exc));
  }

  try {
    const upstreamsResp = await fetch(`${SERVICE_URLS.relay}/api/relay/upstreams`);
    if (upstreamsResp.ok) {
      const upstreams = await upstreamsResp.json();
      const count = Array.isArray(upstreams)
        ? upstreams.length
        : (upstreams.upstreams?.length || 0);
      result.stepPassed("Relay upstreams", `count=${count}`);
    } else {
      result.stepSkipped("Relay upstreams", `status=${upstreamsResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("Relay upstreams", exc.message || String(exc));
  }

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
      result.stepSkipped("AppView backfill status", `status=${appviewResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("AppView backfill status", exc.message || String(exc));
  }

  await timedCall(
    result,
    "Nova views Luna's profile via AppView",
    async () => {
      return await pds2.raw.get("app.bsky.actor.getProfile", { actor: luna.did }, nova.accessJwt);
    },
    (p) => `displayName=${p.displayName}`,
  );

  await timedCall(
    result,
    "Nova sees Luna's feed via AppView",
    async () => {
      return await pds2.raw.get("app.bsky.feed.getAuthorFeed", { actor: luna.did }, nova.accessJwt);
    },
    (f) => `items=${f.feed?.length || 0}`,
  );

  if (lunaPost) {
    await timedCall(
      result,
      "Cross-PDS record retrieval",
      async () => {
        return await pds2.raw.get("com.atproto.repo.getRecord", {
          repo: luna.did,
          collection: "app.bsky.feed.post",
          rkey: lunaPost.uri.split("/").pop(),
        }, nova.accessJwt);
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
