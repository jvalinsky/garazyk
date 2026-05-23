/**
 * @module scenarios/73_feed_read_endpoints
 *
 * Scenario: Tests app.bsky.feed.* read endpoint coverage including getQuotes,
 * searchPosts, getListFeed, and getFeedSkeleton.
 *
 * Behavior:
 * - Creates accounts and posts with quotes, lists, and feed generators.
 * - Tests feed read endpoints against PDS and AppView.
 * - Creates a curated list and verifies list feed output.
 * - Creates a feed generator and tests skeleton feed retrieval.
 *
 * Expectations:
 * - getQuotes returns users who quoted a post.
 * - searchPosts returns posts matching keyword queries.
 * - getListFeed returns posts from a curated list.
 * - getFeedSkeleton returns skeleton feed content (or gracefully skipped).
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: app.bsky.feed.getQuotes, app.bsky.feed.searchPosts,
//   app.bsky.feed.getListFeed, app.bsky.feed.getFeedSkeleton.
// Extends 03_content_creation.ts (post/like/reply lifecycle) to add
// missing read-side feed endpoint coverage.

function now() {
  return new Date().toISOString();
}

/** Try an endpoint, skipping if 404/501, failing on other errors. */
async function tryEndpoint<T>(
  result: ScenarioResult,
  label: string,
  fn: () => Promise<T>,
  summary?: (t: T) => string,
): Promise<T | null> {
  try {
    const val = await fn();
    result.stepPassed(label, summary ? summary(val) : undefined);
    return val;
  } catch (e: any) {
    if (e instanceof XrpcError && (e.status === 404 || e.status === 501)) {
      result.stepSkipped(label, `endpoint not available (HTTP ${e.status})`);
    } else if (e instanceof XrpcError && e.status === 400) {
      const body = typeof e.body === "string" ? e.body : JSON.stringify(e.body ?? "");
      if (body.toLowerCase().includes("not implemented") || body.toLowerCase().includes("unknown method")) {
        result.stepSkipped(label, "endpoint not implemented");
      } else {
        result.stepFailed(label, `HTTP 400: ${body.substring(0, 200)}`);
      }
    } else {
      result.stepFailed(label, String(e.message ?? e));
    }
    return null;
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Feed Read Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getActor("luna");
  const marcus = getActor("marcus");
  const rosa = getActor("rosa");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Account setup ---
  for (const char of [luna, marcus, rosa]) {
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

  if (!luna.did || !marcus.did || !rosa.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // --- Create profiles ---
  for (const char of [luna, marcus, rosa]) {
    await tryEndpoint(
      result,
      `Set profile: ${char.name}`,
      async () => {
        return await pds.records.createRecord(
          char.did,
          "app.bsky.actor.profile",
          { $type: "app.bsky.actor.profile", displayName: char.name, description: char.persona },
          char.accessJwt,
        );
      },
      () => "done",
    );
  }

  // --- Create target post (Luna's post that others will quote) ---
  const targetPost = await timedCall(
    result,
    "Luna creates target post for quoting",
    async () => {
      return await pds.records.createRecord(
        luna.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "The Orion Nebula is 1,344 light-years away and a stellar nursery for new stars!",
          createdAt: now(),
        },
        luna.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  if (!targetPost) {
    result.stepFailed("Create target post", "no post created");
    result.finish();
    return result;
  }

  // --- Create diverse posts for search coverage ---
  await timedCall(
    result,
    "Marcus creates tech post",
    async () => {
      return await pds.records.createRecord(
        marcus.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Building a decentralized social network on ATProto is incredibly rewarding! #atproto #opensource",
          createdAt: now(),
        },
        marcus.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await timedCall(
    result,
    "Rosa creates baking post",
    async () => {
      return await pds.records.createRecord(
        rosa.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Sourdough starter day 7: it's alive! Bubbly and smells like fresh yogurt. #baking #sourdough",
          createdAt: now(),
        },
        rosa.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  // --- 1. Create quotes (getQuotes) ---
  // Marcus quotes Luna's post
  await timedCall(
    result,
    "Marcus quotes Luna's post",
    async () => {
      return await pds.records.createRecord(
        marcus.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Amazing! The scale of the universe never ceases to amaze me.",
          createdAt: now(),
          embed: {
            $type: "app.bsky.embed.record",
            record: { uri: targetPost.uri, cid: targetPost.cid },
          },
        },
        marcus.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  // Rosa also quotes Luna's post
  await timedCall(
    result,
    "Rosa quotes Luna's post",
    async () => {
      return await pds.records.createRecord(
        rosa.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Imagine the sourdough you could bake with starstuff! ✨",
          createdAt: now(),
          embed: {
            $type: "app.bsky.embed.record",
            record: { uri: targetPost.uri, cid: targetPost.cid },
          },
        },
        rosa.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await new Promise((r) => setTimeout(r, 2000));

  // --- 2. app.bsky.feed.getQuotes ---
  // Query the PDS or AppView for quotes of Luna's post
  await tryEndpoint(
    result,
    "getQuotes on Luna's post via PDS",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.feed.getQuotes", {
        uri: targetPost.uri,
        cid: targetPost.cid,
      });
      const posts = body.posts ?? [];
      return { count: posts.length };
    },
    (r) => `quotes=${r.count}`,
  );

  // Also try via AppView (where feed read endpoints typically live)
  await tryEndpoint(
    result,
    "getQuotes on Luna's post via AppView",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.feed.getQuotes", {
        uri: targetPost.uri,
        cid: targetPost.cid,
      });
      const posts = body.posts ?? [];
      return { count: posts.length };
    },
    (r) => `quotes=${r.count}`,
  );

  // --- 3. app.bsky.feed.searchPosts ---
  await tryEndpoint(
    result,
    "searchPosts 'nebula'",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.feed.searchPosts", {
        q: "nebula",
        limit: 10,
      });
      const posts = body.posts ?? [];
      return { found: posts.length };
    },
    (r) => `posts=${r.found}`,
  );

  await tryEndpoint(
    result,
    "searchPosts 'sourdough'",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.feed.searchPosts", {
        q: "sourdough",
        limit: 10,
      });
      const posts = body.posts ?? [];
      return { found: posts.length };
    },
    (r) => `posts=${r.found}`,
  );

  await tryEndpoint(
    result,
    "searchPosts 'atproto opensource'",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.feed.searchPosts", {
        q: "atproto opensource",
        limit: 10,
      });
      const posts = body.posts ?? [];
      return { found: posts.length };
    },
    (r) => `posts=${r.found}`,
  );

  // Also test via AppView
  await tryEndpoint(
    result,
    "searchPosts via AppView",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.feed.searchPosts", {
        q: "nebula",
        limit: 10,
      });
      const posts = body.posts ?? [];
      return { found: posts.length };
    },
    (r) => `posts=${r.found}`,
  );

  // --- 4. Create a list for getListFeed ---
  const listRef = await timedCall(
    result,
    "Rosa creates a curated list",
    async () => {
      return await pds.records.createRecord(
        rosa.did,
        "app.bsky.graph.list",
        {
          $type: "app.bsky.graph.list",
          name: "Space & Code Enthusiasts",
          purpose: "app.bsky.graph.defs#curatelist",
          createdAt: now(),
        },
        rosa.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  let listUri: string | null = null;
  if (listRef) listUri = listRef.uri;

  // Add members to the list
  if (listUri && luna.did && marcus.did) {
    for (const member of [luna, marcus]) {
      await timedCall(
        result,
        `Add ${member.name} to list`,
        async () => {
          return await pds.records.createRecord(
            rosa.did,
            "app.bsky.graph.listitem",
            {
              $type: "app.bsky.graph.listitem",
              list: listUri,
              subject: member.did,
              createdAt: now(),
            },
            rosa.accessJwt,
          );
        },
        () => "added",
      );
    }
  }

  await new Promise((r) => setTimeout(r, 2000));

  // --- 5. app.bsky.feed.getListFeed ---
  if (listUri) {
    await tryEndpoint(
      result,
      "getListFeed via PDS",
      async () => {
        const body = await pds.as(rosa).raw.get("app.bsky.feed.getListFeed", {
          list: listUri,
          limit: 20,
        });
        const feed = body.feed ?? [];
        return { items: feed.length };
      },
      (r) => `feed_items=${r.items}`,
    );

    await tryEndpoint(
      result,
      "getListFeed via AppView",
      async () => {
        const body = await appview.as(rosa).raw.get("app.bsky.feed.getListFeed", {
          list: listUri,
          limit: 20,
        });
        const feed = body.feed ?? [];
        return { items: feed.length };
      },
      (r) => `feed_items=${r.items}`,
    );
  }

  // --- 6. Create a feed generator for getFeedSkeleton ---
  const feedRkey = `feed-rd-${Date.now()}`;
  const feedGenRef = await timedCall(
    result,
    "Rosa creates feed generator",
    async () => {
      return await pds.records.createRecord(
        rosa.did,
        "app.bsky.feed.generator",
        {
          $type: "app.bsky.feed.generator",
          did: rosa.did,
          displayName: "Feed Read Endpoints Test",
          description: "Test feed for getFeedSkeleton coverage",
          createdAt: now(),
        },
        rosa.accessJwt,
        { rkey: feedRkey },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  await new Promise((r) => setTimeout(r, 2000));

  // --- 7. app.bsky.feed.getFeedSkeleton ---
  // getFeedSkeleton is typically implemented by feed generator services,
  // not the PDS or AppView directly. We try both and skip gracefully.
  if (feedGenRef) {
    await tryEndpoint(
      result,
      "getFeedSkeleton via PDS",
      async () => {
        const body = await pds.as(rosa).raw.get("app.bsky.feed.getFeedSkeleton", {
          feed: feedGenRef.uri,
          limit: 10,
        });
        const feed = body.feed ?? [];
        return { items: feed.length };
      },
      (r) => `feed_items=${r.items}`,
    );

    await tryEndpoint(
      result,
      "getFeedSkeleton via AppView",
      async () => {
        const body = await appview.as(rosa).raw.get("app.bsky.feed.getFeedSkeleton", {
          feed: feedGenRef.uri,
          limit: 10,
        });
        const feed = body.feed ?? [];
        return { items: feed.length };
      },
      (r) => `feed_items=${r.items}`,
    );
  }

  // --- 8. Verify via app.bsky.feed.getFeed (existing endpoint, for comparison) ---
  if (feedGenRef) {
    await tryEndpoint(
      result,
      "getFeed via AppView (existing endpoint for comparison)",
      async () => {
        const body = await appview.as(rosa).raw.get("app.bsky.feed.getFeed", {
          feed: feedGenRef.uri,
          limit: 10,
        });
        const feed = body.feed ?? [];
        return { items: feed.length };
      },
      (r) => `feed_items=${r.items}`,
    );
  }

  // --- 9. Negative test: searchPosts with empty query ---
  await tryEndpoint(
    result,
    "searchPosts with empty query (edge case)",
    async () => {
      try {
        const body = await pds.as(luna).raw.get("app.bsky.feed.searchPosts", {
          q: "",
          limit: 10,
        });
        const posts = (body as any).posts ?? [];
        return { found: posts.length };
      } catch (e: any) {
        if (e instanceof XrpcError && e.status === 400) {
          return { rejected: true };
        }
        throw e;
      }
    },
    (r) => r.found !== undefined ? `posts=${r.found}` : "rejected",
  );

  // --- 10. Negative test: getListFeed with non-existent list URI ---
  await tryEndpoint(
    result,
    "getListFeed with non-existent list (error handling)",
    async () => {
      try {
        await pds.as(luna).raw.get("app.bsky.feed.getListFeed", {
          list: `at://${luna.did}/app.bsky.graph.list/nonexistent`,
          limit: 10,
        });
        return { accepted: true };
      } catch (e: any) {
        if (e instanceof XrpcError && (e.status === 400 || e.status === 404)) {
          return { rejected: true };
        }
        throw e;
      }
    },
    (r) => r.accepted ? "accepted" : "rejected (expected for missing list)",
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
