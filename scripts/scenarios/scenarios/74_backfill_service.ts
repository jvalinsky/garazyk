/**
 * @module scenarios/74_backfill_service
 *
 * Scenario: Backfill service repair, queue monitoring, and scope management.
 *
 * Behavior:
 * - Checks backfill health/status endpoints via AppView admin API.
 * - Creates content on PDS and monitors backfill queue for entries.
 * - Triggers backfill scope rebuild and verifies state changes.
 * - Tests auth enforcement on backfill endpoints.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { now, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import {
  APPVIEW_ADMIN_SECRET,
  getActor,
  PDS1,
  SERVICE_URLS,
} from "../../lib/deno/config.ts";


/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Backfill Service Repair and Queue");
  result.start();

  const pds = new XrpcClient(PDS1);
  const avUrl = SERVICE_URLS.appview;
  const av = new XrpcClient(avUrl);
  const adminToken = APPVIEW_ADMIN_SECRET;

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "AppView health check", async () => {
    const status = await av.raw.httpGet(
      "/admin/backfill/status",
      undefined,
      adminToken,
    );
    assert.isTrue(status !== undefined, "expected AppView backfill status");
    return status;
  }, (s) => `enabled=${s.enabled ?? false}`);

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Setup accounts
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await pds.accounts
          .createAccount(char.handle, char.email, char.password)
          .catch(() => pds.accounts.createSession(char.handle, char.password));
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID after account creation");
    result.finish();
    return result;
  }

  // Create some posts so backfill queue gets populated
  for (const char of [luna, marcus]) {
    await timedCall(
      result,
      `${char.name} creates posts for backfill`,
      async () => {
        for (let i = 0; i < 3; i++) {
          await pds.records.createRecord(
            char.did!,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: `Backfill test post ${i + 1} from ${char.name} at ${now()}`,
              createdAt: now(),
            },
            char.accessJwt!,
          );
        }
      },
    );
  }

  // Brief pause for relay propagation
  await new Promise((r) => setTimeout(r, 2000));

  // --- Backfill admin endpoint tests ---

  await timedCall(
    result,
    "Backfill status endpoint",
    async () => {
      const resp = await av.raw.httpGet(
        "/admin/backfill/status",
        undefined,
        adminToken,
      );
      assert.isTrue(
        resp !== undefined && resp !== null,
        "expected backfill status response",
      );
      return resp;
    },
    (r) => `enabled=${r.enabled ?? false}`,
  );

  await timedCall(
    result,
    "Backfill queue endpoint",
    async () => {
      const resp = await av.raw.httpGet(
        "/admin/backfill/queue",
        { limit: 20 },
        adminToken,
      );
      // Queue may be empty or have entries — either is valid
      assert.isTrue(
        Array.isArray(resp.entries) || resp.total !== undefined,
        "expected backfill queue entries or total field",
      );
      return resp;
    },
    (r) => `entries=${r.entries?.length || 0}, total=${r.total ?? 0}`,
  );

  await timedCall(
    result,
    "Backfill scope rebuild",
    async () => {
      const resp = await av.raw.httpPost(
        "/admin/backfill/scope/rebuild",
        undefined,
        adminToken,
      );
      return resp;
    },
    (r) => `success=${r.success ?? false}`,
  );

  // Verify backfill status still readable after rebuild
  await timedCall(
    result,
    "Backfill status after scope rebuild",
    async () => {
      const resp = await av.raw.httpGet(
        "/admin/backfill/status",
        undefined,
        adminToken,
      );
      assert.isTrue(
        resp !== undefined,
        "expected backfill status after rebuild",
      );
      return resp;
    },
    (r) => `enabled=${r.enabled ?? false}`,
  );

  // --- Auth enforcement ---

  await timedCall(
    result,
    "Backfill status rejects unauthenticated request",
    async () => {
      return await av.raw.httpGet("/admin/backfill/status");
    },
    undefined,
    true, // expect error
  );

  await timedCall(
    result,
    "Backfill queue rejects unauthenticated request",
    async () => {
      return await av.raw.httpGet("/admin/backfill/queue", { limit: 5 });
    },
    undefined,
    true, // expect error
  );

  await timedCall(
    result,
    "Backfill scope rebuild rejects unauthenticated",
    async () => {
      return await av.raw.httpPost("/admin/backfill/scope/rebuild");
    },
    undefined,
    true, // expect error
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
