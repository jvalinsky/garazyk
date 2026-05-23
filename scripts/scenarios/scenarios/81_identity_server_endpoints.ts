/**
 * @module scenarios/81_identity_server_endpoints
 *
 * Scenario: Identity & server management endpoints.
 *
 * Behavior:
 * - Creates accounts and profiles.
 * - Tests com.atproto.identity.resolveDid and resolveIdentity.
 * - Tests com.atproto.server.checkAccountStatus.
 * - Tests com.atproto.server.listAppPasswords / createAppPassword / revokeAppPassword.
 * - Tests com.atproto.server.getAccount and getAccountInviteCodes.
 * - Tests com.atproto.repo.describeRepo.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { now, ScenarioResult, timedCall, tryEndpoint } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Identity & Server Management Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const names = ["luna", "marcus"];
  for (const name of names) {
    const char = getActor(name);
    await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await pds.accounts.createAccount(char.handle, char.email, char.password)
          .catch(() => pds.accounts.createSession(char.handle, char.password));
      },
      (s) => `did=${s.did}`,
    );
  }

  const active = names.filter((n) => getActor(n).did);
  if (active.length < 2) {
    result.stepFailed("Account setup", `only ${active.length} accounts`);
    result.finish();
    return result;
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");

  // ── 1. com.atproto.identity.resolveDid ──────────────────────────────────
  if (luna.did) {
    await tryEndpoint(
      result,
      "resolveDid for Luna",
      async () => {
        const body = await pds.as(luna).raw.get("com.atproto.identity.resolveDid", { did: luna.did });
        assert.isTrue(!!body.did, "expected did document");
        return body;
      },
      (r) => `did=${r.did}, handle=${r.handle ?? "none"}`,
    );

    // Also try via AppView for cross-service verification
    await tryEndpoint(
      result,
      "resolveDid for Luna via AppView",
      async () => {
        const body = await appview.as(luna).raw.get("com.atproto.identity.resolveDid", { did: luna.did });
        assert.isTrue(!!body.did, "expected did document");
        return body;
      },
      (r) => `did=${r.did}`,
    );
  }

  // resolveDid with nonexistent DID (error handling)
  await tryEndpoint(
    result,
    "resolveDid with nonexistent DID",
    async () => {
      return await pds.as(luna).raw.get("com.atproto.identity.resolveDid", {
        did: "did:plc:nonexistent00000000",
      });
    },
  );

  // ── 2. com.atproto.identity.resolveIdentity ─────────────────────────────
  if (luna.did) {
    await tryEndpoint(
      result,
      "resolveIdentity for Luna",
      async () => {
        const body = await pds.as(luna).raw.get("com.atproto.identity.resolveIdentity", {
          identifier: luna.handle,
        });
        // Response may contain did, handle, or other identity fields
        return body;
      },
      (r) => `did=${r.did ?? "none"}`,
    );
  }

  // resolveIdentity by DID
  await tryEndpoint(
    result,
      "resolveIdentity by DID",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.identity.resolveIdentity", {
        identifier: luna.did,
      });
      return body;
    },
    (r) => `handle=${r.handle ?? "none"}`,
  );

  // ── 3. com.atproto.server.checkAccountStatus ────────────────────────────
  await tryEndpoint(
    result,
    "checkAccountStatus for Luna",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.server.checkAccountStatus", {});
      // Expected fields: activated, validEmail, repoBlocks, etc.
      return body;
    },
    (r) => `activated=${r.activated}, validEmail=${r.validEmail}`,
  );

  // ── 4. com.atproto.server.getAccount ────────────────────────────────────
  await tryEndpoint(
    result,
    "getAccount for Luna",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.server.getAccount", { did: luna.did });
      assert.isTrue(!!body.did, "expected account info");
      return body;
    },
    (r) => `did=${r.did}, email=${r.email ?? "(redacted)"}`,
  );

  // ── 5. com.atproto.server.listAppPasswords / create/revoke ──────────────
  let appPasswordName: string | null = null;

  // Create an app password
  const createResult = await tryEndpoint(
    result,
    "createAppPassword for Luna",
    async () => {
      const body = await pds.as(luna).raw.post(
        "com.atproto.server.createAppPassword",
        { name: `test-app-pw-${Date.now()}` },
      );
      return body;
    },
    (r) => `name=${r.name}`,
  );

  if (createResult?.name) {
    appPasswordName = createResult.name;
  }

  // List app passwords
  await tryEndpoint(
    result,
    "listAppPasswords for Luna",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.server.listAppPasswords", {});
      assert.isTrue(Array.isArray(body.passwords ?? body.appPasswords), "expected passwords array");
      return body;
    },
    (r) => `count=${(r.passwords ?? r.appPasswords ?? []).length}`,
  );

  // Revoke the created app password
  if (appPasswordName) {
    await tryEndpoint(
      result,
      "revokeAppPassword for Luna",
      async () => {
        return await pds.as(luna).raw.post(
          "com.atproto.server.revokeAppPassword",
          { name: appPasswordName },
        );
      },
    );
  }

  // ── 6. com.atproto.repo.describeRepo ────────────────────────────────────
  await tryEndpoint(
    result,
    "describeRepo for Luna via PDS",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.repo.describeRepo", { repo: luna.did });
      assert.isTrue(!!body.did, "expected repo description");
      return body;
    },
    (r) => `did=${r.did}, handle=${r.handle}, collections=${(r.collections ?? []).length}`,
  );

  await tryEndpoint(
    result,
    "describeRepo for Luna via AppView",
    async () => {
      const body = await appview.as(luna).raw.get("com.atproto.repo.describeRepo", { repo: luna.did });
      return body;
    },
    (r) => `handle=${r.handle ?? "none"}`,
  );

  // describeRepo with nonexistent DID (error handling)
  await tryEndpoint(
    result,
    "describeRepo with nonexistent DID",
    async () => {
      return await pds.as(luna).raw.get("com.atproto.repo.describeRepo", {
        repo: "did:plc:nonexistent00000",
      });
    },
  );

  // ── 7. com.atproto.server.getAccountInviteCodes ─────────────────────────
  await tryEndpoint(
    result,
    "getAccountInviteCodes for Luna",
    async () => {
      const body = await pds.as(luna).raw.get("com.atproto.server.getAccountInviteCodes", {});
      // May return codes, usableBy, etc.
      return body;
    },
    (r) => `codes=${(r.codes ?? []).length}`,
  );

  // ── 8. Auth enforcement ─────────────────────────────────────────────────
  await timedCall(
    result,
    "checkAccountStatus rejects unauthenticated request",
    async () => {
      return await pds.raw.get("com.atproto.server.checkAccountStatus", {});
    },
    undefined,
    true,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
