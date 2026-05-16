import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

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

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Video Processing (The Projection Booth)");
  result.start();

  const pdsClient = new XrpcClient(PDS1);
  const videoUrl = SERVICE_URLS.video;
  const videoClient = new XrpcClient(videoUrl);

  await timedCall(result, "PDS health check", async () => { await pdsClient.waitForHealthy(30); });
  await timedCall(result, "Jelcz health check", async () => { await videoClient.waitForHealthy(15); });

  if (result.failed > 0) return result;

  const luna = getCharacter("luna");
  const session = await timedCall(result, "Create account", async () => {
    return await pdsClient.accounts.createAccount(luna.handle, luna.email, luna.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const videoAuthToken = luna.accessJwt;

  await timedCall(result, "Check upload limits", async () => {
    return await videoClient.raw.xrpcGet("app.bsky.video.getUploadLimits", undefined, videoAuthToken);
  });

  const videoData = await downloadTestVideo();
  const uploadResp = await timedCall(result, "Upload MP4 video", async () => {
    return await videoClient.raw.postRaw("app.bsky.video.uploadVideo", videoData, "video/mp4", {
      token: videoAuthToken,
      params: { did: luna.did, name: "test-video.mp4" }
    });
  });

  if (uploadResp) {
    const jobId = uploadResp.jobStatus?.jobId;
    if (!jobId) {
      result.stepFailed("Video job polling", "Upload response missing jobId — cannot poll job status");
    } else {
      let finalState = null;
      let jobResp = null;

      for (let i = 0; i < 60; i++) {
        try {
          jobResp = await videoClient.raw.xrpcGet("app.bsky.video.getJobStatus", { jobId }, videoAuthToken);
          const state = (jobResp.jobStatus || jobResp).state;
          if (state === "JOB_STATE_COMPLETED" || state === "JOB_STATE_FAILED") {
            finalState = state;
            break;
          }
        } catch { /* ignore */ }
        await new Promise(r => setTimeout(r, 2000));
      }

      if (finalState === "JOB_STATE_COMPLETED") {
        result.stepPassed("Video job completed");
      } else {
        result.stepFailed("Video job completed", `Final state: ${finalState}`);
      }
    }
  }

  await timedCall(
    result, "Reject non-video content",
    async () => {
      await videoClient.raw.postRaw("app.bsky.video.uploadVideo", new TextEncoder().encode("not a video"), "video/mp4", {
        token: videoAuthToken,
        params: { did: luna.did, name: "test-invalid.txt" }
      });
    },
    undefined,
    true
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
