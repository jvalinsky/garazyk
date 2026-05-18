/**
 * @module scenarios/01_account_lifecycle
 *
 * Scenario: Account Lifecycle & Identity verification.
 *
 * Behavior:
 * - Creates a new user account on the PDS.
 * - Verifies session establishment, handle resolution, and PLC DID resolution.
 * - Creates and retrieves a user profile.
 * - Tests session refreshing and invalid login handling.
 * - Logs the user out.
 *
 * Expectations:
 * - All lifecycle operations complete successfully with valid responses.
 */

import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext, ScenarioResult, timedCall, assert } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @param ctx - The scenario context including character registry and service URLs
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Lifecycle & Identity");
  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");

  await timedCall(
    result,
    "Verify PDS health",
    async () => {
      const res = await fetch(`${ctx.pds1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Describe server",
    async () => {
      return await pds.api.com.atproto.server.describeServer();
    },
    (d: any) => `domains=${d.availableUserDomains}`,
  );

  const session = await timedCall(
    result,
    "Create account",
    async () => {
      try {
        const res = await pds.agent.createAccount({
          handle: luna.handle,
          email: luna.email,
          password: luna.password,
        });
        return res.data;
      } catch (e: any) {
        throw new Error(`Failed to create account: ${e.message || String(e)}`);
      }
    },
    (s: any) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Verify handle resolution",
    async () => {
      const res = await pds.api.com.atproto.identity.resolveHandle({
        handle: luna.handle,
      });
      assert.equal(res.did, session.did, "DID mismatch in handle resolution");
      return res;
    },
  );

  await timedCall(
    result,
    "Verify PLC resolution",
    async () => {
      const plcUrl = (ctx as any).plc || "https://plc.directory";
      const res = await fetch(`${plcUrl}/${session.did}`);
      if (!res.ok) throw new Error("PLC resolution failed");
      const doc = await res.json();
      assert.equal(doc.id, session.did, "DID mismatch in PLC document");
    },
  );

  await timedCall(
    result,
    "Get session",
    async () => {
      const res = await pds.agent.com.atproto.server.getSession(undefined, {
        headers: { Authorization: `Bearer ${luna.accessJwt}` },
      });
      return res.data;
    },
    (s: any) => `handle=${s.handle}`,
  );

  await timedCall(
    result,
    "Create profile",
    async () => {
      const res = await pds.agent.com.atproto.repo.createRecord({
        repo: luna.did,
        collection: "app.bsky.actor.profile",
        record: {
          $type: "app.bsky.actor.profile",
          displayName: "Luna Valinsky",
          description: "Testing account lifecycle",
        },
      });
      return res.data;
    },
    (r: any) => `uri=${r.uri}`,
  );

  await timedCall(
    result,
    "Verify profile via XRPC",
    async () => {
      return await pds.api.app.bsky.actor.getProfile(
        { actor: luna.did },
        luna.accessJwt,
      );
    },
    (p) => `displayName=${p?.displayName}`,
  );

  if (luna.refreshJwt) {
    const refreshed = await timedCall(
      result,
      "Refresh session",
      async () => {
        const res = await pds.agent.com.atproto.server.refreshSession(undefined, {
          headers: { Authorization: `Bearer ${luna.refreshJwt}` },
        });
        return res.data;
      },
    );

    if (refreshed) {
      luna.accessJwt = refreshed.accessJwt;
      luna.refreshJwt = refreshed.refreshJwt;
    }
  }

  await timedCall(
    result,
    "Login with invalid credentials",
    async () => {
      try {
        await pds.agent.login({
          identifier: luna.handle,
          password: "wrong-password",
        });
        throw new Error("Login should have failed");
      } catch (err: any) {
        if (!err.message.includes("Invalid identifier or password")) {
          throw err;
        }
      }
    },
  );

  try {
    await timedCall(
      result,
      "Delete session",
      async () => {
        await pds.api.com.atproto.server.deleteSession(undefined, luna.accessJwt);
      },
    );
  } catch (exc: any) {
    result.stepSkipped("Delete session", exc.message || String(exc));
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
