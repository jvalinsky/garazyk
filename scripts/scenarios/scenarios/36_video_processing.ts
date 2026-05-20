/**
 * @module scenarios/36_video_processing
 *
 * Scenario: Uploads a video, polls processing, and rejects non-video uploads.
 *
 * Behavior:
 * - Executes the 36 video processing scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { getCharacter, PDS1, SERVICE_URLS, VIDEO_SERVICE_DID } from "../../lib/deno/config.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

const VIDEO_URL = "http://download.samplelib.com/mp4/sample-5s.mp4";
const VIDEO_CACHE = "/tmp/garazyk-scenario-36-test-video.mp4";

async function downloadTestVideo(): Promise<Uint8Array> {
  try {
    const data = await Deno.readFile(VIDEO_CACHE);
    return data;
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
) {
  const url = new URL("/xrpc/app.bsky.video.uploadVideo", SERVICE_URLS.video);
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

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Video Processing (The Projection Booth)");
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

  const serviceAuth = await timedCall(result, "Get video service auth token", async () => {
    return await pdsClient.raw.xrpcGet("com.atproto.server.getServiceAuth", {
      aud: VIDEO_SERVICE_DID,
      lxm: "app.bsky.video.uploadVideo",
    }, luna.accessJwt);
  });

  if (!serviceAuth?.token) {
    result.stepFailed("Get video service auth token", "no token returned");
    result.finish();
    return result;
  }

  const videoAuthToken = serviceAuth.token;

  await timedCall(result, "Check upload limits", async () => {
    return await videoClient.raw.xrpcGet(
      "app.bsky.video.getUploadLimits",
      undefined,
      luna.accessJwt,
    );
  });

  const videoData = await downloadTestVideo();
  const uploadResp = await timedCall(result, "Upload MP4 video", async () => {
    return await uploadVideo(videoData, luna.did, "test-video.mp4", videoAuthToken, luna.accessJwt);
  });

  if (uploadResp) {
    const jobId = uploadResp.jobStatus?.jobId;
    if (!jobId) {
      result.stepFailed(
        "Video job polling",
        "Upload response missing jobId - cannot poll job status",
      );
    } else {
      let finalState = null;
      let jobResp = null;

      for (let i = 0; i < 60; i++) {
        try {
          jobResp = await videoClient.raw.xrpcGet(
            "app.bsky.video.getJobStatus",
            { jobId },
            luna.accessJwt,
          );
          const state = (jobResp.jobStatus || jobResp).state;
          if (state === "JOB_STATE_COMPLETED" || state === "JOB_STATE_FAILED") {
            finalState = state;
            break;
          }
        } catch { /* ignore */ }
        await new Promise((r) => setTimeout(r, 2000));
      }

      if (finalState === "JOB_STATE_COMPLETED") {
        result.stepPassed("Video job completed");
      } else {
        result.stepFailed("Video job completed", `Final state: ${finalState}`);
      }
    }
  }

  await timedCall(
    result,
    "Reject non-video content",
    async () => {
      await uploadVideo(
        new TextEncoder().encode("not a video"),
        luna.did,
        "test-invalid.txt",
        videoAuthToken,
        luna.accessJwt,
      );
    },
    undefined,
    true,
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
