// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @module scenarios/88_admin_account_endpoints
 *
 * @abstract Covers com.atproto.admin.* account management endpoints.
 *
 * @discussion
 *   Tests admin account management endpoints: sendEmail, updateAccountEmail,
 *   updateAccountHandle, updateAccountPassword, updateAccountSigningKey,
 *   disableAccountInvites, enableAccountInvites, disableInviteCodes.
 *   All endpoints use admin auth and are gracefully skipped if unimplemented.
 *   Destructive operations (password change) revert to original value.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, tryEndpoint, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Admin Account Management Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");
  const troll = getActor("troll");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Create user accounts ---
  const lunaSession = await timedCall(
    result,
    "Create luna account",
    async () => {
      try {
        return await pds.accounts.createAccount(luna.handle, luna.email, luna.password);
      } catch {
        return await pds.accounts.createSession(luna.handle, luna.password);
      }
    },
    (s) => `did=${s.did}`,
  );
  if (lunaSession) {
    luna.did = lunaSession.did;
    luna.accessJwt = lunaSession.accessJwt;
  }

  const trollSession = await timedCall(
    result,
    "Create troll account",
    async () => {
      try {
        return await pds.accounts.createAccount(troll.handle, troll.email, troll.password);
      } catch {
        return await pds.accounts.createSession(troll.handle, troll.password);
      }
    },
    (s) => `did=${s.did}`,
  );
  if (trollSession) {
    troll.did = trollSession.did;
    troll.accessJwt = trollSession.accessJwt;
  }

  if (!luna.did || !troll.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // --- Obtain admin token ---
  const adminPassword = Deno.env.get("PDS_ADMIN_PASSWORD") || "admin-localdev";
  const adminToken = await timedCall(
    result,
    "Admin login",
    async () => pds.adminLogin(adminPassword),
    () => "obtained admin bearer",
  );

  if (!adminToken) {
    result.stepSkipped("All admin account endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // --- 1. com.atproto.admin.sendEmail ---
  await tryEndpoint(
    result,
    "admin.sendEmail",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.sendEmail", {
        to: luna.did,
        subject: "Admin API coverage test",
        content: "This is a test email from the admin API coverage scenario.",
      });
      return { sent: body.sent ?? body.success ?? "present" };
    },
    (r) => `sent=${r.sent}`,
  );

  // --- 2. com.atproto.admin.updateAccountEmail ---
  await tryEndpoint(
    result,
    "admin.updateAccountEmail (and revert)",
    async () => {
      const originalEmail = luna.email ?? "luna@test.com";
      // Set to a temporary email
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountEmail", {
        account: luna.did,
        email: `admin-test-${Date.now()}@garazyk.xyz`,
      });
      // Revert to original
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountEmail", {
        account: luna.did,
        email: originalEmail,
      });
      return { status: "updated and reverted" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 3. com.atproto.admin.updateAccountHandle ---
  await tryEndpoint(
    result,
    "admin.updateAccountHandle (and revert)",
    async () => {
      const originalHandle = luna.handle!;
      const tempHandle = `admin-test-${Date.now().toString(36)}.garazyk.xyz`;
      // Set to a temp handle
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountHandle", {
        did: luna.did,
        handle: tempHandle,
      });
      // Revert to original
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountHandle", {
        did: luna.did,
        handle: originalHandle,
      });
      return { status: "updated and reverted" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 4. com.atproto.admin.updateAccountPassword ---
  await tryEndpoint(
    result,
    "admin.updateAccountPassword (and revert)",
    async () => {
      const originalPassword = luna.password!;
      // Set to a temp password, then revert
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountPassword", {
        did: luna.did,
        password: "admin-test-temp-password-999",
      });
      await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountPassword", {
        did: luna.did,
        password: originalPassword,
      });
      return { status: "updated and reverted" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 5. com.atproto.admin.updateAccountSigningKey ---
  await tryEndpoint(
    result,
    "admin.updateAccountSigningKey",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.updateAccountSigningKey", {
        did: troll.did,
        signingKey: troll.did, // placeholder — actual key rotation not needed for coverage
        verify: false,
      });
      return { success: body.success ?? "present" };
    },
    (r) => `success=${r.success}`,
  );

  // --- 6. com.atproto.admin.disableAccountInvites ---
  await tryEndpoint(
    result,
    "admin.disableAccountInvites",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.disableAccountInvites", {
        account: troll.did,
        note: "Temporarily disabled for admin API coverage test",
      });
      return { disabled: body.disabled ?? "present" };
    },
    (r) => `disabled=${r.disabled}`,
  );

  // --- 7. com.atproto.admin.enableAccountInvites ---
  await tryEndpoint(
    result,
    "admin.enableAccountInvites",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.enableAccountInvites", {
        account: troll.did,
        note: "Re-enabled after admin API coverage test",
      });
      return { enabled: body.enabled ?? "present" };
    },
    (r) => `enabled=${r.enabled}`,
  );

  // --- 8. com.atproto.admin.disableInviteCodes ---
  await tryEndpoint(
    result,
    "admin.disableInviteCodes",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcPost("com.atproto.admin.disableInviteCodes", {
        codes: [],
        accounts: [],
      });
      return { disabled: body.disabled ?? "present" };
    },
    (r) => `disabled=${r.disabled}`,
  );

  // --- 9. com.atproto.admin.getModerationReports ---
  await tryEndpoint(
    result,
    "admin.getModerationReports",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.xrpcGet("com.atproto.admin.getModerationReports", {
        limit: 10,
      });
      const reports = body.reports ?? [];
      return { count: Array.isArray(reports) ? reports.length : "present" };
    },
    (r) => `reports=${r.count}`,
  );

  // --- 10. Auth enforcement ---
  await timedCall(
    result,
    "admin.sendEmail (no auth, rejected)",
    async () => {
      await pds.raw.xrpcPost("com.atproto.admin.sendEmail", {
        to: luna.did,
        subject: "Should fail",
        content: "Should not be sent",
      });
    },
    undefined,
    true, // expectFailure
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
