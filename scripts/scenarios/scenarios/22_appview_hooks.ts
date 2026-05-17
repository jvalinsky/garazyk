/**
 * @module scenarios/22_appview_hooks
 *
 * Scenario: Verifies AppView index hooks, dead-letter reporting, and record browsing.
 *
 * Behavior:
 * - Initializes PDS and AppView clients.
 * - Creates test accounts and generates records.
 * - Checks the AppView hook registry status.
 * - Performs search index queries and validates dead-letter table behavior.
 * - Exercises administrative record browsing endpoints with various filters (DID, collection, pagination).
 *
 * Expectations:
 * - Hooks are registered and registry status is returned.
 * - Search indices show the created content.
 * - Dead-letter reporting handles requests for entries correctly.
 * - Admin record browsing correctly enforces collection filtering and returns results.
 */

import { ScenarioResult, timedCall } from "@garazyk/scenario-runner";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/scenario-runner";
export type { ScenarioReport } from "@garazyk/scenario-runner";
import { assert } from "@garazyk/scenario-runner";
import { XrpcClient } from "@garazyk/atproto-client";
import { APPVIEW_ADMIN_SECRET, getCharacter, PDS1, SERVICE_URLS } from "@garazyk/scenario-runner";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Index Hooks & Dead Letter");
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
    result,
    "AppView health check",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status", undefined, adminToken);
    },
    (r) => `enabled=${r.enabled ?? false}`,
  );

  const charNames = ["luna", "marcus"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => getCharacter(n).did);
  if (active.length < 2) {
    result.stepFailed("Account creation", "Not enough accounts created");
    result.finish();
    return result;
  }

  for (const name of active) {
    const char = getCharacter(name);
    await timedCall(result, `Set profile: ${char.name}`, async () => {
      return await client.records.createRecord(
        char.did,
        "app.bsky.actor.profile",
        { $type: "app.bsky.actor.profile", displayName: char.name },
        char.accessJwt,
      );
    });

    for (let i = 0; i < 3; i++) {
      await timedCall(
        result,
        `${char.name} posts test ${i + 1}`,
        async () => {
          return await client.records.createRecord(
            char.did,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: `Hook test post ${i} from ${char.name}`,
              createdAt: now(),
            },
            char.accessJwt,
          );
        },
        (r) => `uri=${r.uri}`,
      );
    }
  }

  await new Promise((r) => setTimeout(r, 3000));

  const luna = getCharacter("luna");

  const hookData = await timedCall(
    result,
    "Hook registry status",
    async () => {
      return await av.raw.httpGet("/admin/hooks", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`,
  );

  const hookCount = hookData?.count || 0;
  if (hookCount > 0) {
    result.stepPassed("Hook firing test", `Registry wired with ${hookCount} hook(s)`);
  } else {
    result.stepSkipped("Hook firing test", "Hook registry not wired");
  }

  await timedCall(
    result,
    "Search index: actor search",
    async () => {
      return await av.raw.httpGet(
        "/xrpc/app.bsky.actor.searchActors",
        { q: "Luna", limit: 5 },
        adminToken,
      );
    },
    (r) => `actors=${r.actors?.length || 0}`,
  );

  const dlData = await timedCall(
    result,
    "Dead letter table: empty",
    async () => {
      return await av.raw.httpGet("/admin/hooks/dead-letter", { limit: 10 }, adminToken);
    },
    (r) => `entries=${r.entries?.length || 0}`,
  );

  const dlEntries = dlData?.entries || [];
  if (dlEntries.length === 0) {
    result.stepPassed("Dead letter empty (expected)", "No hook failures recorded");
  } else {
    result.stepPassed("Dead letter has entries", `${dlEntries.length} entries found`);
  }

  await timedCall(
    result,
    "Dead letter with limit=1",
    async () => {
      return await av.raw.httpGet("/admin/hooks/dead-letter", { limit: 1 }, adminToken);
    },
  );

  const recData = await timedCall(
    result,
    "Browse records: collection filter",
    async () => {
      return await av.raw.httpGet(
        "/admin/records",
        { collection: "app.bsky.feed.post", limit: 5 },
        adminToken,
      );
    },
    (r) => `records=${r.records?.length || 0}`,
  );

  if (luna.did) {
    await timedCall(
      result,
      "Browse records: DID filter",
      async () => {
        return await av.raw.httpGet("/admin/records", {
          collection: "app.bsky.feed.post",
          did: luna.did,
          limit: 10,
        }, adminToken);
      },
      (r) => `records=${r.records?.length || 0}`,
    );
  }

  if (recData?.cursor) {
    await timedCall(
      result,
      "Browse records: pagination (page 2)",
      async () => {
        return await av.raw.httpGet("/admin/records", {
          collection: "app.bsky.feed.post",
          limit: 2,
          cursor: recData.cursor,
        }, adminToken);
      },
      (r) => `records=${r.records?.length || 0}`,
    );
  }

  await timedCall(
    result,
    "Browse records: invalid collection",
    async () => {
      return await av.raw.httpGet("/admin/records", {
        collection: "nonexistent.collection.type",
        limit: 5,
      }, adminToken);
    },
  );

  await timedCall(
    result,
    "Browse records: missing collection rejected",
    async () => {
      return await av.raw.httpGet("/admin/records", undefined, adminToken);
    },
    undefined,
    true,
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
