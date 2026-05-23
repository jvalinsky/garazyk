/**
 * @module scenarios/71_ozone_moderation_endpoints
 *
 * Scenario: Tests tools.ozone.moderation.* endpoint coverage including
 * getRecord, getRepo, and searchRepos.
 *
 * Behavior:
 * - Creates accounts and posts on PDS with admin/moderator credentials.
 * - Tests moderation read endpoints against the PDS admin API.
 * - Tests tools.ozone.signature search endpoints if available.
 *
 * Expectations:
 * - Moderation endpoints return structured responses with admin auth.
 * - Unavailable endpoints are gracefully skipped.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, tryEndpoint, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: tools.ozone.moderation.getRecord, tools.ozone.moderation.getRepo,
//   tools.ozone.moderation.searchRepos, tools.ozone.signature.findRelatedAccounts,
//   tools.ozone.signature.searchAccounts.
// Extends 04_moderation_safety.ts (createReport/emitEvent) to add read-side
// moderation API coverage. Runs against the PDS admin endpoints.




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Ozone Moderation Endpoints");
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
  const charSession = await timedCall(
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
  if (charSession) {
    luna.did = charSession.did;
    luna.accessJwt = charSession.accessJwt;
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

  // --- Create a post (target for moderation lookup) ---
  const postRef = await timedCall(
    result,
    "Troll creates post (moderation target)",
    async () => {
      return await pds.as(troll).raw.post("com.atproto.repo.createRecord", {
        repo: troll.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Moderation test post for ozone endpoint coverage.",
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
    result.stepSkipped("All ozone endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // --- 1. tools.ozone.moderation.getRecord ---
  // Retrieves moderation details about a specific record.
  await tryEndpoint(
    result,
    "ozone.moderation.getRecord",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.post("tools.ozone.moderation.getRecord", {
        uri: postRef?.uri ?? `${troll.did}/app.bsky.feed.post/test`,
      });
      return { uri: body.uri ?? body.record?.uri ?? "present" };
    },
    (r) => `uri=${r.uri}`,
  );

  // --- 2. tools.ozone.moderation.getRepo ---
  // Retrieves moderation details about a repository (DID).
  await tryEndpoint(
    result,
    "ozone.moderation.getRepo",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.post("tools.ozone.moderation.getRepo", {
        did: troll.did,
      });
      return { did: body.did, modStatus: body.moderation?.currentAction ?? "none" };
    },
    (r) => `did=${r.did}`,
  );

  // --- 3. tools.ozone.moderation.searchRepos ---
  // Searches repositories with moderation filters.
  await tryEndpoint(
    result,
    "ozone.moderation.searchRepos",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.get("tools.ozone.moderation.searchRepos", {
        q: "troll",
        limit: 10,
      });
      const repos = body.repos ?? body.repositories ?? [];
      return { count: Array.isArray(repos) ? repos.length : "present" };
    },
    (r) => `repos=${r.count}`,
  );

  // --- 4. tools.ozone.signature.findRelatedAccounts ---
  // Finds accounts related to a given signature.
  await tryEndpoint(
    result,
    "ozone.signature.findRelatedAccounts",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.post("tools.ozone.signature.findRelatedAccounts", {
        did: troll.did,
      });
      const accounts = body.accounts ?? [];
      return { count: Array.isArray(accounts) ? accounts.length : "present" };
    },
    (r) => `accounts=${r.count}`,
  );

  // --- 5. tools.ozone.signature.searchAccounts ---
  // Searches accounts by signature attributes.
  await tryEndpoint(
    result,
    "ozone.signature.searchAccounts",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.get("tools.ozone.signature.searchAccounts", {
        q: "troll",
        limit: 10,
      });
      const accounts = body.accounts ?? [];
      return { count: Array.isArray(accounts) ? accounts.length : "present" };
    },
    (r) => `accounts=${r.count}`,
  );

  // --- 6. com.atproto.admin.getRecord (existing, for comparison) ---
  // Test the admin getRecord which was partially covered in scenario 55.
  await tryEndpoint(
    result,
    "admin.getRecord (existing endpoint for comparison)",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.get("com.atproto.admin.getRecord", {
        uri: postRef?.uri ?? `${troll.did}/app.bsky.feed.post/test`,
      });
      return { uri: body.uri ?? "present" };
    },
    (r) => `uri=${r.uri}`,
  );

  // --- 7. Report a post (to have moderation data) ---
  await tryEndpoint(
    result,
    "moderation.createReport",
    async () => {
      const body = await pds.as(luna).raw.post("com.atproto.moderation.createReport", {
        reasonType: "com.atproto.moderation.defs#reasonSpam",
        subject: {
          $type: "com.atproto.repo.strongRef",
          uri: postRef?.uri,
          cid: postRef?.cid,
        },
        reason: "Ozone endpoint coverage test report",
      });
      return { id: body.id, reportedBy: body.reportedBy };
    },
    (r) => `id=${r.id}`,
  );

  // --- 8. tools.ozone.moderation.emitEvent (emit a moderation action) ---
  await tryEndpoint(
    result,
    "ozone.moderation.emitEvent",
    async () => {
      const body = await pds.asAdmin(adminToken).raw.post("tools.ozone.moderation.emitEvent", {
        event: {
          $type: "tools.ozone.moderation.defs#modEventLabel",
          labels: [{ val: "test-ozone-coverage" }],
        },
        subject: {
          $type: "com.atproto.repo.strongRef",
          uri: postRef?.uri,
          cid: postRef?.cid,
        },
        subjectBlobCids: [],
        createdBy: luna.did,
      });
      return { id: body.id };
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
