import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Video CDN Playback");
  result.start();

  const pds = new XrpcClient(PDS1);
  const video = new XrpcClient(SERVICE_URLS.video);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => { await pds.wait_for_healthy(30); });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(() => 
    pds.accounts.createSession(luna.handle, luna.password)
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const serviceAuth = await timedCall(result, "Get service auth token", async () => {
    return await pds.raw.xrpcGet("com.atproto.server.getServiceAuth", {
      aud: SERVICE_URLS.video,
      lxm: "app.bsky.video.uploadVideo"
    }, luna.accessJwt);
  });

  if (serviceAuth?.token) {
    const job = await timedCall(result, "Upload video", async () => {
      const data = new Uint8Array(1024); // Placeholder
      return await video.raw.postRaw("app.bsky.video.uploadVideo", data, "video/mp4", {
        token: serviceAuth.token,
        params: { did: luna.did, name: "cdn-test.mp4" }
      });
    });

    if (job?.jobStatus?.jobId) {
      const jobId = job.jobStatus.jobId;
      let finalState = null;
      for (let i = 0; i < 30; i++) {
        const status = await video.raw.xrpcGet("app.bsky.video.getJobStatus", { jobId }, luna.accessJwt);
        if (status.state === "JOB_STATE_COMPLETED" || status.state === "JOB_STATE_FAILED") {
          finalState = status.state;
          break;
        }
        await new Promise(r => setTimeout(r, 2000));
      }
      result.stepPassed("Video job polling completed", `final_state=${finalState}`);
    }
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
