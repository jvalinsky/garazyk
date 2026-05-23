// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @module scenarios/86_admin_query_endpoints
 *
 * @abstract Covers com.atproto.admin.* read-only query and discovery endpoints.
 *
 * @discussion
 *   Tests the admin query endpoints against PDS: getAccountInfo, getAccountInfos,
 *   searchAccounts, getSubjectStatus, getServerStats, getBlobAuditStatus,
 *   getInviteCodes, queryAuditLog, and getAccountUsage.
 *   All endpoints use admin auth and are gracefully skipped if unimplemented.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

function now(): string {
  return new Date().toISOString();
}

/** Try an endpoint, skipping if 404/501/400-not-implemented, failing on other errors. */
async function tryEndpoint<T>(
  result: ScenarioResult,
  label: string,
  fn: () => Promise<T>,
  summary?: (t: T) => string,
): Promise<T | null> {
  try {
    const val = await fn();
    result.stepPassed(label, summary ? summary(val) : undefined);
    return val;
  } catch (e: any) {
    if (e instanceof XrpcError && (e.status === 404 || e.status === 501)) {
      result.stepSkipped(label, `endpoint not available (HTTP ${e.status})`);
    } else if (e instanceof XrpcError && e.status === 403) {
      result.stepSkipped(label, `access denied (HTTP 403) — requires elevated role`);
    } else if (e instanceof XrpcError && e.status === 400) {
      const body = typeof e.body === "string" ? e.body : JSON.stringify(e.body ?? "");
      if (body.toLowerCase().includes("not implemented") || body.toLowerCase().includes("unknown method")) {
        result.stepSkipped(label, `endpoint not implemented`);
      } else {
        result.stepFailed(label, `HTTP 400: ${body.substring(0, 200)}`);
      }
    } else {
      result.stepFailed(label, String(e.message ?? e));
    }
    return null;
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Admin Query & Discovery Endpoints");
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
    result.stepSkipped("All admin query endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // --- 1. com.atproto.admin.getAccountInfo ---
  await tryEndpoint(
    result,
    "admin.getAccountInfo (by DID)",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getAccountInfo", {
        did: luna.did,
      }, adminToken);
      return { did: body.did, handle: body.handle ?? body.email ?? "present" };
    },
    (r) => `did=${r.did}`,
  );

  // --- 2. com.atproto.admin.getAccountInfos (batch) ---
  await tryEndpoint(
    result,
    "admin.getAccountInfos (batch)",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getAccountInfos", {
        dids: [luna.did!, troll.did!],
      }, adminToken);
      const infos = body.infos ?? body.accounts ?? [];
      return { count: Array.isArray(infos) ? infos.length : "present" };
    },
    (r) => `accounts=${r.count}`,
  );

  // --- 3. com.atproto.admin.searchAccounts ---
  await tryEndpoint(
    result,
    "admin.searchAccounts (by email partial)",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.searchAccounts", {
        email: luna.email?.split("@")[0] ?? "luna",
        limit: 10,
      }, adminToken);
      const accounts = body.accounts ?? [];
      return { count: Array.isArray(accounts) ? accounts.length : "present" };
    },
    (r) => `accounts=${r.count}`,
  );

  // --- 4. com.atproto.admin.getSubjectStatus ---
  await tryEndpoint(
    result,
    "admin.getSubjectStatus (by DID)",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getSubjectStatus", {
        did: troll.did,
      }, adminToken);
      return { status: body.takedown?.applied ?? "none" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 5. com.atproto.admin.getServerStats ---
  await tryEndpoint(
    result,
    "admin.getServerStats",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getServerStats", {}, adminToken);
      return { stats: Object.keys(body).join(",") };
    },
    (r) => `keys=${r.stats}`,
  );

  // --- 6. com.atproto.admin.getBlobAuditStatus ---
  await tryEndpoint(
    result,
    "admin.getBlobAuditStatus",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getBlobAuditStatus", {
        did: luna.did,
        limit: 10,
      }, adminToken);
      const blobs = body.blobs ?? body.entries ?? [];
      return { count: Array.isArray(blobs) ? blobs.length : "present" };
    },
    (r) => `blobs=${r.count}`,
  );

  // --- 7. com.atproto.admin.getInviteCodes ---
  await tryEndpoint(
    result,
    "admin.getInviteCodes",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getInviteCodes", {
        limit: 10,
      }, adminToken);
      const codes = body.codes ?? [];
      return { count: Array.isArray(codes) ? codes.length : "present" };
    },
    (r) => `codes=${r.count}`,
  );

  // --- 8. com.atproto.admin.queryAuditLog ---
  await tryEndpoint(
    result,
    "admin.queryAuditLog",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.queryAuditLog", {
        limit: 10,
      }, adminToken);
      const entries = body.entries ?? body.auditLog ?? [];
      return { count: Array.isArray(entries) ? entries.length : "present" };
    },
    (r) => `entries=${r.count}`,
  );

  // --- 9. com.atproto.admin.getAccountUsage ---
  await tryEndpoint(
    result,
    "admin.getAccountUsage",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.admin.getAccountUsage", {
        did: luna.did,
      }, adminToken);
      const usage = body.usage ?? body.daily ?? {};
      return { fields: Object.keys(usage).join(",") };
    },
    (r) => `fields=${r.fields}`,
  );

  // --- 10. Auth enforcement: unauthenticated access rejected ---
  await timedCall(
    result,
    "admin.getAccountInfo (no auth, rejected)",
    async () => {
      await pds.raw.xrpcGet("com.atproto.admin.getAccountInfo", {
        did: luna.did,
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
