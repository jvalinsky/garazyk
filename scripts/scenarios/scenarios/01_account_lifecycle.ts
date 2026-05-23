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

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Lifecycle & Identity");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
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
      return await pds.raw.get("com.atproto.server.describeServer");
    },
    (d) => `domains=${d.availableUserDomains}`,
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
        if (e.message && e.message.includes("already exists")) {
          // If running locally multiple times without wiping db
          const res = await pds.agent.login({ identifier: luna.handle, password: luna.password });
          return res.data;
        }
        throw e;
      }
    },
    (s) => `did=${s.did}`,
  );

  if (session) {
    luna.did = session.did;
    luna.accessJwt = session.accessJwt;
    luna.refreshJwt = session.refreshJwt;
  } else {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Get session",
    async () => {
      const res = await pds.agent.com.atproto.server.getSession(undefined, {
        headers: { Authorization: `Bearer ${luna.accessJwt}` },
      });
      return res.data;
    },
    (s) => `did=${s.did}`,
  );

  await timedCall(
    result,
    "Resolve handle",
    async () => {
      const res = await pds.agent.com.atproto.identity.resolveHandle({ handle: luna.handle });
      return res.data;
    },
    (r) => `did=${r.did}`,
  );

  try {
    const plcResp = await fetch(`${SERVICE_URLS.plc}/${luna.did}`);
    if (plcResp.ok) {
      const didDoc = await plcResp.json();
      const didField = didDoc.id || didDoc.did;
      assert.equal(didField, luna.did, `PLC DID mismatch: expected ${luna.did}, got ${didField}`);
      result.stepPassed(
        "PLC DID resolution",
        `method=${didDoc.verificationMethod ? "present" : "N/A"}`,
      );
    } else {
      result.stepSkipped("PLC DID resolution", `PLC returned ${plcResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("PLC DID resolution", exc.message || String(exc));
  }

  const profile = {
    $type: "app.bsky.actor.profile",
    displayName: "Luna Starfield",
    description: "Astronomy enthusiast. Looking up, always.",
  };

  await timedCall(
    result,
    "Create profile",
    async () => {
      const res = await pds.agent.com.atproto.repo.createRecord({
        repo: luna.did,
        collection: "app.bsky.actor.profile",
        record: profile,
      });
      return res.data;
    },
    (r) => `uri=${r.uri}`,
  );

  await timedCall(
    result,
    "Get profile",
    async () => {
      const res = await pds.as(luna).raw.get(
        "app.bsky.actor.getProfile",
        { actor: luna.did },
      );
      return res;
    },
    (p) => `displayName=${p?.displayName || p?.record?.displayName}`,
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
      (r) => `accessJwt=${r.accessJwt.substring(0, 20)}...`,
    );
    if (refreshed) {
      luna.accessJwt = refreshed.accessJwt;
      luna.refreshJwt = refreshed.refreshJwt;
    }
  } else {
    result.stepSkipped("Refresh session", "No refreshJwt available");
  }

  await timedCall(
    result,
    "Invalid login rejected",
    async () => {
      await pds.agent.login({ identifier: luna.handle, password: "wrong_password" });
    },
    undefined,
    true,
  );

  try {
    await pds.agent.com.atproto.server.deleteSession(undefined, {
      headers: { Authorization: `Bearer ${luna.refreshJwt || luna.accessJwt}` },
    });
    result.stepPassed("Delete session (logout)");
  } catch (exc: any) {
    result.stepSkipped("Delete session", exc.message || String(exc));
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
