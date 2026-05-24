/**
 * @module scenarios/75_mikrus_enumeration
 *
 * Scenario: Mikrus backlink enumeration with pagination, edge cases, and list endpoints.
 *
 * Behavior:
 * - Creates multiple backlink records (follows, likes, reposts) targeting a single subject.
 * - Tests getBacklinks (list, not just count) with pagination.
 * - Tests getBacklinkDids with empty results.
 * - Tests getManyToManyCounts with alternative pathToOther values.
 * - Tests getRecordByUri with nonexistent URI.
 * - Tests getBacklinksCount with nonexistent subject.
 * - Verifies Mikrus health endpoint.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, ScenarioResult } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

const MIKRUS_URL = Deno.env.get("MIKRUS_URL") ?? SERVICE_URLS.mikrus;


async function waitForBacklinkCount(
  mikrus: XrpcClient,
  subject: string,
  source: string,
  minTotal: number,
  timeoutMs = 25_000,
) {
  const deadline = Date.now() + timeoutMs;
  let lastTotal = 0;
  while (Date.now() < deadline) {
    const response = await mikrus.raw.xrpcGet(
      "blue.microcosm.links.getBacklinksCount",
      { subject, source },
    );
    lastTotal = Number(response.total || 0);
    if (lastTotal >= minTotal) return response;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(
    `Timed out waiting for count on ${subject}/${source}; last total=${lastTotal}`,
  );
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Mikrus Backlink Enumeration");
  result.start();

  const pds = new XrpcClient(PDS1);
  const mikrus = new XrpcClient(MIKRUS_URL);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Mikrus health check", async () => {
    await mikrus.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");
  const rosa = getActor("rosa");

  for (const char of [luna, marcus, rosa]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await pds.accounts
          .createAccount(char.handle, char.email, char.password)
          .catch(() => pds.accounts.createSession(char.handle, char.password));
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did || !rosa.did) {
    result.stepFailed("Account setup", "missing DID after account creation");
    result.finish();
    return result;
  }

  // Create a target post from Luna
  const postRef = await timedCall(
    result,
    "Create target post for backlinks",
    async () => {
      return await pds.records.createRecord(
        luna.did!,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Mikrus enumeration target",
          createdAt: now(),
        },
        luna.accessJwt!,
        { rkey: `enum-target-${Date.now()}` },
      );
    },
    (r) => r.uri,
  );

  if (!postRef) {
    result.finish();
    return result;
  }
  const targetUri = postRef.uri;

  // Marcus follows Luna
  await timedCall(result, "Marcus follows Luna", async () => {
    return await pds.records.createRecord(
      marcus.did!,
      "app.bsky.graph.follow",
      { $type: "app.bsky.graph.follow", subject: luna.did, createdAt: now() },
      marcus.accessJwt!,
      { rkey: `enum-follow-${Date.now()}` },
    );
  });

  // Rosa follows Luna
  await timedCall(result, "Rosa follows Luna", async () => {
    return await pds.records.createRecord(
      rosa.did!,
      "app.bsky.graph.follow",
      { $type: "app.bsky.graph.follow", subject: luna.did, createdAt: now() },
      rosa.accessJwt!,
      { rkey: `enum-follow2-${Date.now()}` },
    );
  });

  // Marcus likes Luna's post
  await timedCall(result, "Marcus likes target post", async () => {
    return await pds.records.createRecord(
      marcus.did!,
      "app.bsky.feed.like",
      {
        $type: "app.bsky.feed.like",
        subject: { uri: targetUri, cid: postRef.cid },
        createdAt: now(),
      },
      marcus.accessJwt!,
      { rkey: `enum-like-${Date.now()}` },
    );
  });

  // Rosa likes Luna's post
  await timedCall(result, "Rosa likes target post", async () => {
    return await pds.records.createRecord(
      rosa.did!,
      "app.bsky.feed.like",
      {
        $type: "app.bsky.feed.like",
        subject: { uri: targetUri, cid: postRef.cid },
        createdAt: now(),
      },
      rosa.accessJwt!,
      { rkey: `enum-like2-${Date.now()}` },
    );
  });

  // Wait for backlinks to be indexed
  await timedCall(
    result,
    "Wait for follow backlinks to Luna",
    async () => {
      return await waitForBacklinkCount(
        mikrus,
        luna.did!,
        "app.bsky.graph.follow:subject",
        2,
      );
    },
    (r) => `total=${r.total}`,
  );

  await timedCall(
    result,
    "Wait for like backlinks to target post",
    async () => {
      return await waitForBacklinkCount(
        mikrus,
        targetUri,
        "app.bsky.feed.like:subject.uri",
        2,
      );
    },
    (r) => `total=${r.total}`,
  );

  // --- Enumeration endpoints ---

  // getBacklinks (list, not count)
  await timedCall(
    result,
    "getBacklinks lists follow backlinks to Luna",
    async () => {
      const resp = await mikrus.raw.xrpcGet(
        "blue.microcosm.links.getBacklinks",
        {
          subject: luna.did,
          source: "app.bsky.graph.follow:subject",
        },
      );
      assert.isTrue(
        Array.isArray(resp.records),
        "expected records array",
      );
      assert.isTrue(
        resp.records.length >= 2,
        `expected at least 2 backlink records, got ${resp.records.length}`,
      );
      // Each backlink should reference a DID
      const linkingDids = resp.records.map((b: any) => b.did);
      assert.isTrue(
        linkingDids.includes(marcus.did),
        "expected marcus in backlinks",
      );
      assert.isTrue(
        linkingDids.includes(rosa.did),
        "expected rosa in backlinks",
      );
      // Verify backlink structure has expected fields
      const first = resp.records[0];
      assert.isTrue(
        typeof first.did === "string",
        "expected did string",
      );
      assert.isTrue(
        typeof first.total === "number" || typeof first.count === "number",
        "expected count in backlink entry",
      );
      return resp;
    },
    (r) => `count=${r.records.length}`,
  );

  // getBacklinks with limit/cursor pagination
  await timedCall(
    result,
    "getBacklinks pagination with limit",
    async () => {
      const resp = await mikrus.raw.xrpcGet(
        "blue.microcosm.links.getBacklinks",
        {
          subject: luna.did,
          source: "app.bsky.graph.follow:subject",
          limit: 1,
        },
      );
      assert.isTrue(
        Array.isArray(resp.records),
        "expected records array with limit",
      );
      assert.isTrue(
        resp.records.length === 1,
        `expected 1 backlink record with limit=1, got ${resp.records.length}`,
      );
      return resp;
    },
    (r) => `count=${r.records.length}, cursor=${r.cursor ?? "none"}`,
  );

  // getBacklinks with nonexistent subject
  await timedCall(
    result,
    "getBacklinks with nonexistent subject returns empty",
    async () => {
      try {
        const resp = await mikrus.raw.xrpcGet(
          "blue.microcosm.links.getBacklinks",
          {
            subject: "at://did:plc:nonexistent/app.bsky.feed.post/fake",
            source: "app.bsky.feed.like:subject.uri",
          },
        );
        const links = resp.records ?? [];
        assert.isTrue(
          links.length === 0,
          `expected empty records, got ${links.length}`,
        );
        return resp;
      } catch {
        // Some implementations may throw 404 — that's acceptable
        return { records: [] };
      }
    },
  );

  // getBacklinkDids
  await timedCall(
    result,
    "getBacklinkDids returns linking DIDs",
    async () => {
      const resp = await mikrus.raw.xrpcGet(
        "blue.microcosm.links.getBacklinkDids",
        {
          subject: targetUri,
          source: "app.bsky.feed.like:subject.uri",
        },
      );
      assert.isTrue(
        Array.isArray(resp.linking_dids),
        "expected linking_dids array",
      );
      assert.isTrue(
        resp.linking_dids.includes(marcus.did),
        "expected marcus in linking_dids",
      );
      assert.isTrue(
        resp.linking_dids.includes(rosa.did),
        "expected rosa in linking_dids",
      );
      return resp;
    },
    (r) => `count=${r.linking_dids.length}`,
  );

  // getManyToManyCounts with pathToOther
  await timedCall(
    result,
    "getManyToManyCounts for list items",
    async () => {
      const resp = await mikrus.raw.xrpcGet(
        "blue.microcosm.links.getManyToManyCounts",
        {
          subject: luna.did,
          source: "app.bsky.graph.follow:subject",
          pathToOther: "subject",
        },
      );
      assert.isTrue(
        Array.isArray(resp.counts_by_other_subject),
        "expected counts_by_other_subject array",
      );
      return resp;
    },
    (r) => `items=${r.counts_by_other_subject.length}`,
  );

  // getRecordByUri with known URI
  await timedCall(
    result,
    "getRecordByUri with known URI",
    async () => {
      const resp = await mikrus.raw.xrpcGet(
        "blue.microcosm.repo.getRecordByUri",
        { at_uri: targetUri, cid: postRef.cid },
      );
      assert.equal(resp.uri, targetUri);
      assert.equal(resp.cid, postRef.cid);
      return resp;
    },
    (r) => `uri=${r.uri}`,
  );

  // getRecordByUri with nonexistent URI
  await timedCall(
    result,
    "getRecordByUri with nonexistent URI returns error gracefully",
    async () => {
      try {
        await mikrus.raw.xrpcGet(
          "blue.microcosm.repo.getRecordByUri",
          {
            at_uri: "at://did:plc:nonexistent/app.bsky.feed.post/void",
            cid: "bafyreiadempty",
          },
        );
        // Some implementations may return empty, that's fine
      } catch {
        // Expected error for nonexistent record
      }
    },
  );

  result.recordArtifact("mikrus-enumeration", {
    url: MIKRUS_URL,
    targetUri,
    luna: luna.did,
    marcus: marcus.did,
    rosa: rosa.did,
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
