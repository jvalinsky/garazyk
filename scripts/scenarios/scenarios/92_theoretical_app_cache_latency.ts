/**
 * @module scenarios/92_theoretical_app_cache_latency
 *
 * Scenario: Models a small app rendering post cards directly from PDS reads
 * versus through Beskid and Mikrus caches.
 */

import { OperationTimer, PhaseTimer } from "@garazyk/hamownia";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

const MIKRUS_URL = Deno.env.get("MIKRUS_URL") ||
  SERVICE_URLS.mikrus ||
  "http://127.0.0.1:3210";
const BESKID_URL = Deno.env.get("BESKID_URL") ||
  SERVICE_URLS.beskid ||
  "http://127.0.0.1:8085";

type Actor = ReturnType<typeof getActor>;

interface ActorState {
  key: string;
  character: Actor;
}

interface PostRef {
  uri: string;
  cid: string;
  rkey: string;
  author: Actor;
  text: string;
  quotedUri?: string;
}

interface SocialCounts {
  likes: number;
  reposts: number;
  followers: number;
}

interface CardSummary {
  uri: string;
  authorDid: string;
  text: string;
  profileDisplayName?: string;
  social?: SocialCounts;
  hydratedRecordCount?: number;
}


function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function p95(timer: OperationTimer, name: string): number {
  return timer.getAllStats()[name]?.p95 ?? 0;
}

function ratio(numerator: number, denominator: number): number | null {
  if (denominator <= 0) return null;
  return Number((numerator / denominator).toFixed(3));
}

async function setupAccount(pds: XrpcClient, character: Actor) {
  const session = await pds.accounts.createAccount(
    character.handle,
    character.email,
    character.password,
  ).catch(() =>
    pds.accounts.createSession(character.handle, character.password)
  );
  character.did = session.did;
  character.accessJwt = session.accessJwt;
  return session;
}

async function putProfile(
  pds: XrpcClient,
  character: Actor,
): Promise<void> {
  const record = {
    $type: "app.bsky.actor.profile",
    displayName: character.name,
    description: `Cache latency scenario actor: ${character.handle}`,
  };

  try {
    await pds.records.putRecord(
      character.did,
      "app.bsky.actor.profile",
      "self",
      record,
      character.accessJwt,
    );
  } catch {
    try {
      await pds.records.createRecord(
        character.did,
        "app.bsky.actor.profile",
        record,
        character.accessJwt,
        { rkey: "self" },
      );
    } catch {
      // Existing profile records are acceptable for this scenario.
    }
  }
}

async function createPost(
  pds: XrpcClient,
  author: Actor,
  rkey: string,
  text: string,
  quoted?: PostRef,
): Promise<PostRef> {
  const record: Record<string, unknown> = {
    $type: "app.bsky.feed.post",
    text,
    createdAt: now(),
  };
  if (quoted) {
    record.embed = {
      $type: "app.bsky.embed.record",
      record: {
        uri: quoted.uri,
        cid: quoted.cid,
      },
    };
  }

  const res = await pds.records.createRecord(
    author.did,
    "app.bsky.feed.post",
    record,
    author.accessJwt,
    { rkey },
  );
  return {
    uri: res.uri,
    cid: res.cid,
    rkey,
    author,
    text,
    quotedUri: quoted?.uri,
  };
}

async function createRelationSeed(
  pds: XrpcClient,
  actors: ActorState[],
  hotPost: PostRef,
  runKey: string,
) {
  for (const actor of actors.slice(1)) {
    await pds.records.createRecord(
      actor.character.did,
      "app.bsky.graph.follow",
      {
        $type: "app.bsky.graph.follow",
        subject: actors[0].character.did,
        createdAt: now(),
      },
      actor.character.accessJwt,
      { rkey: `cache-follow-${runKey}-${actor.key}` },
    );
    await pds.records.createRecord(
      actor.character.did,
      "app.bsky.feed.like",
      {
        $type: "app.bsky.feed.like",
        subject: { uri: hotPost.uri, cid: hotPost.cid },
        createdAt: now(),
      },
      actor.character.accessJwt,
      { rkey: `cache-like-${runKey}-${actor.key}` },
    );
    await pds.records.createRecord(
      actor.character.did,
      "app.bsky.feed.repost",
      {
        $type: "app.bsky.feed.repost",
        subject: { uri: hotPost.uri, cid: hotPost.cid },
        createdAt: now(),
      },
      actor.character.accessJwt,
      { rkey: `cache-repost-${runKey}-${actor.key}` },
    );
  }

  const list = await pds.records.createRecord(
    actors[0].character.did,
    "app.bsky.graph.list",
    {
      $type: "app.bsky.graph.list",
      purpose: "app.bsky.graph.defs#curatelist",
      name: "Cache latency actors",
      description: "Actors used by scenario 92",
      createdAt: now(),
    },
    actors[0].character.accessJwt,
    { rkey: `cache-list-${runKey}` },
  );

  for (const actor of actors.slice(1)) {
    await pds.records.createRecord(
      actors[0].character.did,
      "app.bsky.graph.listitem",
      {
        $type: "app.bsky.graph.listitem",
        list: list.uri,
        subject: actor.character.did,
        createdAt: now(),
      },
      actors[0].character.accessJwt,
      { rkey: `cache-listitem-${runKey}-${actor.key}` },
    );
  }

  return list;
}

