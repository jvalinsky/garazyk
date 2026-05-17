/**
 * @module scenarios/30_temporal_distortion
 *
 * Scenario: 30 temporal distortion
 *
 * Behavior:
 * - Executes the 30 temporal distortion scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getCharacter, PDS1 } from "@garazyk/hamownia";
import { ScenarioResult } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Temporal Distortion");
  result.start();

  const client = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await timedCall(result, "Create Luna", async () => {
    return await client.accounts.createAccount(luna.handle, luna.email, luna.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  await timedCall(result, "Create Post A", async () => {
    return await client.records.createRecord(
      luna.did,
      "app.bsky.feed.post",
      { $type: "app.bsky.feed.post", text: "Post A", createdAt: now() },
      luna.accessJwt,
    );
  });

  const repoHead = await client.raw.xrpcGet("com.atproto.sync.getHead", { did: luna.did });
  assert.isTrue(repoHead.root, "Missing root in getHead");

  // Monotonicity burst
  for (let i = 0; i < 10; i++) {
    await client.records.createRecord(
      luna.did,
      "app.bsky.feed.post",
      { $type: "app.bsky.feed.post", text: `Burst ${i}`, createdAt: now() },
      luna.accessJwt,
    );
  }

  result.stepPassed("Monotonicity burst completed");
  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
