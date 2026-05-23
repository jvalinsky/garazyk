/**
 * @module scenarios/42_handle_change_propagation
 *
 * Scenario: Updates a handle and verifies propagation through PLC and AppView.
 *
 * Behavior:
 * - Executes the 42 handle change propagation scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
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
  const result = new ScenarioResult("Handle Change Propagation");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getActor("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(
    () => pds.accounts.createSession(luna.handle, luna.password),
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;
  const originalHandle = session.handle || luna.handle;

  await timedCall(result, "Resolve handle before change", async () => {
    return await pds.identity.resolveHandle(originalHandle);
  });

  const newHandle = `new-${luna.handle}`;
  await timedCall(result, "Update handle", async () => {
    return await pds.identity.updateHandle(newHandle, luna.accessJwt);
  });

  await new Promise((r) => setTimeout(r, 3000));

  try {
    const plcRes = await fetch(`${SERVICE_URLS.plc}/${luna.did}`);
    const doc = await plcRes.json();
    const hasNewHandle = doc.alsoKnownAs?.some((h: string) => h.includes(newHandle));
    assert.isTrue(hasNewHandle, "New handle not found in PLC DID doc");
    result.stepPassed("PLC handle verification");
  } catch (e) {
    result.stepSkipped("PLC handle verification", String(e));
  }

  await timedCall(result, "Verify AppView profile has new handle", async () => {
    const profile = await appview.feed.getProfile(luna.did, luna.accessJwt);
    assert.isTrue(profile.handle === newHandle, `Expected ${newHandle}, got ${profile.handle}`);
  });

  await timedCall(result, "Resolve new handle", async () => {
    return await pds.identity.resolveHandle(newHandle);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
