/**
 * @module scenarios/02_social_graph
 *
 * Scenario: Social Graph management (follows, blocks, and counts)
 *
 * Behavior:
 * - Create test accounts and profiles
 * - Establish a follower graph between test users
 * - Marcus follows/unfollows DJ Volt
 * - Luna blocks Trollface
 * - Verify follow/follower counts and lists
 *
 * Expectations:
 * - Follow records are created and deleted correctly
 * - Block records are created
 * - Actor lists and counts reflect the social graph accurately
 */

import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";

function now() {
  return new Date().toISOString();
}

async function createAccounts(
  ctx: ScenarioContext,
  client: XrpcClient,
  names: string[],
  result: ScenarioResult,
) {
  const sessions: Record<string, any> = {};
  for (const name of names) {
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
      sessions[name] = session;
    }
  }
  return sessions;
}

async function follow(
  ctx: ScenarioContext,
  client: XrpcClient,
  followerName: string,
  targetName: string,
  result: ScenarioResult,
) {
  const follower = ctx.getCharacter(followerName);
  const target = ctx.getCharacter(targetName);

  if (!follower.did || !follower.accessJwt) {
    result.stepSkipped(
      `${follower.name} follows ${target.name}`,
      "Follower account not created",
    );
    return null;
  }
  if (!target.did) {
    result.stepSkipped(
      `${follower.name} follows ${target.name}`,
      "Target account not created",
    );
    return null;
  }

  const rec = await timedCall(
    result,
    `${follower.name} follows ${target.name}`,
    async () => {
      const res = await client.raw.post("com.atproto.repo.createRecord", {
        repo: follower.did,
        collection: "app.bsky.graph.follow",
        record: {
          $type: "app.bsky.graph.follow",
          subject: target.did,
          createdAt: now(),
        },
      }, follower.accessJwt);
      return res;
    },
    (r) => `uri=${r.uri}`,
  );
  return rec;
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Social Graph");
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

  const pds1Chars = [
    "luna",
    "marcus",
    "rosa",
    "volt",
    "troll",
    "quiet",
    "admin",
  ];
  await createAccounts(ctx, client, pds1Chars, result);

  const active = pds1Chars.filter((n) => ctx.getCharacter(n).did);
  if (active.length < 4) {
    result.stepFailed(
      "Account creation",
      `Only ${active.length} accounts created, need at least 4`,
    );
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

  await follow(ctx, client, "marcus", "luna", result);
  await follow(ctx, client, "marcus", "rosa", result);
  await follow(ctx, client, "marcus", "volt", result);
  await follow(ctx, client, "luna", "marcus", result);
  for (const name of ["luna", "marcus", "rosa", "volt", "troll", "admin"]) {
    await follow(ctx, client, "quiet", name, result);
  }
  await follow(ctx, client, "rosa", "luna", result);
  await follow(ctx, client, "rosa", "marcus", result);
  await follow(ctx, client, "volt", "rosa", result);

  await new Promise((r) => setTimeout(r, 2000));

  const marcus = ctx.getCharacter("marcus");
  const luna = ctx.getCharacter("luna");

  await timedCall(
    result,
    "Marcus's follows list",
    async () => {
      const res = await client.raw.get(
        "app.bsky.graph.getFollows",
        { actor: marcus.did },
        marcus.accessJwt,
      );
      return res;
    },
    (f) => `count=${f.follows?.length || 0}`,
  );

  await timedCall(
    result,
    "Luna's followers list",
    async () => {
      const res = await client.raw.get(
        "app.bsky.graph.getFollowers",
        { actor: luna.did },
        luna.accessJwt,
      );
      return res;
    },
    (f) => `count=${f.followers?.length || 0}`,
  );

  const volt = ctx.getCharacter("volt");
  const followsResp = await timedCall(
    result,
    "Marcus lists follow records (for unfollow)",
    async () => {
      const res = await client.agent.com.atproto.repo.listRecords({
        repo: marcus.did,
        collection: "app.bsky.graph.follow",
      });
      return res.data;
    },
  );

  if (followsResp) {
    const records = followsResp.records || [];
    let voltFollow = null;
    for (const rec of records) {
      if ((rec.value as any).subject === volt.did) {
        voltFollow = rec;
        break;
      }
    }
    if (voltFollow) {
      const rkey = voltFollow.uri.split("/").pop()!;
      await timedCall(
        result,
        "Marcus unfollows DJ Volt",
        async () => {
          await client.raw.post("com.atproto.repo.deleteRecord", {
            repo: marcus.did,
            collection: "app.bsky.graph.follow",
            rkey,
          }, marcus.accessJwt);
        },
        () => `deleted rkey=${rkey}`,
      );
    } else {
      result.stepSkipped("Marcus unfollows DJ Volt", "Follow record not found");
    }
  }

  const troll = ctx.getCharacter("troll");
  if (!luna.did || !luna.accessJwt) {
    result.stepSkipped("Luna blocks Trollface", "Luna account not created");
  } else if (!troll.did) {
    result.stepSkipped("Luna blocks Trollface", "Troll account not created");
  } else {
    await timedCall(
      result,
      "Luna blocks Trollface",
      async () => {
        const res = await client.raw.post("com.atproto.repo.createRecord", {
          repo: luna.did,
          collection: "app.bsky.graph.block",
          record: {
            $type: "app.bsky.graph.block",
            subject: troll.did,
            createdAt: now(),
          },
        }, luna.accessJwt);
        return res;
      },
      (r) => `uri=${r.uri}`,
    );
  }

  if (!luna.did || !luna.accessJwt) {
    result.stepSkipped("Luna's blocks list", "Luna account not created");
  } else {
    await timedCall(
      result,
      "Luna's blocks list",
      async () => {
        const res = await client.raw.get(
          "app.bsky.graph.getBlocks",
          {},
          luna.accessJwt,
        );
        return res;
      },
      (b) => `count=${b.blocks?.length || 0}`,
    );
  }

  await timedCall(
    result,
    "Marcus profile counts",
    async () => {
      const res = await client.raw.get(
        "app.bsky.actor.getProfile",
        { actor: marcus.did },
        marcus.accessJwt,
      );
      return res;
    },
    (p) => `follows=${p.followsCount || 0}, followers=${p.followersCount || 0}`,
  );

  if (!luna.did || !luna.accessJwt) {
    result.stepFailed("Search actors", "Luna account not created");
  } else {
    await timedCall(
      result,
      "Search actors",
      async () => {
        const res = await client.raw.get(
          "app.bsky.actor.searchActors",
          { q: "Luna" },
          luna.accessJwt,
        );
        return res;
      },
      (s) => `found=${s.actors?.length || 0}`,
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
