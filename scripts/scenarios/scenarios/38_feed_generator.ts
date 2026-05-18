/**
 * @module scenarios/38_feed_generator
 *
 * Scenario: 38 feed generator
 *
 * Behavior:
 * - Executes the 38 feed generator scenario.
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
  const result = new ScenarioResult("Feed Generator Lifecycle");
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

  const feedRkey = `test-feed-${Date.now()}`;
  const feedRecord = {
    $type: "app.bsky.feed.generator",
    did: luna.did,
    displayName: "Luna's Test Feed",
    description: "A curated feed for testing",
    createdAt: now(),
  };

  const feedRef = await timedCall(result, "Create feed generator", async () => {
    return await pds.records.createRecord(
      luna.did,
      "app.bsky.feed.generator",
      feedRecord,
      luna.accessJwt,
      { rkey: feedRkey },
    );
  });

  if (feedRef) {
    const feedUri = feedRef.uri;
    await new Promise((r) => setTimeout(r, 2000));

    await timedCall(result, "Get feed generator from AppView", async () => {
      // Note: XrpcClient.feed.getFeedGenerators handles join(",")
      return await appview.feed.getFeedGenerators([feedUri], luna.accessJwt);
    });

    await timedCall(result, "Get custom feed", async () => {
      return await appview.feed.getFeed(feedUri, luna.accessJwt, 10);
    });
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
