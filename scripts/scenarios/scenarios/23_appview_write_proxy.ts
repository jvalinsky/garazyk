import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, APPVIEW_ADMIN_SECRET, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Write Proxy & OAuth2");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const avUrl = SERVICE_URLS.appview;
  const adminToken = APPVIEW_ADMIN_SECRET;
  const av = new XrpcClient(avUrl);

  await timedCall(
    result, "AppView health check",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status", undefined, adminToken);
    },
    (r) => `enabled=${r.enabled ?? false}`
  );

  const charNames = ["luna", "marcus"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter(n => getCharacter(n).did);
  if (active.length < 1) {
    result.stepFailed("Account creation", "No accounts created");
    result.finish();
    return result;
  }

  for (const name of active) {
    const char = getCharacter(name);
    try {
      await client.records.createRecord(
        char.did, "app.bsky.actor.profile",
        { $type: "app.bsky.actor.profile", displayName: char.name },
        char.accessJwt
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  const luna = getCharacter("luna");
  if (luna.did && luna.accessJwt) {
    await timedCall(
      result, "Luna creates a post",
      async () => {
        return await client.records.createRecord(
          luna.did, "app.bsky.feed.post",
          { $type: "app.bsky.feed.post", text: "Write proxy test post from Luna", createdAt: now() },
          luna.accessJwt
        );
      },
      (r) => `uri=${r.uri}`
    );
  }

  await new Promise(r => setTimeout(r, 3000));

  await timedCall(
    result, "Backfill status",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status", undefined, adminToken);
    }
  );

  await timedCall(
    result, "Ingest engine health",
    async () => {
      return await av.raw.httpGet("/admin/ingest/health", undefined, adminToken);
    }
  );

  if (luna.did && luna.accessJwt) {
    await timedCall(
      result, "Write proxy: createRecord on AppView (unwired)",
      async () => {
        return await av.raw.httpPost(
          "/xrpc/com.atproto.repo.createRecord",
          {
            repo: luna.did,
            collection: "app.bsky.feed.post",
            record: {
              $type: "app.bsky.feed.post",
              text: "Proxied post attempt",
              createdAt: now(),
            },
          },
          luna.accessJwt
        );
      }
    );

    await timedCall(
      result, "OAuth2: valid Bearer token on AppView",
      async () => {
        return await av.raw.httpGet(
          "/xrpc/app.bsky.actor.getProfile",
          { actor: luna.did },
          luna.accessJwt
        );
      },
      (r) => `handle=${r.handle || "unknown"}`
    );
  }

  if (luna.did) {
    await timedCall(
      result, "OAuth2: DID-as-token on AppView",
      async () => {
        return await av.raw.httpGet(
          "/xrpc/app.bsky.actor.getProfile",
          { actor: luna.did },
          luna.did
        );
      },
      (r) => `status=200`
    );
  }

  await timedCall(
    result, "OAuth2: invalid Bearer token on AppView",
    async () => {
      return await av.raw.httpGet(
        "/xrpc/app.bsky.actor.getProfile",
        { actor: luna.did || "did:plc:unknown" },
        "invalid-garbage-token-xyz"
      );
    }
  );

  await timedCall(
    result, "Endpoint counts after operations",
    async () => {
      return await av.raw.httpGet("/admin/endpoints", undefined, adminToken);
    }
  );

  await timedCall(
    result, "AppView metrics",
    async () => {
      return await av.raw.httpGet("/admin/appview/metrics/stats", undefined, adminToken);
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
