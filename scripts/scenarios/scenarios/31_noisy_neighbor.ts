/**
 * @module scenarios/31_noisy_neighbor
 *
 * Scenario: Verifies rate limiting is isolated between accounts.
 *
 * Behavior:
 * - Executes the 31 noisy neighbor scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
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
  const result = new ScenarioResult("Rate Limiting Isolation");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const troll = getCharacter("troll");
  const luna = getCharacter("luna");

  for (const char of [troll, luna]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
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
      await client.raw.xrpcGet("app.bsky.actor.getProfile", { actor: troll.did }, troll.accessJwt);
      successCount++;
    } catch {
      break;
    }
  }

  if (successCount === 60) {
    result.stepPassed("Troll burst completion", `success_count=${successCount}`);
  } else {
    result.stepFailed("Troll burst completion", `Expected 60 successes, got ${successCount}`);
  }

  // 4. Troll's 61st request should fail with 429
  await timedCall(
    result,
    "Troll's 61st request (Expect 429)",
    async () => {
      await client.raw.xrpcGet("app.bsky.actor.getProfile", { actor: troll.did }, troll.accessJwt);
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
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
