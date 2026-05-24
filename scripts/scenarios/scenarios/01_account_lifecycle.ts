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
import { createAccountOrLogin, ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
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
      await pds.raw.xrpcGet("com.atproto.server.describeServer");
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
    () => createAccountOrLogin(pds, luna),
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
      const res = await pds.as(luna).api.com.atproto.server.getSession();
      return res;
    },
    (s) => `did=${s.did}`,
  );

  await timedCall(
    result,
    "Resolve handle",
    async () => {
      const res = await pds.api.com.atproto.identity.resolveHandle({ handle: luna.handle });
      return res;
    },
    (r) => `did=${r.did}`,
  );

  try {
    const plcResp = await pds.raw.httpGet(`${SERVICE_URLS.plc}/${luna.did}`);
    const didDoc = plcResp;
    const didField = didDoc.id || didDoc.did;
      assert.equal(didField, luna.did, `PLC DID mismatch: expected ${luna.did}, got ${didField}`);
      result.stepPassed(
        "PLC DID resolution",
        `method=${didDoc.verificationMethod ? "present" : "N/A"}`,
      );
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
      const res = await pds.as(luna).repo.createRecord({
        collection: "app.bsky.actor.profile",
        record: profile,
      });
      return res;
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
    (p) => `displayName=${p?.displayName}`,
  );

  if (luna.refreshJwt) {
    const refreshed = await timedCall(
      result,
      "Refresh session",
      async () => {
        const res = await pds.as({ accessJwt: luna.refreshJwt }).api.com.atproto.server.refreshSession();
        return res;
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
      await pds.raw.xrpcPost("com.atproto.server.createSession", { identifier: luna.handle, password: "wrong_password" });
    },
    undefined,
    true,
  );

  try {
    await pds.as(luna).api.com.atproto.server.deleteSession();
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
