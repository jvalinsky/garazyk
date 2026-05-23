/**
 * @module scenarios/85_labeling_endpoints
 *
 * Scenario: Tests com.atproto.label.* endpoint coverage including
 * createLabel, getLabels, and queryLabels with various filter scenarios.
 *
 * Behavior:
 * - Creates accounts with admin credentials.
 * - Tests com.atproto.label.createLabel to attach labels to accounts and records.
 * - Tests com.atproto.label.getLabels to retrieve labels by DID/URI.
 * - Tests com.atproto.label.queryLabels with URI patterns, cursor pagination, and sources.
 * - Tests edge cases: nonexistent URI patterns, empty results.
 *
 * Expectations:
 * - Label endpoints return structured responses with admin auth.
 * - Labels are queryable by URI patterns and sources.
 * - Unavailable endpoints are gracefully skipped (404/501).
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: com.atproto.label.{createLabel, getLabels, queryLabels}.
// Extends coverage from 04_moderation_safety.ts (queryLabels briefly used) to
// add dedicated coverage with createLabel, getLabels, and expanded queryLabels
// filters. Runs against the PDS admin endpoints with admin authentication.

function now() {
  return new Date().toISOString();
}

/** Try an endpoint, skipping if 404/501/403, failing on other errors. */
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
  const result = new ScenarioResult("Labeling Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Create accounts ---
  const luna = getActor("luna");
  const marcus = getActor("marcus");

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

  const marcusSession = await timedCall(
    result,
    "Create marcus account",
    async () => {
      try {
        return await pds.accounts.createAccount(marcus.handle, marcus.email, marcus.password);
      } catch {
        return await pds.accounts.createSession(marcus.handle, marcus.password);
      }
    },
    (s) => `did=${s.did}`,
  );
  if (marcusSession) {
    marcus.did = marcusSession.did;
    marcus.accessJwt = marcusSession.accessJwt;
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID(s)");
    result.finish();
    return result;
  }

  // --- Create target records for labeling ---
  // Marcus creates a post that will be labeled
  const marcusPost = await timedCall(
    result,
    "Marcus creates a post (labeling target)",
    async () => {
      return await pds.as(marcus).raw.post("com.atproto.repo.createRecord", {
        repo: marcus.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "This post will be labeled for scenario coverage.",
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
    result.stepSkipped("All label endpoints", "no admin token available");
    result.finish();
    return result;
  }

  // ── 1. com.atproto.label.createLabel ──────────────────────────────────
  // Create labels on a repo (DID-level) and on a specific record.

  // 1a. Create a label on the account (repo-level label)
  await tryEndpoint(
    result,
    "label.createLabel (repo-level)",
    async () => {
      const body = await pds.raw.post("com.atproto.label.createLabel", {
        uri: marcus.did,
        val: "test-repo-label",
        neg: false,
        cid: undefined,
        expiresAt: undefined,
      }, adminToken);
      return { uri: body.uri ?? marcus.did, val: body.val };
    },
    (r) => `uri=${r.uri}, val=${r.val}`,
  );

  // 1b. Create a label on a specific record (post-level label)
  if (marcusPost) {
    await tryEndpoint(
      result,
      "label.createLabel (record-level)",
      async () => {
        const body = await pds.raw.post("com.atproto.label.createLabel", {
          uri: marcusPost.uri,
          val: "test-record-label",
          neg: false,
          cid: marcusPost.cid,
          expiresAt: undefined,
        }, adminToken);
        return { uri: body.uri, val: body.val };
      },
      (r) => `uri=${r.uri}, val=${r.val}`,
    );
  }

  // 1c. Create a negative label (negation tag)
  await tryEndpoint(
    result,
    "label.createLabel (negative label)",
    async () => {
      const body = await pds.raw.post("com.atproto.label.createLabel", {
        uri: marcus.did,
        val: "test-negated-label",
        neg: true,
        cid: undefined,
        expiresAt: undefined,
      }, adminToken);
      return { uri: body.uri, val: body.val, neg: body.neg ?? true };
    },
    (r) => `uri=${r.uri}, neg=${r.neg}`,
  );

  // ── 2. com.atproto.label.getLabels ─────────────────────────────────────
  // Retrieve labels for a specific subject (DID or record URI).

  // 2a. getLabels for a DID (all labels on the account)
  await tryEndpoint(
    result,
    "label.getLabels (by DID)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.getLabels", {
        uri: marcus.did,
        limit: 10,
      }, adminToken);
      const labels = body.labels ?? [];
      return { count: Array.isArray(labels) ? labels.length : "present" };
    },
    (r) => `labels=${r.count}`,
  );

  // 2b. getLabels for a specific record
  if (marcusPost) {
    await tryEndpoint(
      result,
      "label.getLabels (by record URI)",
      async () => {
        const body = await pds.raw.get("com.atproto.label.getLabels", {
          uri: marcusPost.uri,
          limit: 10,
        }, adminToken);
        const labels = body.labels ?? [];
        return { count: Array.isArray(labels) ? labels.length : "present" };
      },
      (r) => `labels=${r.count}`,
    );
  }

  // 2c. getLabels for a nonexistent URI (empty results)
  await tryEndpoint(
    result,
    "label.getLabels (nonexistent URI — empty)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.getLabels", {
        uri: "at://did:plc:nonexistent/app.bsky.feed.post/nonexistent",
        limit: 10,
      }, adminToken);
      const labels = body.labels ?? [];
      return { count: Array.isArray(labels) ? labels.length : 0 };
    },
    (r) => `labels=${r.count}`,
  );

  // ── 3. com.atproto.label.queryLabels ──────────────────────────────────
  // Query labels with URI patterns and optional filters.
  // Partially covered in scenario 04 — this expands with pagination, cursor, sources.

  // 3a. queryLabels with URI pattern matching (broad pattern for marcus)
  await tryEndpoint(
    result,
    "label.queryLabels (URI pattern — DID prefix)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.queryLabels", {
        uriPatterns: [`${marcus.did!.slice(0, 20)}*`],
        limit: 10,
      }, adminToken);
      const labels = body.labels ?? [];
      return { count: Array.isArray(labels) ? labels.length : "present" };
    },
    (r) => `labels=${r.count}`,
  );

  // 3b. queryLabels with cursor pagination
  const firstPage = await tryEndpoint(
    result,
    "label.queryLabels (with cursor — first page)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.queryLabels", {
        uriPatterns: ["*"],
        limit: 1,
      }, adminToken);
      const labels = body.labels ?? [];
      return { cursor: body.cursor, count: Array.isArray(labels) ? labels.length : 0 };
    },
    (r) => `cursor=${r.cursor ?? "none"}, count=${r.count}`,
  );

  if (firstPage && firstPage.cursor) {
    await tryEndpoint(
      result,
      "label.queryLabels (with cursor — second page)",
      async () => {
        const body = await pds.raw.get("com.atproto.label.queryLabels", {
          uriPatterns: ["*"],
          cursor: firstPage.cursor,
          limit: 10,
        }, adminToken);
        const labels = body.labels ?? [];
        return { cursor: body.cursor, count: Array.isArray(labels) ? labels.length : 0 };
      },
      (r) => `cursor=${r.cursor ?? "none"}, count=${r.count}`,
    );
  }

  // 3c. queryLabels with sources filter
  await tryEndpoint(
    result,
    "label.queryLabels (with sources filter)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.queryLabels", {
        uriPatterns: ["*"],
        sources: [marcus.did!],
        limit: 10,
      }, adminToken);
      const labels = body.labels ?? [];
      return { count: Array.isArray(labels) ? labels.length : "present" };
    },
    (r) => `labels=${r.count}`,
  );

  // 3d. queryLabels with nonexistent URI pattern (empty results)
  await tryEndpoint(
    result,
    "label.queryLabels (nonexistent URI pattern — empty)",
    async () => {
      const body = await pds.raw.get("com.atproto.label.queryLabels", {
        uriPatterns: ["at://did:plc:zzzzzzzzzzzzz/app.bsky.feed.post/*"],
        limit: 10,
      }, adminToken);
      const labels = body.labels ?? [];
      return { count: Array.isArray(labels) ? labels.length : 0 };
    },
    (r) => `labels=${r.count}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
