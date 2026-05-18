/**
 * @module scenarios/29_depth_charger
 *
 * Scenario: 29 depth charger
 *
 * Behavior:
 * - Executes the 29 depth charger scenario.
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
  const result = new ScenarioResult("The Depth Charger");
  result.start();

  const client = new XrpcClient(ctx.pds1);
  const marcus = ctx.getCharacter("marcus");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create Marcus", async () => {
    return await client.accounts.createAccount(
      marcus.handle,
      marcus.email,
      marcus.password,
    );
  });

  if (!session) {
    result.finish();
    return result;
  }
  marcus.did = session.did;
  marcus.accessJwt = session.accessJwt;

  // 1. Lexicon Nesting Limit
  let deepMap: any = { a: "b" };
  for (let i = 0; i < 40; i++) {
    deepMap = { n: deepMap };
  }

  await timedCall(
    result,
    "Reject 32-level Lexicon nesting",
    async () => {
      await client.records.createRecord(
        marcus.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "too deep",
          createdAt: now(),
          testExtra: deepMap,
        },
        marcus.accessJwt,
      );
    },
    undefined,
    true, // Expect failure
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
