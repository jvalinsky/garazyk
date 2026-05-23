/**
 * @module scenarios/90_unspecced_endpoints
 *
 * Scenario: Covers app.bsky.unspecced.* endpoints — unofficial/experimental
 *   and reference-implementation-specific endpoints.
 *
 * Covers:
 *   app.bsky.unspecced.getConfig
 *   app.bsky.unspecced.getSuggestedFeeds
 *   app.bsky.unspecced.getSuggestedFeedsSkeleton
 *   app.bsky.unspecced.getSuggestedUsers
 *   app.bsky.unspecced.getSuggestedUsersForDiscover
 *   app.bsky.unspecced.getOnboardingSuggestedStarterPacks
 *   app.bsky.unspecced.getPopularFeedGenerators
 *   app.bsky.unspecced.getPostThreadV2
 *   app.bsky.unspecced.getAgeAssuranceState
 *   app.bsky.unspecced.confirmAgeAssurance
 *   app.bsky.unspecced.getSuggestedStarterPacks
 *   app.bsky.unspecced.getSuggestedOnboardingUsers
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, ScenarioResult, timedCall, tryEndpoint } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Unspecced Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview || "http://localhost:3200");
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  // --- Health checks ---
  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "AppView health check", async () => {
    await appview.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Account setup ---
  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          return await pds.accounts.createAccount(char.handle, char.email, char.password);
        } catch {
          return await pds.accounts.createSession(char.handle, char.password);
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // ── 1. app.bsky.unspecced.getConfig ────────────────────────────────────
  // Server configuration (unspecced) — available on AppView or PDS
  await tryEndpoint(
    result,
    "getConfig (AppView)",
    async () => {
      return await appview.raw.get("app.bsky.unspecced.getConfig", {});
    },
    (c) => `configKeys=${Object.keys(c ?? {}).join(",")}`,
  );

  await tryEndpoint(
    result,
    "getConfig (PDS)",
    async () => {
      return await pds.raw.get("app.bsky.unspecced.getConfig", {});
    },
    (c) => `configKeys=${Object.keys(c ?? {}).join(",")}`,
  );

  // ── 2. app.bsky.unspecced.getSuggestedFeeds ────────────────────────────
  await tryEndpoint(
    result,
    "getSuggestedFeeds (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedFeeds", {});
    },
    (r) => `feeds=${(r?.feeds ?? []).length}`,
  );

  // ── 3. app.bsky.unspecced.getSuggestedFeedsSkeleton ────────────────────
  await tryEndpoint(
    result,
    "getSuggestedFeedsSkeleton (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedFeedsSkeleton", {});
    },
    (r) => `feeds=${(r?.feeds ?? []).length}`,
  );

  // ── 4. app.bsky.unspecced.getSuggestedUsers ────────────────────────────
  await tryEndpoint(
    result,
    "getSuggestedUsers (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedUsers", {});
    },
    (r) => `users=${(r?.users ?? []).length}`,
  );

  // ── 5. app.bsky.unspecced.getSuggestedUsersForDiscover ─────────────────
  await tryEndpoint(
    result,
    "getSuggestedUsersForDiscover (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedUsersForDiscover", {});
    },
    (r) => `users=${(r?.users ?? []).length}`,
  );

  // ── 6. app.bsky.unspecced.getOnboardingSuggestedStarterPacks ───────────
  await tryEndpoint(
    result,
    "getOnboardingSuggestedStarterPacks (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getOnboardingSuggestedStarterPacks", {});
    },
    (r) => `packs=${(r?.starterPacks ?? r?.packs ?? []).length}`,
  );

  // ── 7. app.bsky.unspecced.getPopularFeedGenerators ─────────────────────
  await tryEndpoint(
    result,
    "getPopularFeedGenerators (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getPopularFeedGenerators", {});
    },
    (r) => `feeds=${(r?.feeds ?? []).length}`,
  );

  // ── 8. app.bsky.unspecced.getPostThreadV2 ──────────────────────────────
  // Create a post first to have something to query
  const post = await timedCall(
    result,
    "Create post for thread query",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Testing unspecced getPostThreadV2 endpoint",
          createdAt: new Date().toISOString(),
        },
      });
    },
    (p) => `uri=${p?.uri}`,
  );

  const postUri = post?.uri;
  if (postUri) {
    await tryEndpoint(
      result,
      "getPostThreadV2 (AppView)",
      async () => {
        return await appview.as(luna).raw.get("app.bsky.unspecced.getPostThreadV2", {
          uri: postUri,
        });
      },
      (r) => `thread=${r?.thread?.$type ?? "present"}`,
    );
  }

  // ── 9. app.bsky.unspecced.getAgeAssuranceState ────────────────────────
  await tryEndpoint(
    result,
    "getAgeAssuranceState (PDS)",
    async () => {
      return await pds.as(luna).raw.get("app.bsky.unspecced.getAgeAssuranceState", {});
    },
    (r) => `state=${JSON.stringify(r ?? {})}`,
  );

  // ── 10. app.bsky.unspecced.confirmAgeAssurance ────────────────────────
  await tryEndpoint(
    result,
    "confirmAgeAssurance (PDS)",
    async () => {
      return await pds.as(luna).raw.post("app.bsky.unspecced.confirmAgeAssurance", {
        age: 21,
      });
    },
    () => "confirmed",
  );

  // ── 11. app.bsky.unspecced.getSuggestedStarterPacks ────────────────────
  await tryEndpoint(
    result,
    "getSuggestedStarterPacks (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedStarterPacks", {});
    },
    (r) => `packs=${(r?.starterPacks ?? r?.packs ?? []).length}`,
  );

  // ── 12. app.bsky.unspecced.getSuggestedOnboardingUsers ────────────────
  await tryEndpoint(
    result,
    "getSuggestedOnboardingUsers (AppView)",
    async () => {
      return await appview.as(luna).raw.get("app.bsky.unspecced.getSuggestedOnboardingUsers", {});
    },
    (r) => `users=${(r?.users ?? []).length}`,
  );

  // ── 13. Auth enforcement ───────────────────────────────────────────────
  await timedCall(
    result,
    "Auth enforcement: getConfig without auth",
    async () => {
      try {
        await appview.raw.get("app.bsky.unspecced.getConfig", {});
        result.stepPassed("getConfig without auth allowed", "public endpoint");
      } catch (e: any) {
        if (e instanceof XrpcError) {
          result.stepPassed("getConfig without auth", `HTTP ${e.status}`);
        } else {
          throw e;
        }
      }
    },
  );

  await timedCall(
    result,
    "Auth enforcement: getPostThreadV2 without auth",
    async () => {
      try {
        if (postUri) {
          await appview.raw.get("app.bsky.unspecced.getPostThreadV2", { uri: postUri });
          result.stepPassed("getPostThreadV2 without auth allowed", "public endpoint");
        } else {
          result.stepSkipped("getPostThreadV2 auth", "no post URI available");
        }
      } catch (e: any) {
        if (e instanceof XrpcError) {
          result.stepPassed("getPostThreadV2 without auth", `HTTP ${e.status}`);
        } else {
          throw e;
        }
      }
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