async function waitForBacklinkCount(
  mikrus: XrpcClient,
  subject: string,
  source: string,
  minTotal: number,
  timeoutMs = 60_000,
): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  let lastTotal = 0;
  while (Date.now() < deadline) {
    try {
      const response = await mikrus.raw.xrpcGet(
        "blue.microcosm.links.getBacklinksCount",
        { subject, source },
      );
      lastTotal = Number(response.total || 0);
      if (lastTotal >= minTotal) return lastTotal;
    } catch {
      // Keep polling while Mikrus catches up.
    }
    await sleep(1_000);
  }
  throw new Error(
    `Timed out waiting for ${source} on ${subject}; last total=${lastTotal}`,
  );
}

async function directSocialCounts(
  pds: XrpcClient,
  actors: ActorState[],
  post: PostRef,
): Promise<SocialCounts> {
  let likes = 0;
  let reposts = 0;
  let followers = 0;

  for (const actor of actors) {
    const likeList = await pds.raw.xrpcGet("com.atproto.repo.listRecords", {
      repo: actor.character.did,
      collection: "app.bsky.feed.like",
      limit: 100,
    });
    likes += (likeList.records ?? []).filter((item: any) =>
      item.value?.subject?.uri === post.uri
    ).length;

    const repostList = await pds.raw.xrpcGet("com.atproto.repo.listRecords", {
      repo: actor.character.did,
      collection: "app.bsky.feed.repost",
      limit: 100,
    });
    reposts += (repostList.records ?? []).filter((item: any) =>
      item.value?.subject?.uri === post.uri
    ).length;

    const followList = await pds.raw.xrpcGet("com.atproto.repo.listRecords", {
      repo: actor.character.did,
      collection: "app.bsky.graph.follow",
      limit: 100,
    });
    followers += (followList.records ?? []).filter((item: any) =>
      item.value?.subject === post.author.did
    ).length;
  }

  return { likes, reposts, followers };
}

async function mikrusSocialCounts(
  mikrus: XrpcClient,
  post: PostRef,
): Promise<SocialCounts> {
  const [likes, reposts, followers] = await Promise.all([
    mikrus.raw.xrpcGet("blue.microcosm.links.getBacklinksCount", {
      subject: post.uri,
      source: "app.bsky.feed.like:subject.uri",
    }),
    mikrus.raw.xrpcGet("blue.microcosm.links.getBacklinksCount", {
      subject: post.uri,
      source: "app.bsky.feed.repost:subject.uri",
    }),
    mikrus.raw.xrpcGet("blue.microcosm.links.getBacklinksCount", {
      subject: post.author.did,
      source: "app.bsky.graph.follow:subject",
    }),
  ]);
  return {
    likes: Number(likes.total || 0),
    reposts: Number(reposts.total || 0),
    followers: Number(followers.total || 0),
  };
}

async function renderDirectCard(
  pds: XrpcClient,
  timer: OperationTimer,
  actors: ActorState[],
  post: PostRef,
  hotPost: PostRef,
): Promise<CardSummary> {
  const record = await timer.measure(
    "direct_get_record",
    () =>
      pds.records.getRecord(post.author.did, "app.bsky.feed.post", post.rkey),
  );
  const identity = await timer.measure(
    "direct_resolve_handle",
    () =>
      pds.raw.xrpcGet("com.atproto.identity.resolveHandle", {
        handle: post.author.handle,
      }),
  );
  const profile = await timer.measure(
    "direct_get_profile",
    () =>
      pds.records.getRecord(post.author.did, "app.bsky.actor.profile", "self")
        .catch(() => undefined),
  );
  const social = post.uri === hotPost.uri
    ? await timer.measure(
      "direct_social_scan",
      () => directSocialCounts(pds, actors, post),
    )
    : undefined;

  return {
    uri: post.uri,
    authorDid: identity.did,
    text: record.value?.text ?? "",
    profileDisplayName: profile?.value?.displayName,
    social,
  };
}

