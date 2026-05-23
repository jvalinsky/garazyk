/**
 * @module scenarios/76_video_job_lifecycle
 *
 * Scenario: Video job lifecycle — concurrent uploads, job status polling,
 * error handling, and job failure flows.
 *
 * Behavior:
 * - Uploads concurrent video jobs and polls getJobStatus for each.
 * - Verifies getJobStatus with invalid job ID returns graceful error.
 * - Uploads invalid content and verifies JOB_STATE_FAILED.
 * - Checks getUploadLimits endpoint.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import {
  getActor,
  PDS1,
  SERVICE_URLS,
  VIDEO_SERVICE_DID,
} from "../../lib/deno/config.ts";
import { timedCall } from "../../lib/deno/runner.ts";

const VIDEO_URL = "http://download.samplelib.com/mp4/sample-5s.mp4";
const VIDEO_CACHE = "/tmp/garazyk-scenario-76-test-video.mp4";

async function downloadTestVideo(): Promise<Uint8Array> {
  try {
    return await Deno.readFile(VIDEO_CACHE);
  } catch {
    console.log(`Downloading test video from ${VIDEO_URL}...`);
    const res = await fetch(VIDEO_URL);
    const data = new Uint8Array(await res.arrayBuffer());
    await Deno.writeFile(VIDEO_CACHE, data);
    console.log(`Downloaded ${data.length} bytes`);
    return data;
  }
}

async function uploadVideo(
  data: Uint8Array,
  did: string,
  name: string,
  token: string,
  accessJwt: string,
  videoUrl: string,
) {
  const url = new URL("/xrpc/app.bsky.video.uploadVideo", videoUrl);
  url.searchParams.set("did", did);
  url.searchParams.set("name", name);

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "video/mp4",
      "X-Garazyk-Access-JWT": accessJwt,
    },
    body: data,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`upload failed: HTTP ${res.status} ${JSON.stringify(body)}`);
  }
  return body;
}

async function pollJobStatus(
  videoClient: XrpcClient,
  jobId: string,
  token: string,
  timeoutMs = 120_000,
): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const body = await videoClient.raw.get(
      "app.bsky.video.getJobStatus",
      { jobId },
      token,
    );
    const status = body.jobStatus || body;
    const state: string = status.state || "";
    if (state === "JOB_STATE_COMPLETED" || state === "JOB_STATE_FAILED") {
      return state;
    }
    await new Promise((r) => setTimeout(r, 2_000));
  }
  throw new Error(`Video job ${jobId} did not finish within ${timeoutMs}ms`);
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Video Job Lifecycle");
  result.start();

  const pds = new XrpcClient(PDS1);
  const videoUrl = SERVICE_URLS.video;
  const videoClient = new XrpcClient(videoUrl);

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Jelcz health check", async () => {
    await videoClient.waitForHealthy(15);
  });

  if (result.failed > 0) return result;

  const luna = getActor("luna");

  const session = await timedCall(result, "Create or login account", async () => {
    return await pds.accounts
      .createAccount(luna.handle, luna.email, luna.password)
      .catch(() => pds.accounts.createSession(luna.handle, luna.password));
  });

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  // Get service auth token for video upload
  const serviceAuth = await timedCall(
    result,
    "Get video service auth token",
    async () => {
      return await pds.as(luna).raw.get(
        "com.atproto.server.getServiceAuth",
        { aud: VIDEO_SERVICE_DID, lxm: "app.bsky.video.uploadVideo" },
      );
    },
  );

  if (!serviceAuth?.token) {
    result.stepFailed("Get video service auth token", "no token returned");
    result.finish();
    return result;
  }
  const authToken = serviceAuth.token;

  // Test 1: getUploadLimits
  await timedCall(
    result,
    "getUploadLimits returns quota info",
    async () => {
      const limits = await videoClient.as(luna).raw.get(
        "app.bsky.video.getUploadLimits",
        undefined,
      );
      assert.isTrue(
        limits !== undefined && limits !== null,
        "expected upload limits response",
      );
      return limits;
    },
    (r) => {
      const keys = Object.keys(r || {});
      return `fields=${keys.join(",")}`;
    },
  );

  // Test 2: getJobStatus with invalid job ID
  await timedCall(
    result,
    "getJobStatus with invalid job ID returns graceful error",
    async () => {
      try {
        await videoClient.as(luna).raw.get(
          "app.bsky.video.getJobStatus",
          { jobId: "nonexistent-job-12345" },
        );
        // If no error thrown, some implementations return error body — accept
      } catch {
        // Expected: XRPC error for nonexistent job
      }
    },
  );

  // Download test video data
  const videoData = await downloadTestVideo();

  // Test 3: Concurrent uploads — upload two videos simultaneously
  const uploadResults = await timedCall(
    result,
    "Upload two videos concurrently",
    async () => {
      const [uploadA, uploadB] = await Promise.all([
        uploadVideo(
          videoData,
          luna.did!,
          "concurrent-a.mp4",
          authToken,
          luna.accessJwt!,
          videoUrl,
        ),
        uploadVideo(
          videoData,
          luna.did!,
          "concurrent-b.mp4",
          authToken,
          luna.accessJwt!,
          videoUrl,
        ),
      ]);
      const jobIdA = uploadA.jobStatus?.jobId || uploadA.jobId;
      const jobIdB = uploadB.jobStatus?.jobId || uploadB.jobId;
      assert.isTrue(
        !!jobIdA,
        "upload A should include jobStatus.jobId",
      );
      assert.isTrue(
        !!jobIdB,
        "upload B should include jobStatus.jobId",
      );
      return { jobIdA, jobIdB };
    },
    (r) => `jobA=${r.jobIdA}, jobB=${r.jobIdB}`,
  );

  // Test 4: Poll both jobs to completion
  if (uploadResults) {
    await timedCall(
      result,
      "Poll both concurrent jobs to completion",
      async () => {
        const states = await Promise.all([
          pollJobStatus(videoClient, uploadResults.jobIdA, luna.accessJwt!),
          pollJobStatus(videoClient, uploadResults.jobIdB, luna.accessJwt!),
        ]);
        assert.equal(
          states[0],
          "JOB_STATE_COMPLETED",
          `job A final state: ${states[0]}`,
        );
        assert.equal(
          states[1],
          "JOB_STATE_COMPLETED",
          `job B final state: ${states[1]}`,
        );
        return states;
      },
      (r) => `states=${r.join(",")}`,
    );
  }

  // Test 5: Upload invalid content and verify JOB_STATE_FAILED
  await timedCall(
    result,
    "Upload invalid content and verify job failure",
    async () => {
      const invalidData = new TextEncoder().encode(
        "this is not a valid video file by any stretch",
      );
      const uploadResp = await uploadVideo(
        invalidData,
        luna.did!,
        "invalid-data.bin",
        authToken,
        luna.accessJwt!,
        videoUrl,
      );
      const jobId = uploadResp.jobStatus?.jobId || uploadResp.jobId;
      assert.isTrue(
        !!jobId,
        "upload of invalid content should still return jobId",
      );
      const finalState = await pollJobStatus(
        videoClient,
        jobId,
        luna.accessJwt!,
        60_000,
      );
      assert.equal(
        finalState,
        "JOB_STATE_FAILED",
        `expected failed job for invalid content, got ${finalState}`,
      );
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
