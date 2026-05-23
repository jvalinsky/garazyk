/**
 * @module scenarios/80_feed_interaction_endpoints
 *
 * Scenario: Feed interaction & discovery endpoints.
 *
 * Behavior:
 * - Creates accounts and sets up profiles with posts.
 * - Tests app.bsky.feed.getActorFeeds (list feeds created by an actor).
 * - Tests app.bsky.feed.getSuggestedFeeds (discoverable feeds).
 * - Tests app.bsky.feed.getFeedGenerator (single feed generator metadata).
 * - Tests app.bsky.feed.sendInteractions (feed interaction events).
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
  const result = new ScenarioResult("Feed Interaction & Discovery Endpoints");
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

  const names = ["luna", "marcus"];
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
  if (active.length < 2) {
    result.stepFailed("Account setup", `only ${active.length} accounts`);
    result.finish();
    return result;
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");

  // Set up profiles
  for (const char of [luna, marcus]) {
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

  // Luna creates posts
  const postRef = await timedCall(
    result,
    "Luna creates a post",
    async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.feed.post",
        { $type: "app.bsky.feed.post", text: "Discovering new feeds on ATProto!", createdAt: now() },
        luna.accessJwt!,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await new Promise((r) => setTimeout(r, 1000));

  // ── 1. app.bsky.feed.getActorFeeds ─────────────────────────────────────
  // List feed generators created by an actor. Luna creates a feed generator first.
  const feedRkey = `feed-80-${Date.now()}`;
  const feedGenRef = await timedCall(
    result,
    "Luna creates a feed generator record",
    async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.feed.generator",
        {
          $type: "app.bsky.feed.generator",
          did: luna.did!,
          displayName: "Luna's Discovery Feed",
          description: "Discover interesting content across the network",
          createdAt: now(),
        },
        luna.accessJwt!,
        { rkey: feedRkey },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await new Promise((r) => setTimeout(r, 2000));

  // getActorFeeds via PDS
  if (luna.did) {
    await tryEndpoint(
      result,
      "getActorFeeds via PDS",
      async () => {
        const body = await pds.as(luna).raw.get("app.bsky.feed.getActorFeeds", { actor: luna.did });
        const feeds = body.feeds ?? [];
        assert.isTrue(Array.isArray(feeds), "expected feeds array");
        return feeds;
      },
      (f) => `feeds=${f.length}`,
    );

    // getActorFeeds via AppView
    await tryEndpoint(
      result,
      "getActorFeeds via AppView",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.feed.getActorFeeds", { actor: luna.did });
        const feeds = body.feeds ?? [];
        assert.isTrue(Array.isArray(feeds), "expected feeds array");
        return feeds;
      },
      (f) => `feeds=${f.length}`,
    );
  }

  // getActorFeeds with nonexistent actor (error handling)
  await tryEndpoint(
    result,
    "getActorFeeds with nonexistent DID",
    async () => {
      const body = await pds.as(luna).raw.get(
        "app.bsky.feed.getActorFeeds",
        { actor: "did:plc:nonexistent0000000000" },
      );
      const feeds = body.feeds ?? [];
      return { feeds: feeds.length };
    },
    (r) => `feeds=${r.feeds}`,
  );

  // ── 2. app.bsky.feed.getFeedGenerator ──────────────────────────────────
  if (feedGenRef) {
    await tryEndpoint(
      result,
      "getFeedGenerator via AppView (single generator)",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.feed.getFeedGenerator", { feed: feedGenRef.uri });
        // Response may contain view + isOnline + isValid
        const view = body.view;
        assert.isTrue(!!view, "expected feed generator view");
        return { did: view?.did };
      },
      (r) => `did=${r.did}`,
    );
  }

  // ── 3. app.bsky.feed.getSuggestedFeeds ─────────────────────────────────
  await tryEndpoint(
    result,
    "getSuggestedFeeds",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.feed.getSuggestedFeeds", {});
      const feeds = body.feeds ?? [];
      assert.isTrue(Array.isArray(feeds), "expected feeds array");
      return feeds;
    },
    (f) => `feeds=${f.length}`,
  );

  await tryEndpoint(
    result,
    "getSuggestedFeeds via AppView",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.feed.getSuggestedFeeds", {});
      const feeds = body.feeds ?? [];
      assert.isTrue(Array.isArray(feeds), "expected feeds array");
      return feeds;
    },
    (f) => `feeds=${f.length}`,
  );

  // ── 4. app.bsky.feed.sendInteractions ──────────────────────────────────
  // Send interaction events for feed engagement tracking.
  if (postRef && marcus.accessJwt) {
    await tryEndpoint(
      result,
      "sendInteractions with like interaction",
      async () => {
        return await appview.as(marcus).raw.post(
          "app.bsky.feed.sendInteractions",
          {
            interactions: [
              {
                item: postRef.uri,
                event: "app.bsky.feed.defs#interactionLike",
                feedContext: "test-feed-context",
              },
            ],
          },
        );
      },
    );
  }

  // ── 5. Auth enforcement ─────────────────────────────────────────────────
  await timedCall(
    result,
    "getSuggestedFeeds rejects unauthenticated request",
    async () => {
      return await pds.raw.get("app.bsky.feed.getSuggestedFeeds", {});
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
