/**
 * @module scenarios/54_negative_auth_paths
 *
 * Scenario: Rejects revoked and expired tokens, cross-account writes, and suspended-account access.
 *
 * Behavior:
 * - Executes the 54 negative auth paths scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: revoked token reuse, expired JWT rejection, cross-account write denial,
//   suspended account write, suspended account read.
// Production paths: com.atproto.server.{deleteSession,createSession,deactivateAccount},
//   com.atproto.repo.{createRecord,listRecords} (auth enforcement).

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Negative Auth Paths");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");
  const nova = getActor("nova");
  const volt = getActor("volt");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Setup: create accounts ---

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
    luna.refreshJwt = lunaSession.refreshJwt;
  } else {
    result.finish();
    return result;
  }

  const novaSession = await timedCall(
    result,
    "Create nova account",
    async () => {
      try {
        return await pds.accounts.createAccount(nova.handle, nova.email, nova.password);
      } catch {
        return await pds.accounts.createSession(nova.handle, nova.password);
      }
    },
    (s) => `did=${s.did}`,
  );

  if (novaSession) {
    nova.did = novaSession.did;
    nova.accessJwt = novaSession.accessJwt;
  }

  const voltSession = await timedCall(
    result,
    "Create volt account",
    async () => {
      try {
        return await pds.accounts.createAccount(volt.handle, volt.email, volt.password);
      } catch {
        return await pds.accounts.createSession(volt.handle, volt.password);
      }
    },
    (s) => `did=${s.did}`,
  );

  if (voltSession) {
    volt.did = voltSession.did;
    volt.accessJwt = voltSession.accessJwt;
  }

  // --- Step 1: Revoked token reuse ---
  // Save luna's token, delete the session, then assert the saved token is rejected with 401.
  const savedJwt = luna.accessJwt!;

  await timedCall(result, "Delete luna session (revoke token)", async () => {
    await pds.accounts.deleteSession(savedJwt);
  });

  await timedCall(
    result,
    "Revoked token reuse rejected",
    async () => {
      await pds.accounts.getSession(savedJwt);
    },
    undefined,
    true, // must throw XrpcError(401)
  );

  // Re-login luna so she has a valid token for subsequent steps.
  const lunaSession2 = await timedCall(
    result,
    "Re-login luna after token revocation",
    async () => pds.accounts.createSession(luna.handle, luna.password),
    (s) => `did=${s.did}`,
  );
  if (lunaSession2) luna.accessJwt = lunaSession2.accessJwt;

  // --- Step 2: Expired JWT rejection ---
  // Construct a three-segment base64url JWT with exp=1 (epoch 1970-01-01 00:00:01).
  // The PDS must reject it with 401 regardless of signature validity.
  const b64url = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  const expiredJwt = `${b64url({ alg: "HS256", typ: "JWT" })}` +
    `.${b64url({ sub: "did:plc:fake", exp: 1, iat: 1 })}` +
    `.invalidsig`;

  await timedCall(
    result,
    "Expired JWT rejected",
    async () => {
      await pds.accounts.getSession(expiredJwt);
    },
    undefined,
    true, // must throw (401)
  );

  // --- Step 3: Cross-account write denial ---
  // Luna attempts to create a record in nova's repo using her own token.
  // The PDS must reject this because luna.did != nova.did.
  if (luna.accessJwt && nova.did) {
    await timedCall(
      result,
      "Cross-account write denied",
      async () => {
        await pds.as(luna).raw.post("com.atproto.repo.createRecord", {
          repo: nova.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "unauthorized cross-account write attempt",
            createdAt: now(),
          },
        });
      },
      undefined,
      true, // must throw 401
    );
  } else {
    result.stepSkipped("Cross-account write denied", "prerequisite accounts not ready");
  }

  // --- Step 4: Suspended account write denied ---
  // Deactivate volt, then assert volt can no longer create records.
  if (volt.accessJwt && volt.did) {
    await timedCall(result, "Deactivate volt account", async () => {
      await pds.accounts.deactivateAccount(volt.accessJwt!);
    });

    await timedCall(
      result,
      "Suspended account write denied",
      async () => {
        await pds.as(volt).raw.post("com.atproto.repo.createRecord", {
          repo: volt.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "deactivated account write attempt",
            createdAt: now(),
          },
        });
      },
      undefined,
      true, // must throw 400/AccountDeactivated or 401
    );

    // --- Step 5: Suspended account read behavior ---
    await timedCall(
      result,
      "Suspended account read returns error",
      async () => {
        await pds.raw.get("com.atproto.repo.listRecords", {
          repo: volt.did,
          collection: "app.bsky.feed.post",
        });
      },
      undefined,
      true, // must throw (400/AccountDeactivated or 403)
    );
  } else {
    result.stepSkipped("Deactivate volt account", "volt session not available");
    result.stepSkipped("Suspended account write denied", "volt session not available");
    result.stepSkipped("Suspended account read returns error", "volt session not available");
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
