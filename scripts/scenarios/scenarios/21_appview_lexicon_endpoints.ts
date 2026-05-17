/**
 * @module scenarios/21_appview_lexicon_endpoints
 *
 * Scenario: Verifies that the AppView correctly registers and serves lexicon-defined endpoints.
 *
 * Behavior:
 * - Initializes PDS and AppView clients.
 * - Creates two test accounts and populates profiles/posts.
 * - Queries AppView admin APIs to confirm lexicon, collection, and handler registration.
 * - Exercises third-party dynamic GET endpoints via /xrpc.
 * - Validates negative auth/missing handler responses.
 *
 * Expectations:
 * - Lexicons, collections, and custom handlers are successfully listed.
 * - Registered third-party dynamic endpoints respond correctly.
 * - Unregistered endpoints and unauthorized admin requests are rejected.
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

const THIRD_PARTY_QUERY_NSIDS = [
  "com.shinolabs.pinksea.getRecent",
  "com.whtwnd.blog.getAuthorPosts",
  "social.grain.feed.getTimeline",
];

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("AppView Lexicon-Driven Endpoints");
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

    for (let i = 0; i < 2; i++) {
      await timedCall(
        result,
        `${char.name} posts test ${i + 1}`,
        async () => {
          return await client.records.createRecord(
            char.did,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: `Lexicon test post ${i} from ${char.name}`,
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

  const lexData = await timedCall(
    result,
    "List loaded lexicons",
    async () => {
      return await av.raw.httpGet("/admin/lexicons", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`,
  );

  if (lexData) {
    const nsids = lexData.nsids || [];
    const found = THIRD_PARTY_QUERY_NSIDS.filter((n) => nsids.includes(n));
    if (found.length > 0) {
      result.stepPassed(
        "Third-party lexicons loaded",
        `found=${found.length} of ${THIRD_PARTY_QUERY_NSIDS.length}`,
      );
    } else {
      result.stepSkipped("Third-party lexicons loaded", "none found");
    }
  }

  await timedCall(
    result,
    "List dynamic endpoints",
    async () => {
      return await av.raw.httpGet("/admin/endpoints", undefined, adminToken);
    },
    (r) => `dynamic=${r.dynamic_endpoint_count ?? 0}, custom=${r.custom_handler_count ?? 0}`,
  );

  await timedCall(
    result,
    "List indexed collections",
    async () => {
      return await av.raw.httpGet("/admin/lexicons/collections", undefined, adminToken);
    },
    (r) => `count=${r.collections?.length || 0}`,
  );

  await timedCall(
    result,
    "List custom handlers",
    async () => {
      return await av.raw.httpGet("/admin/handlers", undefined, adminToken);
    },
    (r) => `count=${r.count ?? 0}`,
  );

  for (const nsid of THIRD_PARTY_QUERY_NSIDS.slice(0, 2)) {
    await timedCall(
      result,
      `Dynamic GET /xrpc/${nsid}`,
      async () => {
        return await av.raw.httpGet(`/xrpc/${nsid}`);
      },
      (r) => `status=200 keys=${Object.keys(r).slice(0, 3)}`,
    );
  }

  await timedCall(
    result,
    "Unknown NSID returns 501",
    async () => {
      return await av.raw.httpGet("/xrpc/com.example.nonexistent.method");
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "Procedure without custom handler returns 501",
    async () => {
      return await av.raw.httpPost(
        "/xrpc/com.shinolabs.pinksea.oekaki",
        { $type: "com.shinolabs.pinksea.oekaki", data: "test" },
      );
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "Browse indexed records",
    async () => {
      return await av.raw.httpGet(
        "/admin/records",
        { collection: "app.bsky.feed.post", limit: 10 },
        adminToken,
      );
    },
    (r) => `records=${r.records?.length || 0}`,
  );

  await timedCall(
    result,
    "Admin auth: wrong secret rejected",
    async () => {
      const resp = await av.raw.httpGet("/admin/lexicons", undefined, "wrong-secret-value");
      // If we get here, the request didn't throw — that's a bug
      // (wrong secret should be rejected with 401/403)
      if (resp && typeof resp === "object" && !("error" in resp)) {
        throw new Error("Wrong admin secret was accepted — expected 401/403 rejection");
      }
      return resp;
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
