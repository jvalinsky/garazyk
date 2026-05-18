/**
 * @module scenarios/03_content_creation
 *
 * Scenario: Content creation and engagement (posts, replies, quotes, likes, and deletion)
 *
 * Behavior:
 * - Create test accounts and profiles
 * - Post different types of content (text, reply, quote)
 * - Users like posts and bookmark content
 * - Verify feed generation, thread views, and notifications
 * - Delete a post and confirm it is gone
 *
 * Expectations:
 * - Content is created and retrievable
 * - Interactions (replies, quotes, likes, bookmarks) are tracked correctly
 * - Deletion of records works and is verifiable
 */

import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia/config";
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";

function now() {
  return new Date().toISOString();
}

async function createPost(
  ctx: ScenarioContext,
  client: XrpcClient,
  authorName: string,
  text: string,
  result: ScenarioResult,
  facets?: any[],
  reply?: any,
  embed?: any,
) {
  const author = ctx.getCharacter(authorName);
  const record: any = {
    $type: "app.bsky.feed.post",
    text,
    createdAt: now(),
  };
  if (facets) record.facets = facets;
  if (reply) record.reply = reply;
  if (embed) record.embed = embed;

  const rec = await timedCall(
    result,
    `${author.name} posts`,
    async () => {
      const res = await client.raw.post("com.atproto.repo.createRecord", {
        repo: author.did,
        collection: "app.bsky.feed.post",
        record,
      }, author.accessJwt);
      return res;
    },
    () => text.substring(0, 60),
  );
  return rec;
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Content Creation & Interaction");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${ctx.pds1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt", "quiet"];
  for (const name of charNames) {
    const char = ctx.getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => ctx.getCharacter(n).did);
  if (active.length < 3) {
    result.stepFailed("Account creation", "Not enough accounts");
    result.finish();
    return result;
  }

  for (const name of active) {
    const char = ctx.getCharacter(name);
    await timedCall(
      result,
      `Set profile: ${char.name}`,
      async () => {
        const res = await client.raw.post("com.atproto.repo.createRecord", {
          repo: char.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
          },
        }, char.accessJwt);
        return res;
      },
    );
  }

  const lunaPost = await createPost(
    ctx,
    client,
    "luna",
    "Just captured the most stunning image of the Orion Nebula! The colors are breathtaking. #astronomy",
    result,
  );

  const marcusPost = await createPost(
    ctx,
    client,
    "marcus",
    "Just shipped a new XRPC handler for the PDS. Open source is the way!",
    result,
  );

  const rosaPost = await createPost(
    ctx,
    client,
    "rosa",
    "Made the most incredible sourdough today. The crust was perfect!",
    result,
  );

  const voltPost = await createPost(
    ctx,
    client,
    "volt",
    "New beat dropping this weekend. Get ready for the drop!",
    result,
  );

  if (lunaPost && marcusPost) {
    const replyRef = {
      root: { uri: lunaPost.uri, cid: lunaPost.cid },
      parent: { uri: lunaPost.uri, cid: lunaPost.cid },
    };
    await createPost(
      ctx,
      client,
      "marcus",
      "The data pipeline for nebula images is fascinating — CBOR-encoded CAR blocks!",
      result,
      undefined,
      replyRef,
    );
  } else {
    result.stepSkipped("Marcus replies to Luna", "Missing post references");
  }

  if (lunaPost) {
    await createPost(
      ctx,
      client,
      "rosa",
      "Space food is underrated — imagine sourdough on the ISS!",
      result,
      undefined,
      undefined,
      {
        $type: "app.bsky.embed.record",
        record: { uri: lunaPost.uri, cid: lunaPost.cid },
      },
    );
  } else {
    result.stepSkipped("Rosa quotes Luna", "Missing post reference");
  }

  const volt = ctx.getCharacter("volt");
  for (
    const { name, rec } of [{ name: "Luna", rec: lunaPost }, {
      name: "Marcus",
      rec: marcusPost,
    }, {
      name: "Rosa",
      rec: rosaPost,
    }]
  ) {
    if (rec) {
      await timedCall(
        result,
        `DJ Volt likes ${name}'s post`,
        async () => {
          await client.raw.post("com.atproto.repo.createRecord", {
            repo: volt.did,
            collection: "app.bsky.feed.like",
            record: {
              $type: "app.bsky.feed.like",
              subject: { uri: rec.uri, cid: rec.cid },
              createdAt: now(),
            },
          }, volt.accessJwt);
        },
      );
    }
  }

  const quiet = ctx.getCharacter("quiet");
  if (lunaPost) {
    await timedCall(
      result,
      "Quiet Observer bookmarks Luna's post",
      async () => {
        await client.raw.post("app.bsky.bookmark.createBookmark", {
          uri: lunaPost.uri,
          cid: lunaPost.cid,
        }, quiet.accessJwt);
      },
    );
  }

  const rosa = ctx.getCharacter("rosa");
  const rosaTemp = await createPost(
    ctx,
    client,
    "rosa",
    "This post will be deleted soon. Don't get attached!",
    result,
  );

  if (rosaTemp) {
    const rkey = rosaTemp.uri.split("/").pop()!;
    await timedCall(
      result,
      "Rosa deletes her post",
      async () => {
        await client.raw.post("com.atproto.repo.deleteRecord", {
          repo: rosa.did,
          collection: "app.bsky.feed.post",
          rkey,
        }, rosa.accessJwt);
      },
      () => `rkey=${rkey}`,
    );

    await timedCall(
      result,
      "Verify deletion",
      async () => {
        await client.agent.com.atproto.repo.getRecord({
          repo: rosa.did,
          collection: "app.bsky.feed.post",
          rkey,
        });
      },
      undefined,
      true,
    );
  }

  await new Promise((r) => setTimeout(r, 3000));

  const luna = ctx.getCharacter("luna");

  await timedCall(
    result,
    "Luna's timeline",
    async () => {
      return await client.raw.get(
        "app.bsky.feed.getTimeline",
        {},
        luna.accessJwt,
      );
    },
    (t) => `items=${t.feed?.length || 0}`,
  );

  await timedCall(
    result,
    "Luna's author feed",
    async () => {
      return await client.raw.get(
        "app.bsky.feed.getAuthorFeed",
        { actor: luna.did },
        luna.accessJwt,
      );
    },
    (f) => `items=${f.feed?.length || 0}`,
  );

  if (lunaPost) {
    await timedCall(
      result,
      "Post thread view",
      async () => {
        return await client.raw.get(
          "app.bsky.feed.getPostThread",
          { uri: lunaPost.uri },
          luna.accessJwt,
        );
      },
    );

    await timedCall(
      result,
      "Likes on Luna's post",
      async () => {
        return await client.raw.get(
          "app.bsky.feed.getLikes",
          { uri: lunaPost.uri },
          luna.accessJwt,
        );
      },
      (l) => `count=${l.likes?.length || 0}`,
    );
  }

  await timedCall(
    result,
    "Luna's notifications",
    async () => {
      return await client.raw.get(
        "app.bsky.notification.listNotifications",
        {},
        luna.accessJwt,
      );
    },
    (n) => `count=${n.notifications?.length || 0}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
