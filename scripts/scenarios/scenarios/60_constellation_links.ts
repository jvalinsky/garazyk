import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

const CONSTELLATION_URL =
  Deno.env.get("CONSTELLATION_URL") ||
  SERVICE_URLS.constellation ||
  "http://localhost:3210";

function now() {
  return new Date().toISOString();
}

async function waitForCount(
  constellation: XrpcClient,
  subject: string,
  source: string,
  minTotal: number,
  timeoutMs = 20_000,
) {
  const deadline = Date.now() + timeoutMs;
  let lastTotal = 0;
  while (Date.now() < deadline) {
    const response = await constellation.raw.xrpcGet(
      "blue.microcosm.links.getBacklinksCount",
      { subject, source },
    );
    lastTotal = Number(response.total || 0);
    if (lastTotal >= minTotal) return response;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`Timed out waiting for ${source} count on ${subject}; last total=${lastTotal}`);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Constellation Links");
  result.start();

  const pds = new XrpcClient(PDS1);
  const constellation = new XrpcClient(CONSTELLATION_URL);
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Constellation health check", async () => {
    await constellation.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  for (const character of [luna, marcus]) {
    const session = await timedCall(result, `Create account: ${character.name}`, async () => {
      return await pds.accounts.createAccount(
        character.handle,
        character.email,
        character.password,
      ).catch(() => pds.accounts.createSession(character.handle, character.password));
    }, (session) => `did=${session.did}`);
    if (session) {
      character.did = session.did;
      character.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID after account creation");
    result.finish();
    return result;
  }

  const postRef = await timedCall(result, "Create target post", async () => {
    return await pds.records.createRecord(
      luna.did,
      "app.bsky.feed.post",
      {
        $type: "app.bsky.feed.post",
        text: "Constellation link index target",
        createdAt: now(),
      },
      luna.accessJwt,
      { rkey: `constellation-target-${Date.now()}` },
    );
  }, (record) => record.uri);

  if (!postRef) {
    result.finish();
    return result;
  }

  const postUri = postRef.uri;
  const listRef = await timedCall(result, "Create list target", async () => {
    return await pds.records.createRecord(
      luna.did,
      "app.bsky.graph.list",
      {
        $type: "app.bsky.graph.list",
        purpose: "app.bsky.graph.defs#curatelist",
        name: "Constellation Targets",
        description: "Records used by the Constellation scenario",
        createdAt: now(),
      },
      luna.accessJwt,
      { rkey: `constellation-list-${Date.now()}` },
    );
  }, (record) => record.uri);

  await timedCall(result, "Create follow", async () => {
    return await pds.records.createRecord(
      marcus.did,
      "app.bsky.graph.follow",
      {
        $type: "app.bsky.graph.follow",
        subject: luna.did,
        createdAt: now(),
      },
      marcus.accessJwt,
      { rkey: `constellation-follow-${Date.now()}` },
    );
  });

  await timedCall(result, "Create like", async () => {
    return await pds.records.createRecord(
      marcus.did,
      "app.bsky.feed.like",
      {
        $type: "app.bsky.feed.like",
        subject: { uri: postUri, cid: postRef.cid },
        createdAt: now(),
      },
      marcus.accessJwt,
      { rkey: `constellation-like-${Date.now()}` },
    );
  });

  await timedCall(result, "Create repost", async () => {
    return await pds.records.createRecord(
      marcus.did,
      "app.bsky.feed.repost",
      {
        $type: "app.bsky.feed.repost",
        subject: { uri: postUri, cid: postRef.cid },
        createdAt: now(),
      },
      marcus.accessJwt,
      { rkey: `constellation-repost-${Date.now()}` },
    );
  });

  if (listRef) {
    await timedCall(result, "Create list item", async () => {
      return await pds.records.createRecord(
        marcus.did,
        "app.bsky.graph.listitem",
        {
          $type: "app.bsky.graph.listitem",
          list: listRef.uri,
          subject: luna.did,
          createdAt: now(),
        },
        marcus.accessJwt,
        { rkey: `constellation-listitem-${Date.now()}` },
      );
    });
  }

  await timedCall(result, "Follow backlink count", async () => {
    const response = await waitForCount(
      constellation,
      luna.did,
      "app.bsky.graph.follow:subject",
      1,
    );
    assert.equal(response.total, 1);
    return response;
  }, (response) => `total=${response.total}`);

  await timedCall(result, "Post like backlink", async () => {
    const response = await waitForCount(
      constellation,
      postUri,
      "app.bsky.feed.like:subject.uri",
      1,
    );
    assert.equal(response.total, 1);
    return response;
  }, (response) => `total=${response.total}`);

  await timedCall(result, "Backlink DID lookup", async () => {
    const response = await constellation.raw.xrpcGet(
      "blue.microcosm.links.getBacklinkDids",
      {
        subject: postUri,
        source: "app.bsky.feed.like:subject.uri",
      },
    );
    assert.equal(response.linking_dids, [marcus.did]);
    return response;
  }, (response) => `dids=${response.linking_dids.join(",")}`);

  if (listRef) {
    await timedCall(result, "Many-to-many list count", async () => {
      const response = await constellation.raw.xrpcGet(
        "blue.microcosm.links.getManyToManyCounts",
        {
          subject: luna.did,
          source: "app.bsky.graph.listitem:subject",
          pathToOther: "list",
        },
      );
      assert.isTrue(
        response.counts_by_other_subject.some((item: any) =>
          item.subject === listRef.uri && Number(item.total) >= 1
        ),
        "list URI missing from many-to-many counts",
      );
      return response;
    }, (response) => `items=${response.counts_by_other_subject.length}`);
  }

  await timedCall(result, "Record lookup by URI", async () => {
    const response = await constellation.raw.xrpcGet(
      "blue.microcosm.repo.getRecordByUri",
      { at_uri: postUri, cid: postRef.cid },
    );
    assert.equal(response.uri, postUri);
    assert.equal(response.cid, postRef.cid);
    return response;
  }, (response) => `cid=${response.cid}`);

  result.recordArtifact("constellation", {
    url: CONSTELLATION_URL,
    postUri,
    listUri: listRef?.uri,
    luna: luna.did,
    marcus: marcus.did,
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
