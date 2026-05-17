/**
 * @module scenarios/58_account_delete_cascade
 *
 * Scenario: 58 account delete cascade
 *
 * Behavior:
 * - Executes the 58 account delete cascade scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { PDS1 } from "@garazyk/scenario-runner";
import { ScenarioResult } from "@garazyk/scenario-runner";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/scenario-runner";
export type { ScenarioReport } from "@garazyk/scenario-runner";
import { XrpcClient } from "@garazyk/atproto-client";
import { assert } from "@garazyk/scenario-runner";
import { timedCall } from "@garazyk/scenario-runner";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: hard-delete of an account; assert records gone, blobs inaccessible, sessions revoked.
// Distinct from 41_account_deactivation.ts (deactivation, not hard-delete)
// and 51_blob_garbage_collection.ts (orphaned blobs from rolled-back transactions).
// Production paths: com.atproto.server.deleteAccount (body: {did, password}),
//   com.atproto.repo.listRecords, com.atproto.sync.getRepo/getBlob,
//   com.atproto.server.getSession.

function now() {
  return new Date().toISOString();
}

// Minimal 1×1 PNG for blob test.
const TINY_PNG = new Uint8Array([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x00,
  0x02,
  0x00,
  0x01,
  0xE2,
  0x21,
  0xBC,
  0x33,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Delete Cascade");
  result.start();

  const pds = new XrpcClient(PDS1);

  // "ghost" is not in config.ts BASE_CHARACTERS — create an ephemeral account inline
  // so this scenario is self-contained and always cleans up after itself.
  const suffix = Date.now();
  const ghostHandle = `ghost-${suffix}.test`;
  const ghostEmail = `ghost-${suffix}@test.com`;
  const ghostPassword = "ghost_pass_123";
  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(
    result,
    "Create ghost account",
    async () => {
      try {
        return await pds.accounts.createAccount(ghostHandle, ghostEmail, ghostPassword);
      } catch {
        return await pds.accounts.createSession(ghostHandle, ghostPassword);
      }
    },
    (s) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }

  const ghostDid = session.did;
  const ghostAccessJwt = session.accessJwt;

  // Seed records before deleting.
  await timedCall(result, "Ghost creates profile + post", async () => {
    await pds.raw.post("com.atproto.repo.createRecord", {
      repo: ghostDid,
      collection: "app.bsky.actor.profile",
      rkey: "self",
      record: { $type: "app.bsky.actor.profile", displayName: "Ghost Account" },
    }, ghostAccessJwt);
    await pds.raw.post("com.atproto.repo.createRecord", {
      repo: ghostDid,
      collection: "app.bsky.feed.post",
      record: { $type: "app.bsky.feed.post", text: "Soon to be deleted.", createdAt: now() },
    }, ghostAccessJwt);
  });

  // Upload a blob so we can verify it becomes inaccessible after account deletion.
  const blobResult = await timedCall(
    result,
    "Ghost uploads a blob",
    async () => pds.blobs.uploadBlob(TINY_PNG, "image/png", ghostAccessJwt!),
    (r) => `cid=${(r as any)?.blob?.$link ?? (r as any)?.blob?.ref?.$link ?? "present"}`,
  );
  const blobCid: string | null = (blobResult as any)?.blob?.$link ??
    (blobResult as any)?.blob?.ref?.$link ??
    null;

  // --- Hard-delete the account ---
  // com.atproto.server.deleteAccount requires {did, password} in the body.
  // No Authorization header needed — the password is the credential (XrpcServerPack.m:1291).
  await timedCall(
    result,
    "Hard-delete ghost account",
    async () => {
      await pds.raw.post("com.atproto.server.deleteAccount", {
        did: ghostDid,
        password: ghostPassword,
      });
    },
  );

  if (result.failed > 0) {
    // If deleteAccount itself failed, the cascade assertions below are meaningless.
    result.finish();
    return result;
  }

  // --- Records gone ---
  // listRecords on a deleted account must be rejected (404 or 400/AccountNotFound).
  await timedCall(
    result,
    "Records gone after delete",
    async () => {
      await pds.raw.get("com.atproto.repo.listRecords", {
        repo: ghostDid,
        collection: "app.bsky.feed.post",
      });
    },
    undefined,
    true, // must throw
  );

  // --- Repo CAR gone ---
  // getRepo must return 404 or 400 for the deleted DID.
  await timedCall(
    result,
    "Repo CAR inaccessible after delete",
    async () => {
      await pds.raw.xrpcGetBinary("com.atproto.sync.getRepo", {
        params: { did: ghostDid },
      });
    },
    undefined,
    true, // must throw
  );

  // --- Sessions revoked ---
  // The ghost's accessJwt must no longer be accepted after account deletion.
  await timedCall(
    result,
    "Sessions revoked after delete",
    async () => {
      await pds.accounts.getSession(ghostAccessJwt!);
    },
    undefined,
    true, // must throw 401
  );

  // --- Blob inaccessible after account delete ---
  if (blobCid) {
    await timedCall(
      result,
      "Blob inaccessible after account delete",
      async () => {
        await pds.raw.xrpcGetBinary("com.atproto.sync.getBlob", {
          params: { did: ghostDid, cid: blobCid },
        });
      },
      undefined,
      true, // must throw 404
    );
  } else {
    result.stepSkipped("Blob inaccessible after account delete", "no blob was uploaded");
  }

  // Firehose tombstone verification requires a streaming consumer — out of scope for this tier.
  result.stepSkipped(
    "Firehose tombstone emitted",
    "P2: requires streaming firehose consumer — implement separately",
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