async function renderCachedCard(
  beskid: XrpcClient,
  mikrus: XrpcClient,
  timer: OperationTimer,
  post: PostRef,
  hotPost: PostRef,
): Promise<CardSummary> {
  const identity = await timer.measure(
    "beskid_resolve_handle",
    () =>
      beskid.raw.xrpcGet("com.atproto.identity.resolveHandle", {
        handle: post.author.handle,
      }),
  );
  const record = await timer.measure(
    "beskid_get_uri_record",
    () =>
      beskid.raw.xrpcGet("com.bad-example.repo.getUriRecord", {
        at_uri: post.uri,
        cid: post.cid,
      }),
  );
  const profile = await timer.measure(
    "beskid_get_profile",
    () =>
      beskid.raw.xrpcGet("com.atproto.repo.getRecord", {
        repo: post.author.did,
        collection: "app.bsky.actor.profile",
        rkey: "self",
      }).catch(() => undefined),
  );
  const social = post.uri === hotPost.uri
    ? await timer.measure(
      "mikrus_social_counts",
      () => mikrusSocialCounts(mikrus, post),
    )
    : undefined;

  let hydratedRecordCount = 0;
  if (post.quotedUri) {
    const hydrated = await timer.measure(
      "beskid_hydrate",
      () =>
        beskid.raw.xrpcPost("com.bad-example.proxy.hydrateQueryResponse", {
          xrpc: "com.atproto.repo.getRecord",
          atproto_proxy: PDS1,
          params: {
            repo: post.author.did,
            collection: "app.bsky.feed.post",
            rkey: post.rkey,
          },
          hydration_sources: [
            { path: "value.embed.record.uri", shape: "strong-ref" },
          ],
        }),
    );
    hydratedRecordCount = Object.keys(hydrated.records ?? {}).length;
  }

  return {
    uri: post.uri,
    authorDid: identity.did,
    text: record.value?.text ?? "",
    profileDisplayName: profile?.value?.displayName,
    social,
    hydratedRecordCount,
  };
}

async function runCardPhase(
  label: "direct" | "cache_cold" | "cache_warm",
  iterations: number,
  cards: PostRef[],
  fn: (post: PostRef) => Promise<CardSummary>,
  timer: OperationTimer,
): Promise<Map<string, CardSummary>> {
  const summaries = new Map<string, CardSummary>();
  for (let i = 0; i < iterations; i++) {
    for (const card of cards) {
      const summary = await timer.measure(`${label}_card`, () => fn(card));
      summaries.set(card.uri, summary);
    }
  }
  return summaries;
}

function compareSummaries(
  cards: PostRef[],
  direct: Map<string, CardSummary>,
  cached: Map<string, CardSummary>,
): string[] {
  const mismatches: string[] = [];
  for (const card of cards) {
    const directCard = direct.get(card.uri);
    const cachedCard = cached.get(card.uri);
    if (!directCard || !cachedCard) {
      mismatches.push(`${card.uri}: missing summary`);
      continue;
    }
    if (directCard.authorDid !== cachedCard.authorDid) {
      mismatches.push(`${card.uri}: author DID mismatch`);
    }
    if (directCard.text !== cachedCard.text) {
      mismatches.push(`${card.uri}: text mismatch`);
    }
    if (directCard.social && cachedCard.social) {
      for (const key of ["likes", "reposts", "followers"] as const) {
        if (directCard.social[key] !== cachedCard.social[key]) {
          mismatches.push(
            `${card.uri}: ${key} mismatch direct=${
              directCard.social[key]
            } cache=${cachedCard.social[key]}`,
          );
        }
      }
    }
    if (card.quotedUri && (cachedCard.hydratedRecordCount ?? 0) < 1) {
      mismatches.push(`${card.uri}: expected hydrated quote record`);
    }
  }
  return mismatches;
}

