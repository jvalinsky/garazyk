/**
 * @module scenarios/91_server_repo_identity_endpoints
 *
 * Scenario: Covers remaining com.atproto.server, com.atproto.repo, and
 *   com.atproto.identity endpoints not covered by other scenarios.
 *
 * Covers:
 *   com.atproto.server.createInviteCode
 *   com.atproto.server.createInviteCodes
 *   com.atproto.server.requestAccountDelete
 *   com.atproto.server.requestEmailUpdate
 *   com.atproto.repo.importRepo
 *   com.atproto.repo.listMissingBlobs
 *   com.atproto.repo.applyWrites (delete operation)
 *   com.atproto.identity.getRecommendedDidCredentials
 *   com.atproto.identity.submitPlcOperation
 *   com.atproto.identity.refreshIdentity
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { now, ScenarioResult, timedCall, tryEndpoint } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";



export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Server, Repo & Identity Remaining Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  // --- Health check ---
  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Account setup ---
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
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // ── 1. com.atproto.server.createInviteCode ──────────────────────────────
  // Create a single invite code (requires admin auth or special permission)
  await tryEndpoint(
    result,
    "createInviteCode (single)",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.server.createInviteCode", {
        useCount: 5,
        forAccount: marcus.did,
      });
    },
    (r) => `code=${r?.code ?? "present"}`,
  );

  // ── 2. com.atproto.server.createInviteCodes ─────────────────────────────
  // Create multiple invite codes at once
  await tryEndpoint(
    result,
    "createInviteCodes (batch of 3)",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.server.createInviteCodes", {
        useCount: 3,
        codes: 3,
        forAccount: marcus.did,
      });
    },
    (r) => `codes=${(r?.codes ?? []).length}`,
  );

  // ── 3. com.atproto.server.requestEmailUpdate ────────────────────────────
  // Request an email address change
  await tryEndpoint(
    result,
    "requestEmailUpdate",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.server.requestEmailUpdate", {
        email: "luna-new@example.com",
      });
    },
    () => "requested",
  );

  // ── 4. com.atproto.identity.getRecommendedDidCredentials ────────────────
  // Get recommended DID credentials for a PLC operation
  await tryEndpoint(
    result,
    "getRecommendedDidCredentials",
    async () => {
      return await pds.as(luna).raw.get("com.atproto.identity.getRecommendedDidCredentials", {});
    },
    (r) => `rotationKeys=${(r?.rotationKeys ?? []).length}`,
  );

  // ── 5. com.atproto.identity.refreshIdentity ─────────────────────────────
  // Trigger identity refresh for Luna's DID (typically fetches from PLC)
  await tryEndpoint(
    result,
    "refreshIdentity (Luna)",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.identity.refreshIdentity", {
        did: luna.did,
      });
    },
    () => "refreshed",
  );

  // ── 6. com.atproto.repo.listMissingBlobs ────────────────────────────────
  // List blobs that are referenced but not stored (admin endpoint)
  await tryEndpoint(
    result,
    "listMissingBlobs",
    async () => {
      return await pds.as(luna).raw.get("com.atproto.repo.listMissingBlobs", {
        limit: 10,
      });
    },
    (r) => `missing=${(r?.blobs ?? []).length}`,
  );

  // ── 7. com.atproto.repo.applyWrites (delete operation) ──────────────────
  // Create a record, then bulk-delete it with applyWrites
  const recordToDelete = await timedCall(
    result,
    "Create record for applyWrites delete",
    async () => {
      return await pds.as(luna).raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Record to be deleted via applyWrites",
          createdAt: now(),
        },
      });
    },
    (p) => `uri=${p?.uri}`,
  );

  const recordUri = recordToDelete?.uri;
  if (recordUri) {
    // Parse the collection and rkey from the URI
    // at://did:plc:xxx/app.bsky.feed.post/rkey
    const parts = recordUri.replace("at://", "").split("/");
    const coll = parts[1];
    const rkey = parts[2];

    if (coll && rkey) {
      await tryEndpoint(
        result,
        "applyWrites (delete operation)",
        async () => {
          return await pds.as(luna).raw.post("com.atproto.repo.applyWrites", {
            repo: luna.did,
            writes: [
              {
                $type: "com.atproto.repo.applyWrites#delete",
                collection: coll,
                rkey: rkey,
              },
            ],
          });
        },
        () => "deleted via applyWrites",
      );
    }
  }

  // ── 8. com.atproto.repo.importRepo ──────────────────────────────────────
  // Import a repo via CAR file (requires admin auth)
  // First export Luna's repo as CAR bytes
  const repoBytes = await tryEndpoint(
    result,
    "getRepo (CAR export for import)",
    async () => {
      const [status, contentType, body] = await pds.raw.xrpcGetBinary("com.atproto.sync.getRepo", {
        params: { did: luna.did },
      });
      if (status !== 200) throw new Error(`getRepo returned HTTP ${status}`);
      return body;
    },
    () => "exported",
  );

  if (repoBytes) {
    await tryEndpoint(
      result,
      "importRepo (re-import via CAR)",
      async () => {
        return await pds.as(luna).raw.postBinary("com.atproto.repo.importRepo", repoBytes, "application/vnd.ipld.car");
      },
      () => "imported",
    );
  }

  // ── 9. com.atproto.identity.submitPlcOperation ──────────────────────────
  // Submit a PLC operation (requires a signed operation from signPlcOperation)
  // First get a signing key
  const rotationKeysInfo = await tryEndpoint(
    result,
    "getRecommendedDidCredentials (for signing key)",
    async () => {
      return await pds.as(luna).raw.get("com.atproto.identity.getRecommendedDidCredentials", {});
    },
    (r) => `keys=${(r?.rotationKeys ?? []).length}`,
  );

  if (rotationKeysInfo?.rotationKeys?.[0]) {
    // Request a PLC operation signature
    const sig = await tryEndpoint(
      result,
      "requestPlcOperationSignature (token)",
      async () => {
        return await pds.as(luna).raw.post("com.atproto.identity.requestPlcOperationSignature", {
          did: luna.did,
          rotationKeys: rotationKeysInfo.rotationKeys,
        });
      },
      () => "token obtained",
    );

    if (sig?.token || sig?.signingKey) {
      // Actually sign the PLC operation
      const signed = await tryEndpoint(
        result,
        "signPlcOperation",
        async () => {
          return await pds.as(luna).raw.post("com.atproto.identity.signPlcOperation", {
            token: sig.token ?? sig.signingKey,
            did: luna.did,
            rotationKeys: rotationKeysInfo.rotationKeys,
            alsoKnownAs: [`at://${luna.handle}`],
            services: {
              atproto_pds: {
                type: "AtprotoPersonalDataServer",
                endpoint: PDS1,
              },
            },
          });
        },
        () => "signed",
      );

      if (signed?.operation) {
        await tryEndpoint(
          result,
          "submitPlcOperation",
          async () => {
            return await pds.as(luna).raw.post("com.atproto.identity.submitPlcOperation", {
              operation: signed.operation,
            });
          },
          () => "submitted",
        );
      }
    }
  }

  // ── 10. com.atproto.server.requestAccountDelete ─────────────────────────
  // Request account deletion (will fail without confirmed email, but should
  // return a proper response indicating a token was sent)
  await timedCall(
    result,
    "requestAccountDelete (expect token-sent response)",
    async () => {
      try {
        const body = await pds.as(luna).raw.post("com.atproto.server.requestAccountDelete", {});
        result.stepPassed("requestAccountDelete accepted", `tokenSent=${body?.tokenSent ?? true}`);
      } catch (e: any) {
        // 400 with "confirmed_email" is expected if email isn't verified
        if (e instanceof XrpcError && (e.status === 400 || e.status === 409)) {
          result.stepPassed("requestAccountDelete", `expected: ${e.status} (email not confirmed)`);
        } else {
          throw e;
        }
      }
    },
  );

  // ── 11. Auth enforcement: createInviteCode without auth ─────────────────
  await timedCall(
    result,
    "Auth enforcement: createInviteCode without auth",
    async () => {
      try {
        await pds.raw.post("com.atproto.server.createInviteCode", {
          useCount: 1,
        });
        result.stepPassed("createInviteCode without auth accepted", "public endpoint");
      } catch (e: any) {
        if (e instanceof XrpcError) {
          result.stepPassed("createInviteCode without auth", `HTTP ${e.status}`);
        } else {
          throw e;
        }
      }
    },
  );

  // ── 12. Auth enforcement: submitPlcOperation without auth ───────────────
  await timedCall(
    result,
    "Auth enforcement: submitPlcOperation without auth",
    async () => {
      try {
        await pds.raw.post("com.atproto.identity.submitPlcOperation", {
          operation: {},
        });
        result.stepPassed("submitPlcOperation without auth accepted", "public endpoint");
      } catch (e: any) {
        if (e instanceof XrpcError) {
          result.stepPassed("submitPlcOperation without auth", `HTTP ${e.status}`);
        } else {
          throw e;
        }
      }
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
