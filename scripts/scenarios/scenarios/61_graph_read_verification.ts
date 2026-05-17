/**
 * @module scenarios/61_graph_read_verification
 *
 * Scenario: 61 graph read verification
 *
 * Behavior:
 * - Executes the 61 graph read verification scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getCharacter, PDS1 } from "@garazyk/hamownia";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Graph Read Verification");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Create two accounts
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  const lunaSession = await timedCall(
    result,
    `Create account: ${luna.name}`,
    async () => {
      return await client.accounts.createAccount(luna.handle, luna.email, luna.password);
    },
    (s) => `did=${s.did}`,
  );
  if (!lunaSession) {
    result.finish();
    return result;
  }
  luna.did = lunaSession.did;
  luna.accessJwt = lunaSession.accessJwt;
  luna.refreshJwt = lunaSession.refreshJwt;

  const marcusSession = await timedCall(
    result,
    `Create account: ${marcus.name}`,
    async () => {
      return await client.accounts.createAccount(marcus.handle, marcus.email, marcus.password);
    },
    (s) => `did=${s.did}`,
  );
  if (!marcusSession) {
    result.finish();
    return result;
  }
  marcus.did = marcusSession.did;
  marcus.accessJwt = marcusSession.accessJwt;
  marcus.refreshJwt = marcusSession.refreshJwt;

  // ── Follow: Luna follows Marcus ──────────────────────────────────────────
  const followUri = await timedCall(
    result,
    "Luna follows Marcus",
    async () => {
      return await client.records.createRecord(
        luna.did,
        "app.bsky.graph.follow",
        { $type: "app.bsky.graph.follow", subject: marcus.did, createdAt: now() },
        luna.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  // ── Verify getFollows returns Marcus ──────────────────────────────────────
  if (followUri) {
    await timedCall(
      result,
      "getFollows returns Marcus",
      async () => {
        const res = await client.graph.getFollows(luna.did, { token: luna.accessJwt });
        const follows = res.follows || [];
        const found = follows.some((f: any) => f.did === marcus.did);
        if (!found) {
          throw new Error(`Marcus not found in Luna's follows (got ${follows.length} follows)`);
        }
        return res;
      },
      (r) => `follows=${r.follows?.length || 0}`,
    );

    // ── Verify getFollowers returns Luna ──────────────────────────────────────
    await timedCall(
      result,
      "getFollowers returns Luna",
      async () => {
        const res = await client.graph.getFollowers(marcus.did, { token: marcus.accessJwt });
        const followers = res.followers || [];
        const found = followers.some((f: any) => f.did === luna.did);
        if (!found) {
          throw new Error(
            `Luna not found in Marcus's followers (got ${followers.length} followers)`,
          );
        }
        return res;
      },
      (r) => `followers=${r.followers?.length || 0}`,
    );

    // ── Verify getRelationships ──────────────────────────────────────────────
    await timedCall(
      result,
      "getRelationships shows Luna→Marcus follow",
      async () => {
        const res = await client.graph.getRelationships(luna.did, [marcus.did], luna.accessJwt);
        const rels = res.relationships || [];
        const rel = rels.find((r: any) => r.did === marcus.did);
        if (!rel) throw new Error("No relationship found for Marcus");
        if (!rel.following) {
          throw new Error(`Expected following=true, got following=${rel.following}`);
        }
        return res;
      },
      (r) => `relationships=${r.relationships?.length || 0}`,
    );
  }

  // ── Block: Luna blocks Troll ─────────────────────────────────────────────
  const troll = getCharacter("troll");
  const trollSession = await timedCall(
    result,
    `Create account: ${troll.name}`,
    async () => {
      return await client.accounts.createAccount(troll.handle, troll.email, troll.password);
    },
    (s) => `did=${s.did}`,
  );
  if (trollSession) {
    troll.did = trollSession.did;
    troll.accessJwt = trollSession.accessJwt;

    const blockUri = await timedCall(
      result,
      "Luna blocks Troll",
      async () => {
        return await client.records.createRecord(
          luna.did,
          "app.bsky.graph.block",
          { $type: "app.bsky.graph.block", subject: troll.did, createdAt: now() },
          luna.accessJwt,
        );
      },
      (r) => `uri=${r.uri}`,
    );

    if (blockUri) {
      // ── Verify getBlocks returns Troll ──────────────────────────────────────
      await timedCall(
        result,
        "getBlocks returns Troll",
        async () => {
          const res = await client.graph.getBlocks(luna.accessJwt);
          const blocks = res.blocks || [];
          const found = blocks.some((b: any) => b.did === troll.did);
          if (!found) {
            throw new Error(`Troll not found in Luna's blocks (got ${blocks.length} blocks)`);
          }
          return res;
        },
        (r) => `blocks=${r.blocks?.length || 0}`,
      );
    }
  }

  // ── Mute: Luna mutes Marcus ───────────────────────────────────────────────
  await timedCall(
    result,
    "Luna mutes Marcus",
    async () => {
      return await client.graph.muteActor(marcus.did, luna.accessJwt);
    },
  );

  await timedCall(
    result,
    "getMutes returns Marcus",
    async () => {
      const res = await client.graph.getMutes(luna.accessJwt);
      const mutes = res.mutes || [];
      const found = mutes.some((m: any) => m.did === marcus.did);
      if (!found) throw new Error(`Marcus not found in Luna's mutes (got ${mutes.length} mutes)`);
      return res;
    },
    (r) => `mutes=${r.mutes?.length || 0}`,
  );

  // ── Unmute ────────────────────────────────────────────────────────────────
  await timedCall(
    result,
    "Luna unmutes Marcus",
    async () => {
      return await client.graph.unmuteActor(marcus.did, luna.accessJwt);
    },
  );

  await timedCall(
    result,
    "getMutes no longer returns Marcus",
    async () => {
      const res = await client.graph.getMutes(luna.accessJwt);
      const mutes = res.mutes || [];
      const found = mutes.some((m: any) => m.did === marcus.did);
      if (found) throw new Error("Marcus still in mutes after unmute");
      return res;
    },
    (r) => `mutes=${r.mutes?.length || 0}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const r = await run();
  console.log(r.summary());
  Deno.exit(r.ok ? 0 : 1);
}
