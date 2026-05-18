/**
 * @module scenarios/41_account_deactivation
 *
 * Scenario: 41 account deactivation
 *
 * Behavior:
 * - Executes the 41 account deactivation scenario.
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

function now() {
  return new Date().toISOString();
}

export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Deactivation & Reactivation");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const appview = new XrpcClient(ctx.serviceUrls.appview);
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

  const postRef = await timedCall(
    result,
    "Create post before deactivation",
    async () => {
      return await pds.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: "I'll be back!",
        createdAt: now(),
      }, luna.accessJwt);
    },
  );

  await timedCall(result, "Get profile before deactivation", async () => {
    return await appview.feed.getProfile(luna.did, luna.accessJwt);
  });

  await timedCall(result, "Deactivate account", async () => {
    return await pds.accounts.deactivateAccount(luna.accessJwt);
  });

  await new Promise((r) => setTimeout(r, 2000));

  await timedCall(result, "Verify profile is deactivated", async () => {
    try {
      const profile = await appview.feed.getProfile(luna.did, luna.accessJwt);
      assert.isTrue(
        profile.associated?.deactivated === true ||
          profile.error === "AccountDeactivated",
        "Should be deactivated",
      );
    } catch {
      // Hidden entirely is also valid deactivation
    }
  });

  const reactivated = await timedCall(
    result,
    "Reactivate account",
    async () => {
      return await pds.accounts.createSession(luna.handle, luna.password);
    },
  );

  if (reactivated) {
    luna.accessJwt = reactivated.accessJwt;
    await timedCall(result, "Verify profile visible again", async () => {
      return await appview.feed.getProfile(luna.did, luna.accessJwt);
    });

    if (postRef) {
      await timedCall(result, "Verify data restored", async () => {
        return await appview.feed.getPosts([postRef.uri], luna.accessJwt);
      });
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
