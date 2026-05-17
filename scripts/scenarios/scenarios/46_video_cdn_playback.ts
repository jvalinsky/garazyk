/**
 * @module scenarios/46_video_cdn_playback
 *
 * Scenario: 46 video cdn playback
 *
 * Behavior:
 * - Executes the 46 video cdn playback scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import {
  APPVIEW_ADMIN_SECRET,
  getCharacter,
  PDS1,
  SERVICE_URLS,
  VIDEO_SERVICE_DID,
} from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

const VIDEO_URL = "http://download.samplelib.com/mp4/sample-5s.mp4";
const VIDEO_CACHE = "/tmp/garazyk-scenario-46-test-video.mp4";

async function readTestVideo(): Promise<Uint8Array> {
  try {
    return await Deno.readFile(VIDEO_CACHE);
  } catch {
    const res = await fetch(VIDEO_URL);
    if (!res.ok) throw new Error(`download failed: HTTP ${res.status}`);
    const data = new Uint8Array(await res.arrayBuffer());
    await Deno.writeFile(VIDEO_CACHE, data);
    return data;
  }
}

async function uploadVideo(data: Uint8Array, did: string, token: string, accessJwt: string) {
  const url = new URL("/xrpc/app.bsky.video.uploadVideo", SERVICE_URLS.video);
  url.searchParams.set("did", did);
  url.searchParams.set("name", "cdn-test.mp4");
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
  if (!res.ok) throw new Error(`upload failed: HTTP ${res.status} ${JSON.stringify(body)}`);
  return body;
}

async function waitForVideoJob(video: XrpcClient, jobId: string, token: string) {
  for (let i = 0; i < 60; i++) {
    const body = await video.raw.xrpcGet("app.bsky.video.getJobStatus", { jobId }, token);
    const status = body.jobStatus || body;
    if (status.state === "JOB_STATE_COMPLETED" || status.state === "JOB_STATE_FAILED") {
      return status;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error("video job did not complete before timeout");
}

async function waitForAppViewHealthy(timeout = 30): Promise<void> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeout * 1000) {
    try {
      const res = await fetch(`${SERVICE_URLS.appview}/admin/ingest/health`, {
        headers: { Authorization: `Bearer ${APPVIEW_ADMIN_SECRET}` },
      });
      if (res.ok) return;
    } catch {
      // Retry until timeout; containers may still be binding ports.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`AppView at ${SERVICE_URLS.appview} not healthy after ${timeout}s`);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Video CDN Playback");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const video = new XrpcClient(SERVICE_URLS.video);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "AppView health check", async () => {
    await waitForAppViewHealthy(30);
  });
  await timedCall(result, "Jelcz health check", async () => {
    await video.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(result, "Create or login account", async () => {
    return await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(() =>
      pds.accounts.createSession(luna.handle, luna.password)
    );
  });

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const serviceAuth = await timedCall(result, "Get video service auth token", async () => {
    return await pds.raw.xrpcGet("com.atproto.server.getServiceAuth", {
      aud: VIDEO_SERVICE_DID,
      lxm: "app.bsky.video.uploadVideo",
    }, luna.accessJwt);
  });

  if (!serviceAuth?.token) {
    result.stepFailed("Get video service auth token", "no token returned");
    result.finish();
    return result;
  }

  const finalJob = await timedCall(result, "Upload MP4 and poll to completion", async () => {
    const upload = await uploadVideo(
      await readTestVideo(),
      luna.did,
      serviceAuth.token,
      luna.accessJwt,
    );
    const jobId = upload.jobStatus?.jobId || upload.jobId;
    assert.isTrue(!!jobId, "upload response should include jobStatus.jobId");
    const status = await waitForVideoJob(video, jobId, luna.accessJwt);
    assert.isTrue(
      status.state === "JOB_STATE_COMPLETED",
      `expected completed job, got ${status.state}`,
    );
    assert.isTrue(!!status.blob?.ref?.$link, "completed job should include blob ref");
    return status;
  }, (status) => `cid=${status.blob.ref.$link}`);

  if (!finalJob?.blob) {
    result.finish();
    return result;
  }

  const created = await timedCall(result, "Publish post with app.bsky.embed.video", async () => {
    return await pds.raw.xrpcPost("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "SkyLab video CDN playback check",
        createdAt: new Date().toISOString(),
        embed: {
          $type: "app.bsky.embed.video",
          video: finalJob.blob,
          alt: "A short test video",
          aspectRatio: finalJob.aspectRatio,
        },
      },
    }, luna.accessJwt);
  }, (body) => `uri=${body.uri}`);

  await timedCall(result, "AppView returns playable video embed", async () => {
    let post = null;
    for (let i = 0; i < 20; i++) {
      const body = await appview.raw.xrpcGet(
        "app.bsky.feed.getPosts",
        { uris: created.uri },
        luna.accessJwt,
      );
      post = body.posts?.[0] || null;
      if (post?.embed?.$type === "app.bsky.embed.video#view") break;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    assert.isTrue(
      post?.embed?.$type === "app.bsky.embed.video#view",
      "post should include video view embed",
    );
    assert.isTrue(
      post.embed.cid === finalJob.blob.ref.$link,
      "view cid should match uploaded blob",
    );
    assert.isTrue(post.embed.playlist?.includes("/watch/"), "view should include HLS playlist URL");
    assert.isTrue(post.embed.thumbnail?.includes("/watch/"), "view should include thumbnail URL");
    return post.embed;
  }, (embed) => `playlist=${embed.playlist}`);

  await timedCall(result, "Direct CDN playlist and thumbnail are readable", async () => {
    const cid = finalJob.blob.ref.$link;
    const playlist = await fetch(`${SERVICE_URLS.video}/watch/${luna.did}/${cid}/playlist.m3u8`);
    assert.isTrue(playlist.ok, `playlist HTTP ${playlist.status}`);
    assert.isTrue(
      (playlist.headers.get("content-type") || "").includes("mpegurl"),
      "playlist should be HLS content",
    );
    const thumbnail = await fetch(`${SERVICE_URLS.video}/watch/${luna.did}/${cid}/thumbnail.jpg`);
    assert.isTrue(thumbnail.ok, `thumbnail HTTP ${thumbnail.status}`);
    assert.isTrue(
      (thumbnail.headers.get("access-control-allow-origin") || "").length > 0,
      "thumbnail should include CORS",
    );
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
