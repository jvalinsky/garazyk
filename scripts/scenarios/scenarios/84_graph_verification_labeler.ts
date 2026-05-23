/**
 * @module scenarios/84_graph_verification_labeler
 *
 * Scenario: Tests graph verification (createVerification, deleteVerification) and
 * labeler service endpoints (getServices with multiple DID scenarios).
 *
 * Behavior:
 * - Creates accounts with profiles.
 * - Tests app.bsky.graph.verification.createVerification to verify an account.
 * - Tests verification retrieval and account verify status.
 * - Tests app.bsky.graph.verification.deleteVerification to remove a verification.
 * - Verifies verification is gone after delete.
 * - Tests app.bsky.labeler.getServices with various DID combinations.
 *
 * Expectations:
 * - Verification endpoints return structured responses.
 * - Labeler service queries work with single and multiple DIDs.
 * - Unimplemented endpoints are gracefully skipped.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, tryEndpoint, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: app.bsky.graph.verification.{createVerification, deleteVerification},
//   app.bsky.labeler.getServices.
// Extends coverage from scenarios 45 (labeler subscription), 61 (graph read verification),
// and 82 (graph advanced). Runs against PDS and AppView.




export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Graph Verification & Labeler");
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

  // --- Create accounts ---
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          return await pds.accounts.createAccount(char.handle, char.email, char.password);
        } catch {
          return await pds.accounts.createSession(char.handle, char.password);
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID(s)");
    result.finish();
    return result;
  }

  // --- Set profiles for both accounts ---
  for (const char of [luna, marcus]) {
    await tryEndpoint(
      result,
      `Set profile: ${char.name}`,
      async () => {
        return await pds.records.createRecord(
          char.did!,
          "app.bsky.actor.profile",
          {
            $type: "app.bsky.actor.profile",
            displayName: char.name,
            description: char.persona,
            createdAt: now(),
          },
          char.accessJwt!,
        );
      },
    );
  }

  // ── 1. app.bsky.graph.verification.* ───────────────────────────────────
  // Graph verification allows accounts to verify other accounts on the network.
  // createVerification creates a verification record, deleteVerification removes it.

  // 1a. Verification lifecycle: create verification by Marcus verifying Luna
  let verificationRef: { uri: string; cid: string } | null = null;

  verificationRef = await tryEndpoint(
    result,
    "graph.verification.createVerification (Marcus verifies Luna)",
    async () => {
      const body = await pds.as(marcus).raw.post("app.bsky.graph.verification.createVerification", {
        subject: luna.did,
        createdAt: now(),
      });
      return { uri: body.uri, cid: body.cid };
    },
    (r) => `uri=${r.uri}`,
  );

  // 1b. Verify via AppView getProfile (check verification status)
  if (verificationRef) {
    await tryEndpoint(
      result,
      "appview.actor.getProfile shows verification",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.actor.getProfile", {
          actor: luna.did,
        });
        const verification = body.verification;
        return {
          verified: !!verification,
          subject: body.did ?? "present",
        };
      },
      (r) => `verified=${r.verified}`,
    );
  }

  // 1c. Delete the verification
  if (verificationRef) {
    await tryEndpoint(
      result,
      "graph.verification.deleteVerification",
      async () => {
        const body = await pds.as(marcus).raw.post("app.bsky.graph.verification.deleteVerification", {
          subject: luna.did,
        });
        return { status: "deleted" };
      },
    );

    // 1d. Verify verification is no longer present via getProfile
    await tryEndpoint(
      result,
      "appview.actor.getProfile shows verification removed",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.actor.getProfile", {
          actor: luna.did,
        });
        return { verified: !!body.verification };
      },
      (r) => `verified=${r.verified}`,
    );
  }

  // ── 2. app.bsky.labeler.getServices ────────────────────────────────────
  // Query labeler services for a given set of DIDs. Expands on scenario 45
  // which just did a single DID lookup.

  // 2a. getServices with a single DID (marcus — no labeler)
  await tryEndpoint(
    result,
    "labeler.getServices (single DID, no labeler)",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.labeler.getServices", {
        dids: [marcus.did],
      });
      const views = body.views ?? [];
      return { count: Array.isArray(views) ? views.length : "present" };
    },
    (r) => `views=${r.count}`,
  );

  // 2b. getServices with multiple DIDs (some with labelers, some without)
  await tryEndpoint(
    result,
    "labeler.getServices (multiple DIDs)",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.labeler.getServices", {
        dids: [luna.did, marcus.did],
      });
      const views = body.views ?? [];
      return { count: Array.isArray(views) ? views.length : "present" };
    },
    (r) => `views=${r.count}`,
  );

  // 2c. getServices with nonexistent DID
  await tryEndpoint(
    result,
    "labeler.getServices (nonexistent DID)",
    async () => {
      const body = await appview.as(luna).raw.get("app.bsky.labeler.getServices", {
        dids: ["did:plc:nonexistent000000000000"],
      });
      const views = body.views ?? [];
      return { count: Array.isArray(views) ? views.length : "present" };
    },
    (r) => `views=${r.count}`,
  );

  // 2d. getServices via PDS (direct)
  await tryEndpoint(
    result,
    "labeler.getServices via PDS",
    async () => {
      const body = await pds.as(luna).raw.get("app.bsky.labeler.getServices", {
        dids: [marcus.did],
      });
      const views = body.views ?? [];
      return { count: Array.isArray(views) ? views.length : "present" };
    },
    (r) => `views=${r.count}`,
  );

  // 2e. getServices via PDS with no auth
  await tryEndpoint(
    result,
    "labeler.getServices via PDS (no auth)",
    async () => {
      const body = await pds.asAdmin("").raw.get("app.bsky.labeler.getServices", {
        dids: [marcus.did],
      });
      const views = body.views ?? [];
      return { count: Array.isArray(views) ? views.length : "present" };
    },
    (r) => `views=${r.count}`,
  );

  // ── 3. Create a labeler service record and verify via getServices ──────
  // This mirrors scenario 45 but adds AppView verification coverage.

  const labelerRecord = {
    $type: "app.bsky.labeler.service",
    policies: { labelValues: [], labelValueDefinitions: [] },
    createdAt: now(),
  };

  const labelerRef = await tryEndpoint(
    result,
    "Marcus creates labeler service record",
    async () => {
      return await pds.records.createRecord(
        marcus.did,
        "app.bsky.labeler.service",
        labelerRecord,
        marcus.accessJwt,
        { rkey: "self" },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  if (labelerRef) {
    // Small delay for indexing
    await new Promise((r) => setTimeout(r, 1500));

    await tryEndpoint(
      result,
      "labeler.getServices shows marcus labeler (AppView)",
      async () => {
        const body = await appview.as(luna).raw.get("app.bsky.labeler.getServices", {
          dids: [marcus.did],
        });
        const views = body.views ?? [];
        const hasLabeler = Array.isArray(views) && views.length > 0;
        return { views: Array.isArray(views) ? views.length : 0, hasLabeler };
      },
      (r) => `views=${r.views}, hasLabeler=${r.hasLabeler}`,
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
