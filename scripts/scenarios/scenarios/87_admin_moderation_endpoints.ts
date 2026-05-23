// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 * @module scenarios/87_admin_moderation_endpoints
 *
 * @abstract Covers com.atproto.admin.* moderation action endpoints and remaining
 *   tools.ozone.moderation.* endpoints (queryStatuses, getRecords, getEvent).
 *
 * @discussion
 *   Tests admin action endpoints: takeDownAccount, moderateAccount, moderateRecord,
 *   resolveReport, updateSubjectStatus, repairRepo, runBlobAudit.
 *   Also covers: tools.ozone.moderation.queryStatuses, getRecords, getEvent.
 *   All endpoints use admin auth and are gracefully skipped if unimplemented.
 *   Destructive operations (takedown) are reverted to avoid side effects.
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
  const result = new ScenarioResult("Admin Moderation & Action Endpoints");
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

  // --- Create a post (moderation target) ---
  const postRef = await timedCall(
    result,
    "Troll creates post",
    async () => {
      return await pds.as(troll).raw.post("com.atproto.repo.createRecord", {
        repo: troll.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Content requiring moderation action.",
          createdAt: now(),
        },
      });
    },
    (r) => `uri=${r.uri}`,
  );

  // --- Obtain admin token ---
  const adminPassword = Deno.env.get("PDS_ADMIN_PASSWORD") || "admin-localdev";
  const adminToken = await timedCall(
    result,
    "Admin login",
    async () => pds.adminLogin(adminPassword),
    () => "obtained admin bearer",
  );

  if (!adminToken) {
    result.stepSkipped("All admin moderation endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // --- 1. com.atproto.admin.takeDownAccount ---
  // Apply then immediately revert to avoid side effects.
  const takedownRef = await tryEndpoint(
    result,
    "admin.takeDownAccount (apply + revert)",
    async () => {
      const body = await pds.raw.post("com.atproto.admin.takeDownAccount", {
        did: troll.did,
      }, adminToken);
      // Revert immediately
      await pds.raw.post("com.atproto.admin.updateSubjectStatus", {
        subject: {
          $type: "com.atproto.admin.defs#repoRef",
          did: troll.did,
        },
        takedown: { applied: false },
      }, adminToken);
      return { actionId: body.id ?? body.actionId ?? "present" };
    },
    (r) => `actionId=${r.actionId}`,
  );

  // --- 2. com.atproto.admin.getAccountTakedown ---
  await tryEndpoint(
    result,
    "admin.getAccountTakedown",
    async () => {
      const body = await pds.raw.post("com.atproto.admin.getAccountTakedown", {
        did: troll.did,
      }, adminToken);
      return { status: body.takedown?.applied ?? "none" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 3. com.atproto.admin.moderateAccount ---
  await tryEndpoint(
    result,
    "admin.moderateAccount (label)",
    async () => {
      const body = await pds.raw.post("com.atproto.admin.moderateAccount", {
        did: troll.did,
        action: "label",
        label: { val: "test-admin-coverage" },
      }, adminToken);
      return { id: body.id ?? body.actionId ?? "present" };
    },
    (r) => `id=${r.id}`,
  );

  // --- 4. com.atproto.admin.moderateRecord ---
  if (postRef) {
    await tryEndpoint(
      result,
      "admin.moderateRecord (label)",
      async () => {
        const body = await pds.raw.post("com.atproto.admin.moderateRecord", {
          uri: postRef.uri,
          action: "label",
          label: { val: "test-record-moderation" },
        }, adminToken);
        return { id: body.id ?? body.actionId ?? "present" };
      },
      (r) => `id=${r.id}`,
    );
  } else {
    result.stepSkipped("admin.moderateRecord", "no post reference");
  }

  // --- 5. com.atproto.admin.resolveReport ---
  // Create a report first, then resolve it
  const reportRef = await tryEndpoint(
    result,
    "Create report for resolution test",
    async () => {
      const body = await pds.as(luna).raw.post("com.atproto.moderation.createReport", {
        reasonType: "com.atproto.moderation.defs#reasonSpam",
        subject: {
          $type: "com.atproto.repo.strongRef",
          uri: postRef?.uri ?? `${troll.did}/app.bsky.feed.post/test`,
          cid: postRef?.cid,
        },
        reason: "Report for resolveReport coverage test",
      });
      return { id: body.id, reportId: body.id };
    },
    (r) => `id=${r.id}`,
  );

  if (reportRef?.id) {
    await tryEndpoint(
      result,
      "admin.resolveReport",
      async () => {
        const body = await pds.raw.post("com.atproto.admin.resolveReport", {
          reportId: reportRef.id,
          action: "tools.ozone.moderation.defs#modEventResolve",
          comment: "Resolved via admin API coverage test",
        }, adminToken);
        return { id: body.id ?? "present" };
      },
      (r) => `resolutionId=${r.id}`,
    );
  } else {
    result.stepSkipped("admin.resolveReport", "no report to resolve");
  }

  // --- 6. com.atproto.admin.updateSubjectStatus ---
  await tryEndpoint(
    result,
    "admin.updateSubjectStatus (check + cleanup)",
    async () => {
      // Apply a label, then clean up
      await pds.raw.post("com.atproto.admin.updateSubjectStatus", {
        subject: {
          $type: "com.atproto.repo.strongRef",
          uri: postRef?.uri ?? `${troll.did}/app.bsky.feed.post/test`,
          cid: postRef?.cid,
        },
        takedown: { applied: false },
      }, adminToken);
      return { status: "cleared" };
    },
    (r) => `status=${r.status}`,
  );

  // --- 7. com.atproto.admin.repairRepo ---
  await tryEndpoint(
    result,
    "admin.repairRepo",
    async () => {
      const body = await pds.raw.post("com.atproto.admin.repairRepo", {
        did: troll.did,
      }, adminToken);
      return { success: body.success ?? "present" };
    },
    (r) => `success=${r.success}`,
  );

  // --- 8. com.atproto.admin.runBlobAudit ---
  await tryEndpoint(
    result,
    "admin.runBlobAudit",
    async () => {
      const body = await pds.raw.post("com.atproto.admin.runBlobAudit", {
        did: luna.did,
      }, adminToken);
      return { blobCount: body.blobs?.length ?? body.count ?? "present" };
    },
    (r) => `blobs=${r.blobCount}`,
  );

  // --- 9. tools.ozone.moderation.queryStatuses ---
  await tryEndpoint(
    result,
    "ozone.moderation.queryStatuses",
    async () => {
      const body = await pds.raw.get("tools.ozone.moderation.queryStatuses", {
        limit: 10,
      }, adminToken);
      const statuses = body.statuses ?? body.subjectStatuses ?? [];
      return { count: Array.isArray(statuses) ? statuses.length : "present" };
    },
    (r) => `statuses=${r.count}`,
  );

  // --- 10. tools.ozone.moderation.getRecords ---
  await tryEndpoint(
    result,
    "ozone.moderation.getRecords",
    async () => {
      const body = await pds.raw.post("tools.ozone.moderation.getRecords", {
        uris: [postRef?.uri ?? `${troll.did}/app.bsky.feed.post/test`],
      }, adminToken);
      const records = body.records ?? [];
      return { count: Array.isArray(records) ? records.length : "present" };
    },
    (r) => `records=${r.count}`,
  );

  // --- 11. tools.ozone.moderation.getEvent ---
  await tryEndpoint(
    result,
    "ozone.moderation.getEvent",
    async () => {
      const body = await pds.raw.post("tools.ozone.moderation.getEvent", {
        id: takedownRef?.actionId ?? 0,
      }, adminToken);
      return { id: body.id ?? body.event?.id ?? "present" };
    },
    (r) => `id=${r.id}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
