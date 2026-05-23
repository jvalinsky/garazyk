/**
 * @module scenarios/82_graph_advanced_endpoints
 *
 * Scenario: Graph advanced read & discovery endpoints.
 *
 * Behavior:
 * - Creates accounts, profiles, follows, and blocks.
 * - Tests app.bsky.graph.getKnownFollowers (followers known to both actors).
 * - Tests app.bsky.graph.getListMutes (list-level mutes only).
 * - Tests app.bsky.graph.getSuggestedFollowsByActor (suggested follows for an actor).
 * - Tests app.bsky.graph.getListsWithMembership (lists the actor belongs to).
 * - Tests app.bsky.graph.searchStarterPacks (search starter packs).
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { now, ScenarioResult, timedCall, tryEndpoint } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Graph Advanced Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Create 4 accounts: luna, marcus, rosa, troll
  const names = ["luna", "marcus", "rosa", "troll"];
  for (const name of names) {
    const char = getActor(name);
    await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await pds.accounts.createAccount(char.handle, char.email, char.password)
          .catch(() => pds.accounts.createSession(char.handle, char.password));
      },
      (s) => `did=${s.did}`,
    );
  }

  const active = names.filter((n) => getActor(n).did);
  if (active.length < 3) {
    result.stepFailed("Account setup", `only ${active.length} accounts`);
    result.finish();
    return result;
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");
  const rosa = getActor("rosa");
  const troll = getActor("troll");

  // Set up profiles
  for (const char of [luna, marcus, rosa, troll]) {
    await tryEndpoint(
      result,
      `Set profile: ${char.name}`,
      async () => {
        return await pds.records.createRecord(
          char.did!,
          "app.bsky.actor.profile",
          { $type: "app.bsky.actor.profile", displayName: char.name, description: char.persona },
          char.accessJwt!,
        );
      },
    );
  }

  // ── Establish follows ──────────────────────────────────────────────────
  // marcus follows luna, rosa follows luna, troll follows luna
  // This gives Luna followers that known_followers can test
  for (const follower of [marcus, rosa, troll]) {
    if (follower.did && follower.accessJwt && luna.did) {
      await timedCall(
        result,
        `${follower.name} follows Luna`,
        async () => {
          return await pds.records.createRecord(
            follower.did!,
            "app.bsky.graph.follow",
            { $type: "app.bsky.graph.follow", subject: luna.did, createdAt: now() },
            follower.accessJwt!,
          );
        },
        (r) => `uri=${r.uri}`,
      );
    }
  }

  // luna follows marcus and rosa (so getSuggestedFollowsByActor has context)
  for (const target of [marcus, rosa]) {
    if (luna.did && luna.accessJwt && target.did) {
      await timedCall(
        result,
        `Luna follows ${target.name}`,
        async () => {
          return await pds.records.createRecord(
            luna.did!,
            "app.bsky.graph.follow",
            { $type: "app.bsky.graph.follow", subject: target.did, createdAt: now() },
            luna.accessJwt!,
          );
        },
      );
    }
  }

  // marcus also follows rosa (so there's mutual follows for known_followers)
  if (marcus.did && marcus.accessJwt && rosa.did) {
    await timedCall(
      result,
      "Marcus follows Rosa",
      async () => {
        return await pds.records.createRecord(
          marcus.did!,
          "app.bsky.graph.follow",
          { $type: "app.bsky.graph.follow", subject: rosa.did, createdAt: now() },
          marcus.accessJwt!,
        );
      },
    );
  }

  await new Promise((r) => setTimeout(r, 2000));

  // ── 1. app.bsky.graph.getKnownFollowers ─────────────────────────────────
  // Actors that follow both the actor and the viewer: marcus follows luna,
  // marcus also follows rosa → check if marcus knows followers of rosa
  if (luna.did && luna.accessJwt && marcus.did) {
    // getKnownFollowers for Rosa as seen by Marcus
    // Both Marcus and Rosa follow Luna, so known_followers of Rosa for Marcus
    // would be Luna (if Marcus follows Rosa and Luna follows Rosa...)
    await tryEndpoint(
      result,
      "getKnownFollowers for Rosa via PDS",
      async () => {
        const body = await pds.as(marcus).raw.get(
          "app.bsky.graph.getKnownFollowers",
          { actor: rosa.did! },
        );
        assert.isTrue(Array.isArray(body.followers ?? body.subjects), "expected followers array");
        return body;
      },
      (r) => `known=${(r.followers ?? []).length}`,
    );

    // getKnownFollowers via AppView
    await tryEndpoint(
      result,
      "getKnownFollowers for Rosa via AppView",
      async () => {
        const body = await appview.as(marcus).raw.get(
          "app.bsky.graph.getKnownFollowers",
          { actor: rosa.did! },
        );
        return body;
      },
      (r) => `known=${(r.followers ?? []).length}`,
    );
  }

  // ── 2. app.bsky.graph.getListMutes ──────────────────────────────────────
  // Create a mod list and mute it to populate list-level mutes
  const listRef = await timedCall(
    result,
    "Rosa creates a mod list",
    async () => {
      return await pds.records.createRecord(
        rosa.did!,
        "app.bsky.graph.list",
        {
          $type: "app.bsky.graph.list",
          purpose: "app.bsky.graph.defs#modlist",
          name: "Test List Mute List",
          description: "For testing getListMutes",
          createdAt: now(),
        },
        rosa.accessJwt!,
        { rkey: `listmute-${Date.now()}` },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  if (listRef && luna.accessJwt) {
    // Luna mutes the list
    await tryEndpoint(
      result,
      "Luna mutes the list (muteActorList)",
      async () => {
        return await pds.as(luna).raw.post("app.bsky.graph.muteActorList", { list: listRef.uri });
      },
    );

    await new Promise((r) => setTimeout(r, 1000));

    // getListMutes should show the muted list
    await tryEndpoint(
      result,
      "getListMutes for Luna via PDS",
      async () => {
        const body = await pds.as(luna).raw.get("app.bsky.graph.getListMutes", { limit: 50 });
        assert.isTrue(Array.isArray(body.lists), "expected lists array");
        return body;
      },
      (r) => `muted_lists=${(r.lists ?? []).length}`,
    );

    // getListMutes via AppView
    await tryEndpoint(
      result,
      "getListMutes for Luna via AppView",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.graph.getListMutes", { limit: 50 });
        return body;
      },
      (r) => `muted_lists=${(r.lists ?? []).length}`,
    );

    // Clean up: unmute the list
    await tryEndpoint(
      result,
      "Luna unmutes the list (unmuteActorList)",
      async () => {
        return await pds.as(luna).raw.post("app.bsky.graph.unmuteActorList", { list: listRef.uri });
      },
    );
  }

  // ── 3. app.bsky.graph.getSuggestedFollowsByActor ───────────────────────
  // Returns suggested follows based on an actor's social graph
  if (marcus.did && marcus.accessJwt) {
    await tryEndpoint(
      result,
      "getSuggestedFollowsByActor for Marcus via PDS",
      async () => {
        const body = await pds.as(marcus).raw.get(
          "app.bsky.graph.getSuggestedFollowsByActor",
          { actor: marcus.did },
        );
        return body;
      },
      (r) => `suggestions=${(r.suggestions ?? r.actors ?? []).length}`,
    );
  }

  // ── 4. app.bsky.graph.getListsWithMembership ────────────────────────────
  // Luna creates a curated list and adds Marcus to test membership
  const curatedListRef = await timedCall(
    result,
    "Luna creates a curated list for membership check",
    async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.graph.list",
        {
          $type: "app.bsky.graph.list",
          purpose: "app.bsky.graph.defs#curatelist",
          name: "Membership Test List",
          description: "For testing getListsWithMembership",
          createdAt: now(),
        },
        luna.accessJwt!,
        { rkey: `membership-${Date.now()}` },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  if (curatedListRef && marcus.did) {
    // Add Marcus to the list
    await timedCall(
      result,
      "Add Marcus to membership list",
      async () => {
        return await pds.records.createRecord(
          luna.did!,
          "app.bsky.graph.listitem",
          {
            $type: "app.bsky.graph.listitem",
            list: curatedListRef.uri,
            subject: marcus.did,
            createdAt: now(),
          },
          luna.accessJwt!,
        );
      },
    );
  }

  await new Promise((r) => setTimeout(r, 1000));

  if (marcus.did && marcus.accessJwt) {
    await tryEndpoint(
      result,
      "getListsWithMembership for Marcus via PDS",
      async () => {
        const body = await pds.as(marcus).raw.get(
          "app.bsky.graph.getListsWithMembership",
          { actor: marcus.did },
        );
        return body;
      },
      (r) => `lists=${(r.lists ?? []).length}`,
    );

    // Also via AppView
    await tryEndpoint(
      result,
      "getListsWithMembership for Marcus via AppView",
      async () => {
        const body = await appview.as(marcus).raw.get(
          "app.bsky.graph.getListsWithMembership",
          { actor: marcus.did },
        );
        return body;
      },
      (r) => `lists=${(r.lists ?? []).length}`,
    );
  }

  // ── 5. app.bsky.graph.searchStarterPacks ────────────────────────────────
  // Create a starter pack first, then search for it
  const starterPackRef = await timedCall(
    result,
    "Luna creates a starter pack",
    async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.graph.starterpack",
        {
          $type: "app.bsky.graph.starterpack",
          name: "ATProto Devs Starter Pack",
          description: "A collection of ATProto developers to follow",
          list: curatedListRef?.uri ?? `at://${luna.did}/app.bsky.graph.list/nonexistent`,
          createdAt: now(),
        },
        luna.accessJwt!,
        { rkey: `sp-${Date.now()}` },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await new Promise((r) => setTimeout(r, 2000));

  if (starterPackRef) {
    await tryEndpoint(
      result,
      "searchStarterPacks via PDS",
      async () => {
        const body = await pds.as(luna).raw.get(
          "app.bsky.graph.searchStarterPacks",
          { q: "ATProto Devs", limit: 10 },
        );
        return body;
      },
      (r) => `packs=${(r.starterPacks ?? []).length}`,
    );

    await tryEndpoint(
      result,
      "searchStarterPacks via AppView",
      async () => {
        const body = await appview.as(luna).raw.get(
          "app.bsky.graph.searchStarterPacks",
          { q: "ATProto Devs", limit: 10 },
        );
        return body;
      },
      (r) => `packs=${(r.starterPacks ?? []).length}`,
    );
  }

  // ── 6. Auth enforcement ─────────────────────────────────────────────────
  await timedCall(
    result,
    "getListMutes rejects unauthenticated request",
    async () => {
      return await pds.raw.get("app.bsky.graph.getListMutes", { limit: 50 });
    },
    undefined,
    true,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
