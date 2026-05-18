/**
 * @module scenarios/32_identity_fatigue
 *
 * Scenario: 32 identity fatigue
 *
 * Behavior:
 * - Executes the 32 identity fatigue scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext } from "@garazyk/hamownia";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Identity Fatigue");
  result.start();

  const client = new XrpcClient(ctx.pds1);
  const rosa = ctx.getCharacter("rosa");

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create account: rosa", async () => {
    return await client.accounts.createAccount(
      rosa.handle,
      rosa.email,
      rosa.password,
    );
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
      const signResp = await client.raw.xrpcPost(
        "com.atproto.identity.signPlcOperation",
        {
          token: tokenResp.token,
          alsoKnownAs: [`at://rev-${i}-${rosa.handle}`],
        },
        rosa.accessJwt,
      );

      const op = { ...signResp.data.operation };
      delete op.did;

      const plcRes = await fetch(`${ctx.serviceUrls.plc}/${rosa.did}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(op),
      });

      if (plcRes.status === 200) {
        successCount++;
      } else {
        result.stepFailed(
          "Exhaust Quota",
          `Failed at iteration ${i}: ${plcRes.status}`,
        );
        break;
      }
    } catch (e) {
      result.stepFailed("Exhaust Quota", String(e));
      break;
    }
  }

  if (successCount === rotations) {
    result.stepPassed(
      "Quota Exhaustion",
      `Successfully performed ${successCount} rotations`,
    );

    // Final rotation should fail
    const tokenResp = await client.raw.xrpcPost(
      "com.atproto.identity.requestPlcOperationSignature",
      {},
      rosa.accessJwt,
    );
    const signResp = await client.raw.xrpcPost(
      "com.atproto.identity.signPlcOperation",
      {
        token: tokenResp.token,
        alsoKnownAs: [`at://final-${rosa.handle}`],
      },
      rosa.accessJwt,
    );

    const op = { ...signResp.data.operation };
    delete op.did;

    const plcRes = await fetch(`${ctx.serviceUrls.plc}/${rosa.did}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(op),
    });

    const body = await plcRes.text();
    if (plcRes.status === 400 && body.includes("Too many operations")) {
      result.stepPassed(
        "Verify Hourly Limit",
        "Rejected operation after limit reached",
      );
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
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
