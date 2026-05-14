import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, APPVIEW_ADMIN_SECRET, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Admin Operations");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const avUrl = SERVICE_URLS.appview;
  const adminToken = APPVIEW_ADMIN_SECRET;
  const av = new XrpcClient(avUrl);

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
  if (active.length > 0) {
    for (const name of active) {
      const char = getCharacter(name);
      await timedCall(result, `Set profile: ${char.name}`, async () => {
        return await client.records.createRecord(
          char.did, "app.bsky.actor.profile",
          { $type: "app.bsky.actor.profile", displayName: char.name },
          char.accessJwt
        );
      });
    }

    for (let i = 0; i < 3; i++) {
      for (const name of active) {
        const char = getCharacter(name);
        await timedCall(
          result, `${char.name} posts test ${i + 1}`,
          async () => {
            return await client.records.createRecord(
              char.did, "app.bsky.feed.post",
              { $type: "app.bsky.feed.post", text: `Test post ${i} from ${name}`, createdAt: now() },
              char.accessJwt
            );
          },
          (r) => `uri=${r.uri}`
        );
      }
    }
    await new Promise(r => setTimeout(r, 2000));
  }

  await timedCall(
    result, "Ingest engine health",
    async () => {
      return await av.raw.httpGet("/admin/ingest/health", undefined, adminToken);
    },
    (r) => `running=${r.running ?? false}`
  );

  await timedCall(
    result, "Backfill status",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status", undefined, adminToken);
    },
    (r) => `enabled=${r.enabled ?? false}`
  );

  await timedCall(
    result, "Backfill queue",
    async () => {
      return await av.raw.httpGet("/admin/backfill/queue", { limit: 10 }, adminToken);
    },
    (r) => `entries=${r.entries?.length || 0}, total=${r.total ?? 0}`
  );

  await timedCall(
    result, "Metrics stats",
    async () => {
      return await av.raw.httpGet("/admin/appview/metrics/stats", undefined, adminToken);
    },
    (r) => `repos_total=${r.repos?.total || 0}, queue_depth=${r.queue_depth || 0}`
  );

  await timedCall(
    result, "List lexicons",
    async () => {
      return await av.raw.httpGet("/admin/lexicons", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`
  );

  await timedCall(
    result, "List collections",
    async () => {
      return await av.raw.httpGet("/admin/lexicons/collections", undefined, adminToken);
    },
    (r) => `count=${r.collections?.length || 0}`
  );

  await timedCall(
    result, "Browse records",
    async () => {
      return await av.raw.httpGet("/admin/records", { collection: "app.bsky.feed.post", limit: 10 }, adminToken);
    },
    (r) => `records=${r.records?.length || 0}`
  );

  await timedCall(
    result, "Browse records without collection rejected",
    async () => {
      return await av.raw.httpGet("/admin/records", undefined, adminToken);
    },
    undefined,
    true
  );

  await timedCall(
    result, "List endpoints",
    async () => {
      return await av.raw.httpGet("/admin/endpoints", undefined, adminToken);
    },
    (r) => `dynamic=${r.dynamic_endpoint_count ?? 0}, custom=${r.custom_handler_count ?? 0}`
  );

  await timedCall(
    result, "List hooks",
    async () => {
      return await av.raw.httpGet("/admin/hooks", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`
  );

  await timedCall(
    result, "Dead letter hooks",
    async () => {
      return await av.raw.httpGet("/admin/hooks/dead-letter", { limit: 10 }, adminToken);
    },
    (r) => `entries=${r.entries?.length || 0}`
  );

  await timedCall(
    result, "List handlers",
    async () => {
      return await av.raw.httpGet("/admin/handlers", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`
  );

  await timedCall(
    result, "Backfill scope rebuild",
    async () => {
      return await av.raw.httpPost("/admin/backfill/scope/rebuild", undefined, adminToken);
    },
    (r) => `success=${r.success ?? false}`
  );

  await timedCall(
    result, "Admin access without token",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status");
    },
    undefined,
    true
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
