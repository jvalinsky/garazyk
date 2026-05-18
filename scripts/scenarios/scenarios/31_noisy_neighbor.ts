/**
 * @module scenarios/31_noisy_neighbor
 *
 * Scenario: 31 noisy neighbor
 *
 * Behavior:
 * - Executes the 31 noisy neighbor scenario.
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
  const result = new ScenarioResult("Rate Limiting Isolation");
  result.start();

  const client = new XrpcClient(ctx.pds1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const troll = ctx.getCharacter("troll");
  const luna = ctx.getCharacter("luna");

  for (const char of [troll, luna]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(
          char.handle,
          char.email,
          char.password,
        );
      },
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!troll.did || !luna.did) {
    result.stepFailed("Setup", "Failed to create test accounts");
    result.finish();
    return result;
  }

  // 3. Troll performs 60 rapid requests
  let successCount = 0;
  for (let i = 0; i < 60; i++) {
    try {
      await client.raw.xrpcGet("app.bsky.actor.getProfile", {
        actor: troll.did,
      }, troll.accessJwt);
      successCount++;
    } catch {
      break;
    }
  }

  if (successCount === 60) {
    result.stepPassed(
      "Troll burst completion",
      `success_count=${successCount}`,
    );
  } else {
    result.stepFailed(
      "Troll burst completion",
      `Expected 60 successes, got ${successCount}`,
    );
  }

  // 4. Troll's 61st request should fail with 429
  await timedCall(
    result,
    "Troll's 61st request (Expect 429)",
    async () => {
      await client.raw.xrpcGet("app.bsky.actor.getProfile", {
        actor: troll.did,
      }, troll.accessJwt);
    },
    undefined,
    true,
  );

  // 5. Luna's request should succeed (Isolation)
  await timedCall(
    result,
    "Luna's request (Expect 200 OK)",
    async () => {
      return await client.raw.xrpcGet(
        "app.bsky.actor.getProfile",
        { actor: luna.did },
        luna.accessJwt,
      );
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