async function withPhase<T>(
  phases: PhaseTimer,
  name: string,
  fn: () => Promise<T>,
): Promise<T> {
  phases.startPhase(name);
  try {
    return await fn();
  } finally {
    phases.endPhase();
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Theoretical App Cache Latency");
  result.start();

  const pds = new XrpcClient(PDS1);
  const mikrus = new XrpcClient(MIKRUS_URL);
  const beskid = new XrpcClient(BESKID_URL);
  const timer = new OperationTimer();
  const phases = new PhaseTimer();
  const runKey = String(Date.now());

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Mikrus health check", async () => {
    await mikrus.waitForHealthy(30);
  });
  await timedCall(result, "Beskid health check", async () => {
    await beskid.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const actors: ActorState[] = ["luna", "marcus", "rosa", "volt", "quiet"]
    .map((key) => ({ key, character: getActor(key) }));
  let basePosts: PostRef[] = [];
  let quotePosts: PostRef[] = [];
  let hotPost: PostRef | undefined;
  let listUri = "";

  await timedCall(result, "Seed actors, posts, and social graph", async () => {
    await withPhase(phases, "seed", async () => {
      for (const actor of actors) {
        await setupAccount(pds, actor.character);
        await putProfile(pds, actor.character);
      }

      for (const actor of actors) {
        for (let i = 0; i < 4; i++) {
          basePosts.push(
            await createPost(
              pds,
              actor.character,
              `cache-base-${runKey}-${actor.key}-${i}`,
              `Cache benchmark base ${actor.key} ${i} ${runKey}`,
            ),
          );
        }
      }

      const seededHotPost = basePosts[0];
      if (!seededHotPost) throw new Error("No base posts were created");
      hotPost = seededHotPost;
      for (const actor of actors) {
        for (let i = 0; i < 2; i++) {
          const quoted = basePosts[
            (i + actors.indexOf(actor) + 1) %
            basePosts.length
          ];
          quotePosts.push(
            await createPost(
              pds,
              actor.character,
              `cache-quote-${runKey}-${actor.key}-${i}`,
              `Cache benchmark quote ${actor.key} ${i} ${runKey}`,
              quoted,
            ),
          );
        }
      }

      const list = await createRelationSeed(
        pds,
        actors,
        seededHotPost,
        runKey,
      );
      listUri = list.uri;
    });
  }, () => `posts=${basePosts.length + quotePosts.length}`);

  if (!hotPost) {
    result.stepFailed("Seed validation", "hot post was not created");
    result.finish();
    return result;
  }

  await timedCall(result, "Wait for Mikrus cache indexes", async () => {
    await withPhase(phases, "index_wait", async () => {
      await waitForBacklinkCount(
        mikrus,
        hotPost!.uri,
        "app.bsky.feed.like:subject.uri",
        4,
      );
      await waitForBacklinkCount(
        mikrus,
        hotPost!.uri,
        "app.bsky.feed.repost:subject.uri",
        4,
      );
      await waitForBacklinkCount(
        mikrus,
        hotPost!.author.did,
        "app.bsky.graph.follow:subject",
        4,
      );
      await timer.measure(
        "mikrus_many_to_many_counts",
        () =>
          mikrus.raw.xrpcGet("blue.microcosm.links.getManyToManyCounts", {
            subject: actors[1].character.did,
            source: "app.bsky.graph.listitem:subject",
            pathToOther: "list",
          }),
      );
    });
  });

  const cards = [
    hotPost,
    ...basePosts.slice(1, 5),
    ...quotePosts.slice(0, 5),
  ];
  let directSummaries = new Map<string, CardSummary>();
  let warmSummaries = new Map<string, CardSummary>();
  let correctnessMismatches: string[] = [];

  await timedCall(result, "Direct baseline render", async () => {
    directSummaries = await withPhase(
      phases,
      "direct_baseline",
      () =>
        runCardPhase(
          "direct",
          2,
          cards,
          (post) => renderDirectCard(pds, timer, actors, post, hotPost!),
          timer,
        ),
    );
  }, () => `samples=${timer.getAllStats().direct_card?.count ?? 0}`);

  await timedCall(result, "Cold cache render", async () => {
    await withPhase(phases, "cache_cold", () =>
      runCardPhase(
        "cache_cold",
        1,
        cards,
        (post) => renderCachedCard(beskid, mikrus, timer, post, hotPost!),
        timer,
      ));
  }, () => `samples=${timer.getAllStats().cache_cold_card?.count ?? 0}`);

  await timedCall(result, "Warm cache render", async () => {
    warmSummaries = await withPhase(phases, "cache_warm", () =>
      runCardPhase(
        "cache_warm",
        2,
        cards,
        (post) => renderCachedCard(beskid, mikrus, timer, post, hotPost!),
        timer,
      ));
  }, () => `samples=${timer.getAllStats().cache_warm_card?.count ?? 0}`);

  await timedCall(result, "Verify cache render correctness", async () => {
    correctnessMismatches = compareSummaries(
      cards,
      directSummaries,
      warmSummaries,
    );
    assert.equal(
      correctnessMismatches.length,
      0,
      correctnessMismatches.join("; "),
    );
  }, () => "mismatches=0");

  await timedCall(result, "Churn and staleness checks", async () => {
    return await withPhase(phases, "churn", async () => {
      const updateTarget = basePosts[2];
      const updatedText = `Cache benchmark updated ${runKey}`;
      await pds.records.putRecord(
        updateTarget.author.did,
        "app.bsky.feed.post",
        updateTarget.rkey,
        {
          $type: "app.bsky.feed.post",
          text: updatedText,
          createdAt: now(),
        },
        updateTarget.author.accessJwt,
      );
      const directUpdated = await pds.records.getRecord(
        updateTarget.author.did,
        "app.bsky.feed.post",
        updateTarget.rkey,
      );
      assert.equal(directUpdated.value.text, updatedText);
      const cachedUpdated = await beskid.raw.xrpcGet(
        "com.bad-example.repo.getUriRecord",
        { at_uri: updateTarget.uri, cid: updateTarget.cid },
      );
      assert.equal(cachedUpdated.value.text, updateTarget.text);

      const deleteTarget = basePosts[3];
      await pds.records.deleteRecord(
        deleteTarget.author.did,
        "app.bsky.feed.post",
        deleteTarget.rkey,
        deleteTarget.author.accessJwt,
      );
      const cachedDeleted = await beskid.raw.xrpcGet(
        "com.bad-example.repo.getUriRecord",
        { at_uri: deleteTarget.uri, cid: deleteTarget.cid },
      );
      assert.equal(cachedDeleted.value.text, deleteTarget.text);

      const freshPost = await createPost(
        pds,
        actors[0].character,
        `cache-fresh-${runKey}`,
        `Cache benchmark fresh link ${runKey}`,
      );
      await pds.records.createRecord(
        actors[1].character.did,
        "app.bsky.feed.like",
        {
          $type: "app.bsky.feed.like",
          subject: { uri: freshPost.uri, cid: freshPost.cid },
          createdAt: now(),
        },
        actors[1].character.accessJwt,
        { rkey: `cache-fresh-like-${runKey}` },
      );
      const freshTotal = await waitForBacklinkCount(
        mikrus,
        freshPost.uri,
        "app.bsky.feed.like:subject.uri",
        1,
      );

      return {
        updated_uri: updateTarget.uri,
        deleted_uri: deleteTarget.uri,
        fresh_uri: freshPost.uri,
        fresh_like_total: freshTotal,
      };
    });
  }, (churn) => `fresh_like_total=${churn.fresh_like_total}`);

  const directP95 = p95(timer, "direct_card");
  const coldP95 = p95(timer, "cache_cold_card");
  const warmP95 = p95(timer, "cache_warm_card");
  const ratios = {
    warm_vs_direct_p95_ratio: ratio(warmP95, directP95),
    warm_vs_cold_p95_ratio: ratio(warmP95, coldP95),
  };

  await timedCall(
    result,
    "Evaluate cache latency diagnostic",
    async () => {
      const stats = timer.getAllStats();
      const severeRegression = (stats.direct_card?.count ?? 0) >= 20 &&
        (stats.cache_warm_card?.count ?? 0) >= 20 &&
        directP95 > 0 &&
        warmP95 > directP95 * 2.5;
      assert.isTrue(
        !severeRegression,
        `warm cache p95=${warmP95.toFixed(2)}ms is more than 2.5x direct p95=${
          directP95.toFixed(2)
        }ms`,
      );
      return ratios;
    },
    () =>
      `direct_p95=${directP95.toFixed(2)}ms warm_p95=${warmP95.toFixed(2)}ms`,
  );

  result.recordArtifact("cache_latency", {
    pds_url: PDS1,
    mikrus_url: MIKRUS_URL,
    beskid_url: BESKID_URL,
    run_key: runKey,
    actors: Object.fromEntries(
      actors.map((actor) => [actor.key, actor.character.did]),
    ),
    list_uri: listUri,
    post_count: basePosts.length + quotePosts.length,
    card_count: cards.length,
    operation_stats: timer.toDict(),
    phase_timings: phases.toDict(),
    ratios,
    correctness_mismatches: correctnessMismatches,
    sample_counts: {
      direct: timer.getAllStats().direct_card?.count ?? 0,
      cache_cold: timer.getAllStats().cache_cold_card?.count ?? 0,
      cache_warm: timer.getAllStats().cache_warm_card?.count ?? 0,
    },
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
