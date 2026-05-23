/**
 * @module scenarios/04_moderation_safety
 *
 * Scenario: Moderation and safety operations (reporting, event processing, takedowns)
 *
 * Behavior:
 * - Create test users, an admin, and a moderator
 * - Trollface posts spam and harasses Luna
 * - Luna reports the spam and harassment
 * - Mod queries reports and applies a takedown
 * - Admin applies account status update and labels
 * - Verify that taken-down content is inaccessible
 *
 * Expectations:
 * - Reporting works and is accessible to moderators
 * - Takedown events are emitted and applied successfully
 * - Taken-down content is properly enforced and inaccessible to users
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, PDS_ADMIN_PASSWORD } from "../../lib/deno/config.ts";
import { createAccountOrLogin, now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Moderation & Safety");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      await client.raw.xrpcGet("com.atproto.server.describeServer");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "troll", "admin", "mod"];
  for (const name of charNames) {
    const char = getActor(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      () => createAccountOrLogin(client, char),
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const luna = getActor("luna");
  const troll = getActor("troll");
  const admin = getActor("admin");
  const mod = getActor("mod");

  if (!luna.did || !troll.did || !admin.did || !mod.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  const adminPassword = PDS_ADMIN_PASSWORD;
  const adminToken = await timedCall(
    result,
    "Admin login",
    async () => {
      return await client.adminLogin(adminPassword);
    },
    () => "obtained admin bearer",
  );

  for (const name of charNames) {
    const char = getActor(name);
    await timedCall(
      result,
      `Set profile: ${char.name}`,
      async () => {
        await client.as(char).raw.post("com.atproto.repo.createRecord", {
          repo: char.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
          },
        });
      },
    );
  }

  const lunaPost = await timedCall(
    result,
    "Luna posts stargazing content",
    async () => {
      const res = await client.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Beautiful night for stargazing! The Milky Way is visible tonight.",
          createdAt: now(),
        },
      });
      return res;
    },
  );

  const trollSpam = await timedCall(
    result,
    "Trollface posts spam",
    async () => {
      const res = await client.as(troll).raw.post("com.atproto.repo.createRecord", {
        repo: troll.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "BUY CRYPTO NOW!!! FREE MONEY!!! CLICK HERE!!!",
          createdAt: now(),
        },
      });
      return res;
    },
  );

  let trollHarass = null;
  if (lunaPost) {
    trollHarass = await timedCall(
      result,
      "Trollface harasses Luna",
      async () => {
        const res = await client.as(troll).raw.post("com.atproto.repo.createRecord", {
          repo: troll.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Your stargazing is stupid and nobody cares. Get a life, loser!",
            createdAt: now(),
            reply: {
              root: { uri: lunaPost.uri, cid: lunaPost.cid },
              parent: { uri: lunaPost.uri, cid: lunaPost.cid },
            },
          },
        });
        return res;
      },
    );
  }

  if (trollHarass) {
    await timedCall(
      result,
      "Luna reports harassment",
      async () => {
        const res = await client.as(luna).raw.post("com.atproto.moderation.createReport", {
          reasonType: "com.atproto.moderation.defs#reasonRude",
          subject: {
            $type: "com.atproto.repo.strongRef",
            uri: trollHarass.uri,
            cid: trollHarass.cid,
          },
          reason: "Targeted harassment and personal attacks",
        });
        return res;
      },
      (r) => `report_id=${r.id}`,
    );
  } else {
    result.stepFailed("Luna reports harassment", "No harassment post to report");
  }

  if (trollSpam) {
    await timedCall(
      result,
      "Luna reports spam",
      async () => {
        const res = await client.as(luna).raw.post("com.atproto.moderation.createReport", {
          reasonType: "com.atproto.moderation.defs#reasonSpam",
          subject: {
            $type: "com.atproto.repo.strongRef",
            uri: trollSpam.uri,
            cid: trollSpam.cid,
          },
          reason: "Spam content — crypto scam",
        });
        return res;
      },
      (r) => `report_id=${r.id}`,
    );
  }

  if (adminToken) {
    await timedCall(
      result,
      "Admin checks Trollface status",
      async () => {
        return await client.asAdmin(adminToken).raw.get(
          "com.atproto.admin.getSubjectStatus",
          { did: troll.did },
        );
      },
      (s) => `status=${JSON.stringify(s)}`,
    );
  } else {
    result.stepFailed("Admin checks Trollface status", "No admin token");
  }

  if (adminToken) {
    await timedCall(
      result,
      "Mod queries reports via Ozone",
      async () => {
        return await client.asAdmin(adminToken).raw.get("tools.ozone.moderation.queryEvents", {
          types: "tools.ozone.moderation.defs#modEventReport",
          subject: troll.did,
        });
      },
      (e) => `count=${e.events?.length || 0}`,
    );
  } else {
    result.stepFailed("Mod queries reports via Ozone", "No admin token");
  }

  if (trollHarass && adminToken) {
    await timedCall(
      result,
      "Mod applies takedown via Ozone",
      async () => {
        await client.asAdmin(adminToken).raw.post("tools.ozone.moderation.emitEvent", {
          event: {
            $type: "tools.ozone.moderation.defs#modEventTakedown",
            comment: "Harassment and spam — takedown applied by Mod Justice",
          },
          subject: {
            $type: "com.atproto.admin.defs#repoRef",
            did: troll.did,
          },
          createdBy: mod.did,
        });
      },
    );
  }

  if (adminToken) {
    await timedCall(
      result,
      "Admin applies takedown on Trollface",
      async () => {
        await client.asAdmin(adminToken).raw.post("com.atproto.admin.updateSubjectStatus", {
          subject: {
            $type: "com.atproto.admin.defs#repoRef",
            did: troll.did,
          },
          takedown: {
            applied: true,
            ref: "takedown-harassment-spam",
          },
        });
      },
    );
  } else {
    result.stepFailed("Admin applies takedown on Trollface", "No admin token");
  }

  if (adminToken) {
    await timedCall(
      result,
      "Labels query",
      async () => {
        return await client.asAdmin(adminToken).raw.get("com.atproto.label.queryLabels", {
          uriPatterns: trollHarass ? [trollHarass.uri] : [],
        });
      },
      (l) => `labels=${JSON.stringify(l)}`,
    );
  } else {
    result.stepFailed("Labels query", "No admin token");
  }

  if (trollHarass) {
    await timedCall(
      result,
      "Taken-down content is inaccessible",
      async () => {
        const rkey = trollHarass.uri.split("/").pop()!;
        await client.agent.com.atproto.repo.getRecord({
          repo: troll.did,
          collection: "app.bsky.feed.post",
          rkey,
        });
      },
      undefined,
      true,
    );
  } else {
    result.stepFailed("Taken-down content check", "No harassment post to verify");
  }

  await timedCall(
    result,
    "Admin posts community notice",
    async () => {
      await client.as(admin).raw.post("com.atproto.repo.createRecord", {
        repo: admin.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "We've taken action against a spam/harassment account. Stay safe, everyone!",
          createdAt: now(),
        },
      });
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
