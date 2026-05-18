/**
 * @module scenarios/43_multi_device_sessions
 *
 * Scenario: 43 multi device sessions
 *
 * Behavior:
 * - Executes the 43 multi device sessions scenario.
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

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Multi-Device Session Management");
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

  const d1 = await timedCall(result, "Create session on device 1", async () => {
    return await pds.accounts.createSession(luna.handle, luna.password);
  });

  const d2 = await timedCall(result, "Create session on device 2", async () => {
    return await pds.accounts.createSession(luna.handle, luna.password);
  });

  if (d1 && d2) {
    await timedCall(result, "Verify device 1 session valid", async () => {
      return await pds.accounts.getSession(d1.accessJwt);
    });

    await timedCall(result, "Verify device 2 session valid", async () => {
      return await pds.accounts.getSession(d2.accessJwt);
    });

    await timedCall(result, "Delete device 1 session", async () => {
      return await pds.accounts.deleteSession(d1.accessJwt);
    });

    await timedCall(result, "Verify device 2 session still valid", async () => {
      return await pds.accounts.getSession(d2.accessJwt);
    });

    await timedCall(
      result,
      "Verify device 1 session invalid",
      async () => {
        await pds.accounts.getSession(d1.accessJwt);
      },
      undefined,
      true, // Expect failure
    );
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
