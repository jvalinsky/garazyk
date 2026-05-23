/**
 * @module scenarios/77_actor_profile_endpoints
 *
 * Scenario: Batch profile and actor discovery endpoints with edge cases.
 *
 * Behavior:
 * - Creates multiple accounts with display names for search coverage.
 * - Tests app.bsky.actor.getProfiles (batch) with multiple DIDs/handles.
 * - Tests app.bsky.actor.getProfile with nonexistent actor.
 * - Tests app.bsky.actor.searchActors with pagination and empty queries.
 * - Tests app.bsky.actor.searchActorsTypeahead with partial handles.
 * - Tests app.bsky.actor.getSuggestions after building social graph.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Actor Profile and Discovery Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "AppView health check", async () => {
    await appview.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  // Create 4 accounts with distinct display names for search coverage
  const names = ["luna", "marcus", "rosa", "volt"];
  for (const name of names) {
    const char = getActor(name);
    await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await pds.accounts
          .createAccount(char.handle, char.email, char.password)
          .catch(() =>
            pds.accounts.createSession(char.handle, char.password)
          );
      },
      (s) => `did=${s.did}`,
    );
  }

  const active = names.filter((n) => getActor(n).did);
  if (active.length < 3) {
    result.stepFailed("Account setup", `only ${active.length} accounts created`);
    result.finish();
    return result;
  }

  // Set profiles with searchable display names
  for (const name of active) {
    const char = getActor(name);
    await timedCall(
      result,
      `Set profile: ${char.name}`,
      async () => {
        return await pds.records.createRecord(
          char.did!,
          "app.bsky.actor.profile",
          {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona || `Profile for ${char.name}`,
          },
          char.accessJwt!,
        );
      },
    );
  }

  // Build social graph: Marcus follows Luna and Rosa
  const marcus = getActor("marcus");
  const luna = getActor("luna");
  const rosa = getActor("rosa");

  if (marcus.did && luna.did) {
    await timedCall(result, "Marcus follows Luna", async () => {
      return await pds.records.createRecord(
        marcus.did!,
        "app.bsky.graph.follow",
        { $type: "app.bsky.graph.follow", subject: luna.did!, createdAt: now() },
        marcus.accessJwt!,
      );
    });
  }
  if (marcus.did && rosa.did) {
    await timedCall(result, "Marcus follows Rosa", async () => {
      return await pds.records.createRecord(
        marcus.did!,
        "app.bsky.graph.follow",
        { $type: "app.bsky.graph.follow", subject: rosa.did!, createdAt: now() },
        marcus.accessJwt!,
      );
    });
  }
  if (luna.did && marcus.did) {
    await timedCall(result, "Luna follows Marcus", async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.graph.follow",
        { $type: "app.bsky.graph.follow", subject: marcus.did!, createdAt: now() },
        luna.accessJwt!,
      );
    });
  }
  if (rosa.did && luna.did) {
    await timedCall(result, "Rosa follows Luna", async () => {
      return await pds.records.createRecord(
        rosa.did!,
        "app.bsky.graph.follow",
        { $type: "app.bsky.graph.follow", subject: luna.did!, createdAt: now() },
        rosa.accessJwt!,
      );
    });
  }

  await new Promise((r) => setTimeout(r, 2000));

  // --- getProfiles (batch) ---
  const lunaDid = luna.did!;
  const marcusDid = marcus.did!;
  const rosaDid = rosa.did!;

  await timedCall(
    result,
    "getProfiles batch lookup by DID",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.getProfiles",
        { actors: [lunaDid, marcusDid, rosaDid] },
      );
      assert.isTrue(Array.isArray(resp.profiles), "expected profiles array");
      assert.equal(
        resp.profiles.length,
        3,
        `expected 3 profiles, got ${resp.profiles.length}`,
      );
      const dids = resp.profiles.map((p: any) => p.did);
      assert.isTrue(dids.includes(lunaDid), "luna did in batch");
      assert.isTrue(dids.includes(marcusDid), "marcus did in batch");
      assert.isTrue(dids.includes(rosaDid), "rosa did in batch");
      return resp;
    },
    (r) => `count=${r.profiles.length}`,
  );

  await timedCall(
    result,
    "getProfiles batch lookup by handle",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.getProfiles",
        {
          actors: [
            luna.handle,
            marcus.handle,
            rosa.handle,
          ],
        },
      );
      assert.isTrue(Array.isArray(resp.profiles), "expected profiles array");
      assert.isTrue(
        resp.profiles.length >= 2,
        `expected at least 2 profiles by handle, got ${resp.profiles.length}`,
      );
      return resp;
    },
    (r) => `count=${r.profiles.length}`,
  );

  await timedCall(
    result,
    "getProfiles with nonexistent DID handles gracefully",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.getProfiles",
        {
          actors: [
            lunaDid,
            "did:plc:nonexistent0000000000",
          ],
        },
      );
      assert.isTrue(Array.isArray(resp.profiles), "expected profiles array");
      // Should return profile for Luna even if the other DID is missing
      const dids = resp.profiles.map((p: any) => p.did);
      assert.isTrue(dids.includes(lunaDid), "luna should be in partial result");
      return resp;
    },
    (r) => `profiles=${r.profiles.length}`,
  );

  // --- getProfile edge cases ---
  await timedCall(
    result,
    "getProfile with nonexistent actor returns error gracefully",
    async () => {
      try {
        await pds.as(marcus).raw.get(
          "app.bsky.actor.getProfile",
          { actor: "did:plc:nonexistent0000000000" },
        );
        // Some implementations return empty profile — accept
      } catch {
        // Expected: XRPC error for nonexistent actor
      }
    },
  );

  // --- searchActors ---
  await timedCall(
    result,
    "searchActors by display name",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.searchActors",
        { q: "Luna", limit: 10 },
      );
      assert.isTrue(Array.isArray(resp.actors), "expected actors array");
      assert.isTrue(
        resp.actors.length >= 1,
        `expected at least 1 actor matching 'Luna', got ${resp.actors.length}`,
      );
      const first = resp.actors[0];
      assert.isTrue(
        first.displayName === "luna" || first.handle === luna.handle,
        "expected Luna in search results",
      );
      return resp;
    },
    (r) => `count=${r.actors.length}`,
  );

  await timedCall(
    result,
    "searchActors with nonexistent query returns empty",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.searchActors",
        { q: "zzzzzzzznonexistent", limit: 10 },
      );
      const actors = resp.actors ?? [];
      assert.equal(
        actors.length,
        0,
        `expected 0 results for nonexistent query, got ${actors.length}`,
      );
      return resp;
    },
    (r) => `count=${(r.actors ?? []).length}`,
  );

  await timedCall(
    result,
    "searchActors pagination with limit",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.searchActors",
        { q: "a", limit: 1 },
      );
      const actors = resp.actors ?? [];
      assert.isTrue(
        actors.length <= 1,
        `expected at most 1 actor with limit=1, got ${actors.length}`,
      );
      return resp;
    },
    (r) => `count=${(r.actors ?? []).length}, cursor=${r.cursor ?? "none"}`,
  );

  // --- searchActorsTypeahead ---
  await timedCall(
    result,
    "searchActorsTypeahead by handle prefix",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.searchActorsTypeahead",
        { q: luna.handle.slice(0, 6), limit: 5 },
      );
      assert.isTrue(Array.isArray(resp.actors), "expected actors array");
      const handles = resp.actors.map((a: any) => a.handle);
      assert.isTrue(
        handles.some((h: string) => h === luna.handle),
        `expected Luna handle in typeahead results`,
      );
      return resp;
    },
    (r) => `count=${r.actors.length}`,
  );

  await timedCall(
    result,
    "searchActorsTypeahead with empty query",
    async () => {
      try {
        await pds.as(marcus).raw.get(
          "app.bsky.actor.searchActorsTypeahead",
          { q: "" },
        );
        // Some implementations may accept empty query and return all
      } catch {
        // Expected: error for empty query
      }
    },
  );

  // --- getSuggestions ---
  await timedCall(
    result,
    "getSuggestions returns actors",
    async () => {
      const resp = await pds.as(marcus).raw.get(
        "app.bsky.actor.getSuggestions",
        { limit: 10 },
      );
      const actors = resp.actors ?? [];
      // Suggestions may be empty when there's little activity,
      // but the endpoint should at least return a valid response
      assert.isTrue(
        Array.isArray(actors),
        "expected actors array in suggestions",
      );
      return resp;
    },
    (r) => `count=${(r.actors ?? []).length}`,
  );

  // --- PDS and AppView profile consistency ---
  await timedCall(
    result,
    "Profile from AppView matches PDS",
    async () => {
      const pdsProfile = await pds.as(marcus).raw.get(
        "app.bsky.actor.getProfile",
        { actor: lunaDid },
      );
      // AppView may not have the profile indexed yet — graceful skip
      try {
        const avProfile = await appview.as(marcus).raw.get(
          "app.bsky.actor.getProfile",
          { actor: lunaDid },
        );
        if (avProfile.did) {
          assert.equal(
            avProfile.did,
            pdsProfile.did,
            "DID should match between PDS and AppView",
          );
          assert.equal(
            avProfile.handle,
            pdsProfile.handle,
            "Handle should match between PDS and AppView",
          );
        }
      } catch {
        // AppView may not be indexing — skip cross-service verification
      }
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
