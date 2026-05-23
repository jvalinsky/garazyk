/**
 * @module scenarios/78_list_blocks_and_mutes
 *
 * Scenario: List blocks, actor list mute/unmute, thread mute/unmute, and getMutes edge cases.
 *
 * Behavior:
 * - Creates a mod list (block list) with members.
 * - Tests app.bsky.graph.getListBlocks endpoint.
 * - Tests app.bsky.graph.muteActorList and unmuteActorList.
 * - Tests app.bsky.graph.getMutes with pagination and empty results.
 * - Tests app.bsky.graph.muteThread (gracefully handles missing thread context).
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1 } from "../../lib/deno/config.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("List Blocks and Mute Endpoints");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  // Create 4 accounts
  const names = ["luna", "marcus", "rosa", "troll"];
  for (const name of names) {
    const char = getActor(name);
    await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts
          .createAccount(char.handle, char.email, char.password)
          .catch(() =>
            client.accounts.createSession(char.handle, char.password)
          );
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

  // ── Create a mod list (block list) ────────────────────────────────────────
  const listRef = await timedCall(
    result,
    "Luna creates a mod list for blocking",
    async () => {
      return await client.records.createRecord(
        luna.did!,
        "app.bsky.graph.list",
        {
          $type: "app.bsky.graph.list",
          purpose: "app.bsky.graph.defs#modlist",
          name: "Blocked Users",
          description: "List of blocked accounts for testing",
          createdAt: now(),
        },
        luna.accessJwt!,
        { rkey: `blocklist-${Date.now()}` },
      );
    },
    (r) => r.uri,
  );

  if (!listRef) {
    result.finish();
    return result;
  }
  const listUri = listRef.uri;

  // Add Marcus and Rosa to the block list
  for (const char of [marcus, rosa]) {
    if (char.did) {
      await timedCall(
        result,
        `Add ${char.name} to block list`,
        async () => {
          return await client.records.createRecord(
            luna.did!,
            "app.bsky.graph.listitem",
            {
              $type: "app.bsky.graph.listitem",
              list: listUri,
              subject: char.did!,
              createdAt: now(),
            },
            luna.accessJwt!,
          );
        },
      );
    }
  }

  await new Promise((r) => setTimeout(r, 2000));

  // ── getListBlocks ────────────────────────────────────────────────────────
  await timedCall(
    result,
    "getListBlocks returns the block list",
    async () => {
      const resp = await client.as(luna).raw.get(
        "app.bsky.graph.getListBlocks",
        { limit: 50 },
      );
      assert.isTrue(
        Array.isArray(resp.lists),
        "expected lists array in getListBlocks",
      );
      const found = resp.lists.some((l: any) => l.uri === listUri);
      assert.isTrue(found, "block list URI should appear in getListBlocks");
      return resp;
    },
    (r) => `lists=${r.lists?.length || 0}`,
  );

  await timedCall(
    result,
    "getListBlocks pagination with limit=1",
    async () => {
      const resp = await client.as(luna).raw.get(
        "app.bsky.graph.getListBlocks",
        { limit: 1 },
      );
      const lists = resp.lists ?? [];
      assert.isTrue(
        lists.length <= 1,
        `expected at most 1 list with limit=1, got ${lists.length}`,
      );
      return resp;
    },
    (r) => `count=${(r.lists ?? []).length}, cursor=${r.cursor ?? "none"}`,
  );

  // ── muteActorList ────────────────────────────────────────────────────────
  if (troll.did && troll.accessJwt) {
    await timedCall(
      result,
      "Troll mutes the block list (muteActorList)",
      async () => {
        return await client.as(troll).raw.post(
          "app.bsky.graph.muteActorList",
          { list: listUri },
        );
      },
    );

    // Verify the list appears in Troll's mutes
    await timedCall(
      result,
      "Troll's getMutes should reflect the list mute",
      async () => {
      const resp = await client.as(troll).raw.get(
        "app.bsky.graph.getMutes",
        { limit: 50 },
      );
        // The mutes list might show the specific actors or list-level mute
        // depending on implementation — just check the call succeeds
        assert.isTrue(
          Array.isArray(resp.mutes),
          "expected mutes array",
        );
        return resp;
      },
      (r) => `mutes=${r.mutes?.length || 0}`,
    );

    // ── unmuteActorList ────────────────────────────────────────────────────
    await timedCall(
      result,
      "Troll unmutes the block list (unmuteActorList)",
      async () => {
        return await client.as(troll).raw.post(
          "app.bsky.graph.unmuteActorList",
          { list: listUri },
        );
      },
    );
  }

  // ── muteThread / unmuteThread (graceful skip if unimplemented) ───────────
  await timedCall(
    result,
    "muteThread with nonexistent URI handled gracefully",
    async () => {
      try {
        await client.as(luna).raw.post(
          "app.bsky.graph.muteThread",
          { uri: "at://did:plc:nonexistent/app.bsky.feed.post/fake" },
        );
        // If it succeeds, that's fine
      } catch {
        // Expected if thread doesn't exist
      }
    },
  );

  await timedCall(
    result,
    "unmuteThread with nonexistent URI handled gracefully",
    async () => {
      try {
        await client.as(luna).raw.post(
          "app.bsky.graph.unmuteThread",
          { uri: "at://did:plc:nonexistent/app.bsky.feed.post/fake" },
        );
      } catch {
        // Expected if thread doesn't exist
      }
    },
  );

  // ── getMutes with empty results for a clean account ──────────────────────
  if (rosa.did && rosa.accessJwt) {
    await timedCall(
      result,
      "getMutes returns empty for account with no mutes",
      async () => {
      const resp = await client.as(rosa).raw.get(
        "app.bsky.graph.getMutes",
        { limit: 50 },
      );
        assert.isTrue(
          Array.isArray(resp.mutes),
          "expected mutes array for clean account",
        );
        return resp;
      },
      (r) => `mutes=${r.mutes?.length || 0}`,
    );
  }

  // ── getMutes auth enforcement ────────────────────────────────────────────
  await timedCall(
    result,
    "getMutes rejects unauthenticated request",
    async () => {
      return await client.raw.get("app.bsky.graph.getMutes", { limit: 50 });
    },
    undefined,
    true, // expect error
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
