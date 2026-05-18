/**
 * @module scenarios/55_takedown_read_enforcement
 *
 * Scenario: 55 takedown read enforcement
 *
 * Behavior:
 * - Executes the 55 takedown read enforcement scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: public read returns hidden/404 after record takedown; admin read still returns content;
//   account-level takedown hides all public repo reads.
// Extends 04_moderation_safety.ts which applies takedowns but does not assert read-time enforcement.
// Production paths: com.atproto.admin.updateSubjectStatus, com.atproto.repo.getRecord/listRecords,
//   com.atproto.admin.getRecord.

function now() {
  return new Date().toISOString();
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Takedown Read Enforcement");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const troll = ctx.getCharacter("troll");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(
    result,
    "Create troll account",
    async () => {
      try {
        return await pds.accounts.createAccount(
          troll.handle,
          troll.email,
          troll.password,
        );
      } catch {
        return await pds.accounts.createSession(troll.handle, troll.password);
      }
    },
    (s) => `did=${s.did}`,
  );

  if (session) {
    troll.did = session.did;
    troll.accessJwt = session.accessJwt;
  } else {
    result.finish();
    return result;
  }

  const post = await timedCall(
    result,
    "Troll creates post",
    async () => {
      return await pds.raw.post("com.atproto.repo.createRecord", {
        repo: troll.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Bad content that will be taken down.",
          createdAt: now(),
        },
      }, troll.accessJwt);
    },
    (r) => `uri=${r.uri}`,
  );

  const adminPassword = Deno.env.get("PDS_ADMIN_PASSWORD") ||
    "test-admin-password";
  const adminToken = await timedCall(
    result,
    "Admin login",
    async () => pds.adminLogin(adminPassword),
    () => "obtained admin bearer",
  );

  if (post && adminToken) {
    await timedCall(
      result,
      "Admin applies record takedown",
      async () => {
        await pds.raw.post("com.atproto.admin.updateSubjectStatus", {
          subject: {
            $type: "com.atproto.repo.strongRef",
            uri: post.uri,
            cid: post.cid,
          },
          takedown: { applied: true, ref: "takedown-e2e-test" },
        }, adminToken);
      },
    );
  } else {
    result.stepSkipped(
      "Admin applies record takedown",
      "post or admin token missing",
    );
  }

  // --- Public read after record takedown ---
  // A public (unauthenticated) read of the taken-down record must be rejected (404 or 410).
  if (post && adminToken) {
    const postRkey = post.uri.split("/").pop()!;

    await timedCall(
      result,
      "Public read of taken-down record is hidden",
      async () => {
        // No auth token — public read must fail
        await pds.raw.get("com.atproto.repo.getRecord", {
          repo: troll.did,
          collection: "app.bsky.feed.post",
          rkey: postRkey,
        });
      },
      undefined,
      true, // must throw (404 or 410)
    );

    // --- Admin read after record takedown ---
    // An admin-authenticated read of the same record must still succeed (200).
    const adminRecord = await timedCall(
      result,
      "Admin read of taken-down record succeeds",
      async () => {
        return await pds.raw.get("com.atproto.admin.getRecord", {
          uri: post.uri,
        }, adminToken);
      },
      (r) => `cid=${r?.cid ?? "present"}`,
    );

    // Verify the returned record contains the original content.
    if (adminRecord) {
      const text = adminRecord.value?.text ?? adminRecord.record?.text;
      if (text === "Bad content that will be taken down.") {
        result.stepPassed(
          "Admin record content matches original",
          `text="${text}"`,
        );
      } else {
        result.stepFailed(
          "Admin record content matches original",
          `expected original text, got: ${JSON.stringify(text)}`,
        );
      }
    }

    // --- Account-level takedown: all public repo reads hidden ---
    await timedCall(
      result,
      "Admin applies account-level takedown",
      async () => {
        await pds.raw.post("com.atproto.admin.updateSubjectStatus", {
          subject: {
            $type: "com.atproto.admin.defs#repoRef",
            did: troll.did,
          },
          takedown: { applied: true, ref: "account-takedown-e2e" },
        }, adminToken);
      },
    );

    await timedCall(
      result,
      "Account takedown hides all public repo reads",
      async () => {
        await pds.raw.get("com.atproto.repo.listRecords", {
          repo: troll.did,
          collection: "app.bsky.feed.post",
        });
      },
      undefined,
      true, // must throw (400/AccountTakedown or 403)
    );
  } else {
    result.stepSkipped(
      "Public read of taken-down record is hidden",
      "post or admin token missing",
    );
    result.stepSkipped(
      "Admin read of taken-down record succeeds",
      "post or admin token missing",
    );
    result.stepSkipped(
      "Admin applies account-level takedown",
      "post or admin token missing",
    );
    result.stepSkipped(
      "Account takedown hides all public repo reads",
      "post or admin token missing",
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
