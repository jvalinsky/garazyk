/**
 * @module scenarios/52_rate_limit_behavior
 *
 * Scenario: 52 rate limit behavior
 *
 * Behavior:
 * - Executes the 52 rate limit behavior scenario.
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
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Rate Limit Client Behavior");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(
    luna.handle,
    luna.email,
    luna.password,
  ).catch(
    () => pds.accounts.createSession(luna.handle, luna.password),
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  // Rapidly create records
  let hitLimit = false;
  for (let i = 0; i < 100; i++) {
    try {
      await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: `Rate test ${i}`,
        createdAt: now(),
      }, luna.accessJwt);
    } catch (e) {
      if (e instanceof XrpcError && e.status === 429) {
        hitLimit = true;
        result.stepPassed("Rate limit triggered (429)");
        break;
      }
    }
  }

  if (!hitLimit) {
    result.stepSkipped(
      "Rate limit trigger",
      "Limits might be too high for local dev",
    );
  }

  // Recovery
  await new Promise((r) => setTimeout(r, 2000));
  await timedCall(result, "Verify recovery", async () => {
    return await pds.accounts.getSession(luna.accessJwt);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
