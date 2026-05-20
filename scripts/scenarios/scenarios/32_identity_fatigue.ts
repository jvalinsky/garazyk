/**
 * @module scenarios/32_identity_fatigue
 *
 * Scenario: Exhausts PLC operation quota and rejects further identity operations.
 *
 * Behavior:
 * - Executes the 32 identity fatigue scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
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

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Identity Fatigue");
  result.start();

  const client = new XrpcClient(PDS1);
  const rosa = getCharacter("rosa");

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create account: rosa", async () => {
    return await client.accounts.createAccount(rosa.handle, rosa.email, rosa.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  rosa.did = session.did;
  rosa.accessJwt = session.accessJwt;

  const hourlyLimit = parseInt(Deno.env.get("PLC_HOURLY_LIMIT") || "5");
  const rotations = Math.min(hourlyLimit - 1, 10);

  let successCount = 0;
  for (let i = 0; i < rotations; i++) {
    try {
      const tokenResp = await client.raw.xrpcPost(
        "com.atproto.identity.requestPlcOperationSignature",
        {},
        rosa.accessJwt,
      );
      const signResp = await client.raw.xrpcPost("com.atproto.identity.signPlcOperation", {
        token: tokenResp.token,
        alsoKnownAs: [`at://rev-${i}-${rosa.handle}`],
      }, rosa.accessJwt);

      const op = { ...signResp.operation };
      delete op.did;

      const plcRes = await fetch(`${SERVICE_URLS.plc}/${rosa.did}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(op),
      });

      if (plcRes.status === 200) {
        successCount++;
      } else {
        result.stepFailed("Exhaust Quota", `Failed at iteration ${i}: ${plcRes.status}`);
        break;
      }
    } catch (e) {
      result.stepFailed("Exhaust Quota", String(e));
      break;
    }
  }

  if (successCount === rotations) {
    result.stepPassed("Quota Exhaustion", `Successfully performed ${successCount} rotations`);

    // Final rotation should fail
    const tokenResp = await client.raw.xrpcPost(
      "com.atproto.identity.requestPlcOperationSignature",
      {},
      rosa.accessJwt,
    );
    const signResp = await client.raw.xrpcPost("com.atproto.identity.signPlcOperation", {
      token: tokenResp.token,
      alsoKnownAs: [`at://final-${rosa.handle}`],
    }, rosa.accessJwt);

    const op = { ...signResp.operation };
    delete op.did;

    const plcRes = await fetch(`${SERVICE_URLS.plc}/${rosa.did}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(op),
    });

    const body = await plcRes.text();
    if (plcRes.status === 400 && body.includes("Too many operations")) {
      result.stepPassed("Verify Hourly Limit", "Rejected operation after limit reached");
    } else {
      result.stepFailed(
        "Verify Hourly Limit",
        `Expected 400 rejection, got ${plcRes.status}: ${body}`,
      );
    }
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
