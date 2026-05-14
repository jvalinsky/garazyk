import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter, PDS_ADMIN_PASSWORD } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Moderation & Safety");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result, "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    }
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "troll", "admin", "mod"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({ handle: char.handle, email: char.email, password: char.password });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({ identifier: char.handle, password: char.password });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const luna = getCharacter("luna");
  const troll = getCharacter("troll");
  const admin = getCharacter("admin");
  const mod = getCharacter("mod");

  if (!luna.did || !troll.did || !admin.did || !mod.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  const adminPassword = PDS_ADMIN_PASSWORD;
  const adminToken = await timedCall(
    result, "Admin login",
    async () => {
      return await client.adminLogin(adminPassword);
    },
    () => "obtained admin bearer"
  );

  for (const name of charNames) {
    const char = getCharacter(name);
    await timedCall(
      result, `Set profile: ${char.name}`,
      async () => {
        await client.raw.post("com.atproto.repo.createRecord", {
          repo: char.did,
          collection: "app.bsky.actor.profile",
          record: {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
          }
        }, char.accessJwt);
      }
    );
  }

  const lunaPost = await timedCall(
    result, "Luna posts stargazing content",
    async () => {
      const res = await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Beautiful night for stargazing! The Milky Way is visible tonight.",
          createdAt: now()
        }
      }, luna.accessJwt);
      return res;
    }
  );

  const trollSpam = await timedCall(
    result, "Trollface posts spam",
    async () => {
      const res = await client.raw.post("com.atproto.repo.createRecord", {
        repo: troll.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "BUY CRYPTO NOW!!! FREE MONEY!!! CLICK HERE!!!",
          createdAt: now()
        }
      }, troll.accessJwt);
      return res;
    }
  );

  let trollHarass = null;
  if (lunaPost) {
    trollHarass = await timedCall(
      result, "Trollface harasses Luna",
      async () => {
        const res = await client.raw.post("com.atproto.repo.createRecord", {
          repo: troll.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Your stargazing is stupid and nobody cares. Get a life, loser!",
            createdAt: now(),
            reply: {
              root: { uri: lunaPost.uri, cid: lunaPost.cid },
              parent: { uri: lunaPost.uri, cid: lunaPost.cid }
            }
          }
        }, troll.accessJwt);
        return res;
      }
    );
  }

  if (trollHarass) {
    await timedCall(
      result, "Luna reports harassment",
      async () => {
        const res = await client.raw.post("com.atproto.moderation.createReport", {
          reasonType: "com.atproto.moderation.defs#reasonRude",
          subject: {
            $type: "com.atproto.repo.strongRef",
            uri: trollHarass.uri,
            cid: trollHarass.cid
          },
          reason: "Targeted harassment and personal attacks"
        }, luna.accessJwt);
        return res;
      },
      (r) => `report_id=${r.id}`
    );
  } else {
    result.stepFailed("Luna reports harassment", "No harassment post to report");
  }

  if (trollSpam) {
    await timedCall(
      result, "Luna reports spam",
      async () => {
        const res = await client.raw.post("com.atproto.moderation.createReport", {
          reasonType: "com.atproto.moderation.defs#reasonSpam",
          subject: {
            $type: "com.atproto.repo.strongRef",
            uri: trollSpam.uri,
            cid: trollSpam.cid
          },
          reason: "Spam content — crypto scam"
        }, luna.accessJwt);
        return res;
      },
      (r) => `report_id=${r.id}`
    );
  }

  if (adminToken) {
    await timedCall(
      result, "Admin checks Trollface status",
      async () => {
        return await client.raw.get("com.atproto.admin.getSubjectStatus", { did: troll.did }, adminToken);
      },
      (s) => `status=${JSON.stringify(s)}`
    );
  } else {
    result.stepFailed("Admin checks Trollface status", "No admin token");
  }

  if (adminToken) {
    await timedCall(
      result, "Mod queries reports via Ozone",
      async () => {
        return await client.raw.get("tools.ozone.moderation.queryEvents", {
          types: "tools.ozone.moderation.defs#modEventReport",
          subject: troll.did
        }, adminToken);
      },
      (e) => `count=${e.events?.length || 0}`
    );
  } else {
    result.stepFailed("Mod queries reports via Ozone", "No admin token");
  }

  if (trollHarass && adminToken) {
    await timedCall(
      result, "Mod applies takedown via Ozone",
      async () => {
        await client.raw.post("tools.ozone.moderation.emitEvent", {
          event: {
            $type: "tools.ozone.moderation.defs#modEventTakedown",
            comment: "Harassment and spam — takedown applied by Mod Justice"
          },
          subject: {
            $type: "com.atproto.admin.defs#repoRef",
            did: troll.did
          },
          createdBy: mod.did
        }, adminToken);
      }
    );
  }

  if (adminToken) {
    await timedCall(
      result, "Admin applies takedown on Trollface",
      async () => {
        await client.raw.post("com.atproto.admin.updateSubjectStatus", {
          subject: {
            $type: "com.atproto.admin.defs#repoRef",
            did: troll.did
          },
          takedown: {
            applied: true,
            ref: "takedown-harassment-spam"
          }
        }, adminToken);
      }
    );
  } else {
    result.stepFailed("Admin applies takedown on Trollface", "No admin token");
  }

  if (adminToken) {
    await timedCall(
      result, "Labels query",
      async () => {
        return await client.raw.get("com.atproto.label.queryLabels", {
          uriPatterns: trollHarass ? [trollHarass.uri] : []
        }, adminToken); // Using queryLabels or getLabels? Usually queryLabels is the newer endpoint, let's try getLabels with array
      },
      (l) => `labels=${JSON.stringify(l)}`
    );
  } else {
    result.stepFailed("Labels query", "No admin token");
  }

  if (trollHarass) {
    await timedCall(
      result, "Taken-down content is inaccessible",
      async () => {
        const rkey = trollHarass.uri.split("/").pop()!;
        await client.agent.com.atproto.repo.getRecord({
          repo: troll.did,
          collection: "app.bsky.feed.post",
          rkey
        });
      },
      undefined,
      true
    );
  } else {
    result.stepFailed("Taken-down content check", "No harassment post to verify");
  }

  await timedCall(
    result, "Admin posts community notice",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: admin.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "We've taken action against a spam/harassment account. Stay safe, everyone!",
          createdAt: now()
        }
      }, admin.accessJwt);
    }
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
