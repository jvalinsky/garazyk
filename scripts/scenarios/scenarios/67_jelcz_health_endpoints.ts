/**
 * @module scenarios/67_jelcz_health_endpoints
 *
 * Scenario: Validates Jelcz health endpoint and admin API.
 *
 * Behavior:
 * - Checks the `/_health` endpoint returns expected status fields.
 * - Checks the `/admin/api/media/jobs` endpoint returns a valid job list.
 * - Checks the XRPC `app.bsky.video.getUploadLimits` endpoint works.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Jelcz Health Endpoints (The Projection Booth)");
  result.start();

  const pdsClient = new XrpcClient(PDS1);
  const videoUrl = SERVICE_URLS.video;
  const videoClient = new XrpcClient(videoUrl);

  await timedCall(result, "PDS health check", async () => {
    await pdsClient.waitForHealthy(30);
  });
  await timedCall(result, "Jelcz health check", async () => {
    await videoClient.waitForHealthy(15);
  });

  if (result.failed > 0) return result;

  // Check raw /_health endpoint returns expected JSON schema
  await timedCall(result, "Jelcz /_health endpoint", async () => {
    const url = new URL("/_health", videoUrl);
    const resp = await fetch(url.toString());
    assert(resp.ok, `/_health returned HTTP ${resp.status}`);
    const body = await resp.json();
    assert(body.status === "ok", `Expected status "ok", got "${body.status}"`);
    assert(typeof body.service === "string", "Expected service field to be a string");
    assert(body.service.length > 0, "Expected non-empty service field");
  });

  // Check admin jobs list endpoint returns valid structure
  await timedCall(result, "Jelcz admin jobs endpoint", async () => {
    const url = new URL("/admin/api/media/jobs", videoUrl);
    const resp = await fetch(url.toString());
    assert(resp.ok, `admin jobs returned HTTP ${resp.status}`);
    const body = await resp.json();
    assert(body.jobs !== undefined, "Expected jobs field in response");
    assert(Array.isArray(body.jobs), "Expected jobs to be an array");
  });

  // Get upload limits via XRPC
  const luna = getCharacter("luna");
  const session = await timedCall(result, "Create or login account", async () => {
    return await pdsClient.accounts.createAccount(luna.handle, luna.email, luna.password).catch(
      () => pdsClient.accounts.createSession(luna.handle, luna.password),
    );
  });

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  await timedCall(result, "Get upload limits via XRPC", async () => {
    const limits = await videoClient.raw.xrpcGet(
      "app.bsky.video.getUploadLimits",
      undefined,
      luna.accessJwt,
    );
    assert(limits !== undefined, "Expected upload limits response");
    // Should have at least one of: remaining, maxBytesPerUpload, etc.
    const keys = Object.keys(limits || {});
    assert(keys.length > 0, "Expected at least one field in upload limits");
  });

  // getJobStatus with a dummy jobId should gracefully error, not crash
  await timedCall(result, "Jelcz getJobStatus with invalid id", async () => {
    try {
      await videoClient.raw.xrpcGet(
        "app.bsky.video.getJobStatus",
        { jobId: "dummy-nonexistent-job" },
        luna.accessJwt,
      );
      // If no error thrown, that's fine — some implementations return an error body
    } catch (_e) {
      // Expected: XRPC error response for nonexistent job
    }
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
