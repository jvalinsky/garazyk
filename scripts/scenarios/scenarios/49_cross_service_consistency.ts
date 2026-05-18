/**
 * @module scenarios/49_cross_service_consistency
 *
 * Scenario: 49 cross service consistency
 *
 * Behavior:
 * - Executes the 49 cross service consistency scenario.
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
  const result = new ScenarioResult("Cross-Service Consistency");
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

  const postRkey = `consistency-${Date.now()}`;
  const postText = "Testing consistency!";
  const postRef = await timedCall(result, "Create post on PDS", async () => {
    return await pds.records.createRecord(
      luna.did,
      "app.bsky.feed.post",
      {
        $type: "app.bsky.feed.post",
        text: postText,
        createdAt: now(),
      },
      luna.accessJwt,
      { rkey: postRkey },
    );
  });

  if (postRef) {
    const postUri = postRef.uri;
    let found = false;
    for (let i = 0; i < 15; i++) {
      try {
        const avPost = await appview.feed.getPosts([postUri], luna.accessJwt);
        if (avPost.posts?.length > 0) {
          found = true;
          break;
        }
      } catch { /* ignore */ }
      await new Promise((r) => setTimeout(r, 1000));
    }

    if (found) {
      result.stepPassed("AppView indexed post");
      const avPost = await appview.feed.getPosts([postUri], luna.accessJwt);
      const avText = avPost.posts[0].record?.text;
      assert.isTrue(
        avText === postText,
        `Content drift: ${avText} !== ${postText}`,
      );
      result.stepPassed("PDS-AppView content match");
    } else {
      result.stepFailed("AppView index timeout", "Post not found after 15s");
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
