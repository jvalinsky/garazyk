/**
 * @module scenarios/18_admin_operations
 *
 * Scenario: AppView Admin Operations
 *
 * Behavior:
 * - Initialize test accounts and perform some initial activity.
 * - Call various administrative endpoints (ingest health, backfill status/queue, metrics, lexicons, records, etc.) using admin token.
 * - Verify that unauthenticated admin requests are rejected.
 *
 * Expectations:
 * - Admin endpoints are accessible with valid credentials and return expected operational status/metrics.
 * - Unauthorized requests receive error responses.
 */

import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext } from "@garazyk/hamownia";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Admin Operations");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const avUrl = ctx.serviceUrls.appview;
  const adminToken = ctx.appviewAdminSecret;
  const av = new XrpcClient(avUrl);

  const charNames = ["luna", "marcus"];
  for (const name of charNames) {
    const char = ctx.getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(
          char.handle,
          char.email,
          char.password,
        );
      },
      (s: any) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => ctx.getCharacter(n).did);
  if (active.length > 0) {
    for (const name of active) {
      const char = ctx.getCharacter(name);
      await timedCall(result, `Set profile: ${char.name}`, async () => {
        return await client.records.createRecord(
          char.did,
          "app.bsky.actor.profile",
          { $type: "app.bsky.actor.profile", displayName: char.name },
          char.accessJwt,
        );
      });
    }

    for (let i = 0; i < 3; i++) {
      for (const name of active) {
        const char = ctx.getCharacter(name);
        await timedCall(
          result,
          `${char.name} posts test ${i + 1}`,
          async () => {
            return await client.records.createRecord(
              char.did,
              "app.bsky.feed.post",
              {
                $type: "app.bsky.feed.post",
                text: `Test post ${i} from ${name}`,
                createdAt: now(),
              },
              char.accessJwt,
            );
          },
          (r: any) => `uri=${r.uri}`,
        );
      }
    }
    await new Promise((r) => setTimeout(r, 2000));
  }

  await timedCall(
    result,
    "Ingest engine health",
    async () => {
      return await av.raw.httpGet(
        "/admin/ingest/health",
        undefined,
        adminToken,
      );
    },
    (r: any) => `running=${r.running ?? false}`,
  );

  await timedCall(
    result,
    "Backfill status",
    async () => {
      return await av.raw.httpGet(
        "/admin/backfill/status",
        undefined,
        adminToken,
      );
    },
    (r: any) => `enabled=${r.enabled ?? false}`,
  );

  await timedCall(
    result,
    "Backfill queue",
    async () => {
      return await av.raw.httpGet(
        "/admin/backfill/queue",
        { limit: 10 },
        adminToken,
      );
    },
    (r: any) => `entries=${r.entries?.length || 0}, total=${r.total ?? 0}`,
  );

  await timedCall(
    result,
    "Metrics stats",
    async () => {
      return await av.raw.httpGet(
        "/admin/appview/metrics/stats",
        undefined,
        adminToken,
      );
    },
    (r: any) => `repos_total=${r.repos?.total || 0}, queue_depth=${r.queue_depth || 0}`,
  );

  await timedCall(
    result,
    "List lexicons",
    async () => {
      return await av.raw.httpGet("/admin/lexicons", undefined, adminToken);
    },
    (r: any) => `count=${r.count ?? 0}`,
  );

  await timedCall(
    result,
    "List collections",
    async () => {
      return await av.raw.httpGet(
        "/admin/lexicons/collections",
        undefined,
        adminToken,
      );
    },
    (r: any) => `count=${r.collections?.length || 0}`,
  );

  await timedCall(
    result,
    "Browse records",
    async () => {
      return await av.raw.httpGet(
        "/admin/records",
        { collection: "app.bsky.feed.post", limit: 10 },
        adminToken,
      );
    },
    (r: any) => `records=${r.records?.length || 0}`,
  );

  await timedCall(
    result,
    "Browse records without collection rejected",
    async () => {
      return await av.raw.httpGet("/admin/records", undefined, adminToken);
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "List endpoints",
    async () => {
      return await av.raw.httpGet("/admin/endpoints", undefined, adminToken);
    },
    (r: any) => `dynamic=${r.dynamic_endpoint_count ?? 0}, custom=${
        r.custom_handler_count ?? 0
      }`,
  );

  await timedCall(
    result,
    "List hooks",
    async () => {
      return await av.raw.httpGet("/admin/hooks", undefined, adminToken);
    },
    (r: any) => `count=${r.count ?? 0}`,
  );

  await timedCall(
    result,
    "Dead letter hooks",
    async () => {
      return await av.raw.httpGet(
        "/admin/hooks/dead-letter",
        { limit: 10 },
        adminToken,
      );
    },
    (r: any) => `entries=${r.entries?.length || 0}`,
  );

  await timedCall(
    result,
    "List handlers",
    async () => {
      return await av.raw.httpGet("/admin/handlers", undefined, adminToken);
    },
    (r: any) => `count=${r.count ?? 0}`,
  );

  await timedCall(
    result,
    "Backfill scope rebuild",
    async () => {
      return await av.raw.httpPost(
        "/admin/backfill/scope/rebuild",
        undefined,
        adminToken,
      );
    },
    (r: any) => `success=${r.success ?? false}`,
  );

  await timedCall(
    result,
    "Admin access without token",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status");
    },
    undefined,
    true,
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
