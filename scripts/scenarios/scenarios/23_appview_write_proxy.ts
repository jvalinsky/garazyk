/**
 * @module scenarios/23_appview_write_proxy
 *
 * Scenario: Verifies the AppView write proxy capability and OAuth2 authentication handling.
 *
 * Behavior:
 * - Initializes PDS and AppView clients.
 * - Creates/updates user accounts and profiles.
 * - Performs record creation via both PDS direct and AppView proxy routes.
 * - Tests OAuth2/Bearer token validation on AppView endpoints (profile lookups).
 * - Queries AppView admin metrics, ingest health, and endpoint stats.
 *
 * Expectations:
 * - Direct PDS record creation succeeds.
 * - AppView proxy correctly accepts or denies repo modification attempts.
 * - OAuth2 tokens are correctly validated for public and authed AppView endpoints.
 * - Admin diagnostic endpoints return valid metrics.
 */

import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
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
  const result = new ScenarioResult("AppView Write Proxy & OAuth2");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const avUrl = ctx.serviceUrls.appview;
  const adminToken = ctx.appviewAdminSecret;
  const av = new XrpcClient(avUrl);

  await timedCall(
    result,
    "AppView health check",
    async () => {
      return await av.raw.httpGet(
        "/admin/backfill/status",
        undefined,
        adminToken,
      );
    },
    (r: any) => `enabled=${r.enabled ?? false}`,
  );

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
  if (active.length < 1) {
    result.stepFailed("Account creation", "No accounts created");
    result.finish();
    return result;
  }

  for (const name of active) {
    const char = ctx.getCharacter(name);
    try {
      await client.records.createRecord(
        char.did,
        "app.bsky.actor.profile",
        { $type: "app.bsky.actor.profile", displayName: char.name },
        char.accessJwt,
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  const luna = ctx.getCharacter("luna");
  if (luna.did && luna.accessJwt) {
    await timedCall(
      result,
      "Luna creates a post",
      async () => {
        return await client.records.createRecord(
          luna.did,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: "Write proxy test post from Luna",
            createdAt: now(),
          },
          luna.accessJwt,
        );
      },
      (r: any) => `uri=${r.uri}`,
    );
  }

  await new Promise((r) => setTimeout(r, 3000));

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
  );

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
  );

  if (luna.did && luna.accessJwt) {
    await timedCall(
      result,
      "Write proxy: createRecord on AppView (unwired)",
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
          luna.accessJwt,
        );
      },
    );

    await timedCall(
      result,
      "OAuth2: valid Bearer token on AppView",
      async () => {
        return await av.raw.httpGet(
          "/xrpc/app.bsky.actor.getProfile",
          { actor: luna.did },
          luna.accessJwt,
        );
      },
      (r: any) => `handle=${r.handle || "unknown"}`,
    );
  }

  if (luna.did) {
    await timedCall(
      result,
      "OAuth2: DID-as-token on AppView",
      async () => {
        return await av.raw.httpGet(
          "/xrpc/app.bsky.actor.getProfile",
          { actor: luna.did },
          luna.did,
        );
      },
      (r) => `status=200`,
    );
  }

  await timedCall(
    result,
    "OAuth2: invalid Bearer token on AppView",
    async () => {
      return await av.raw.httpGet(
        "/xrpc/app.bsky.actor.getProfile",
        { actor: luna.did || "did:plc:unknown" },
        "invalid-garbage-token-xyz",
      );
    },
  );

  await timedCall(
    result,
    "Endpoint counts after operations",
    async () => {
      return await av.raw.httpGet("/admin/endpoints", undefined, adminToken);
    },
  );

  await timedCall(
    result,
    "AppView metrics",
    async () => {
      return await av.raw.httpGet(
        "/admin/appview/metrics/stats",
        undefined,
        adminToken,
      );
    },
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
