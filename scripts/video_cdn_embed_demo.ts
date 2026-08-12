/**
 * Upload a test MP4 to jelcz, then serve a small page that plays the HLS CDN output.
 *
 * Usage:
 *   deno run -A scripts/video_cdn_embed_demo.ts
 *   deno run -A scripts/video_cdn_embed_demo.ts --skip-upload --did did:plc:anonymous --cid bafkrei...
 *
 * Env:
 *   JELCZ_URL   default http://127.0.0.1:2586
 *   DEMO_PORT   default 8765
 */

import { parseArgs } from "@std/cli/parse-args";

const JELCZ_URL = Deno.env.get("JELCZ_URL") ?? "http://127.0.0.1:2586";
const DEMO_PORT = Number(Deno.env.get("DEMO_PORT") ?? "8765");
const SAMPLE_VIDEO = "/tmp/garazyk-demo-video.mp4";
const SAMPLE_SOURCE =
  "https://filesamples.com/samples/video/mp4/sample_640x360.mp4";

interface JobStatus {
  jobId: string;
  did: string;
  state: string;
  progress?: number;
  message?: string;
  blob?: {
    ref?: { $link?: string };
    mimeType?: string;
    size?: number;
  };
}

async function ensureSampleVideo(): Promise<Uint8Array> {
  try {
    return await Deno.readFile(SAMPLE_VIDEO);
  } catch {
    const res = await fetch(SAMPLE_SOURCE);
    if (!res.ok) throw new Error(`download failed: HTTP ${res.status}`);
    const data = new Uint8Array(await res.arrayBuffer());
    await Deno.writeFile(SAMPLE_VIDEO, data);
    return data;
  }
}

async function uploadVideo(data: Uint8Array): Promise<JobStatus> {
  const res = await fetch(`${JELCZ_URL}/xrpc/app.bsky.video.uploadVideo`, {
    method: "POST",
    headers: { "Content-Type": "video/mp4" },
    body: data,
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`upload failed: HTTP ${res.status} ${JSON.stringify(body)}`);
  }
  return body.jobStatus as JobStatus;
}

async function waitForJob(jobId: string): Promise<JobStatus> {
  for (let i = 0; i < 120; i++) {
    const url = new URL(`${JELCZ_URL}/xrpc/app.bsky.video.getJobStatus`);
    url.searchParams.set("jobId", jobId);
    const res = await fetch(url);
    const body = await res.json();
    if (!res.ok) {
      throw new Error(`getJobStatus failed: HTTP ${res.status} ${JSON.stringify(body)}`);
    }
    const status = body.jobStatus as JobStatus;
    if (status.state === "JOB_STATE_COMPLETED" || status.state === "JOB_STATE_FAILED") {
      return status;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("job did not complete before timeout");
}

function cdnUrls(did: string, cid: string) {
  const base = `${JELCZ_URL}/watch/${did}/${cid}`;
  return {
    playlist: `${base}/playlist.m3u8`,
    thumbnail: `${base}/thumbnail.jpg`,
  };
}

function renderPage(opts: {
  did: string;
  cid: string;
  playlist: string;
  thumbnail: string;
  jobId?: string;
}): string {
  const { did, cid, playlist, thumbnail, jobId } = opts;
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Garazyk video CDN demo</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 2rem auto; max-width: 960px; line-height: 1.5; }
    video { width: 100%; max-height: 70vh; background: #111; border-radius: 8px; }
    dl { display: grid; grid-template-columns: 8rem 1fr; gap: 0.25rem 1rem; }
    dt { opacity: 0.7; }
    code { word-break: break-all; }
    img { max-width: 320px; border-radius: 6px; }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js"></script>
</head>
<body>
  <h1>Garazyk video CDN demo</h1>
  <p>Playing HLS from jelcz at <code>${JELCZ_URL}</code>.</p>
  <video id="player" controls poster="${thumbnail}"></video>
  <dl>
    ${jobId ? `<dt>Job</dt><dd><code>${jobId}</code></dd>` : ""}
    <dt>DID</dt><dd><code>${did}</code></dd>
    <dt>Blob CID</dt><dd><code>${cid}</code></dd>
    <dt>Playlist</dt><dd><code>${playlist}</code></dd>
    <dt>Thumbnail</dt><dd><a href="${thumbnail}">${thumbnail}</a></dd>
  </dl>
  <p><img src="${thumbnail}" alt="Video thumbnail" /></p>
  <script>
    const src = ${JSON.stringify(playlist)};
    const video = document.getElementById("player");
    if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = src;
    } else if (window.Hls && Hls.isSupported()) {
      const hls = new Hls();
      hls.loadSource(src);
      hls.attachMedia(video);
    } else {
      video.outerHTML = "<p>HLS playback is not supported in this browser.</p>";
    }
  </script>
</body>
</html>`;
}

async function main() {
  const args = parseArgs(Deno.args, {
    boolean: ["skip-upload", "help"],
    string: ["did", "cid", "job-id"],
    default: { "skip-upload": false, help: false },
  });

  if (args.help) {
    console.log(`Upload + embed demo for jelcz CDN

  deno run -A scripts/video_cdn_embed_demo.ts [--skip-upload] [--did DID] [--cid CID] [--job-id ID]

Env: JELCZ_URL=${JELCZ_URL} DEMO_PORT=${DEMO_PORT}`);
    return;
  }

  let did = args.did;
  let cid = args.cid;
  let jobId = args["job-id"];
  let playlist: string;
  let thumbnail: string;

  if (!args["skip-upload"]) {
    const health = await fetch(`${JELCZ_URL}/_health`);
    if (!health.ok) throw new Error(`jelcz not reachable at ${JELCZ_URL}`);
    console.log(`Uploading sample MP4 to ${JELCZ_URL}...`);
    const data = await ensureSampleVideo();
    const pending = await uploadVideo(data);
    jobId = pending.jobId;
    did = pending.did;
    console.log(`Job ${jobId} (${did}) — waiting for transcode + HLS...`);
    const final = await waitForJob(jobId);
    if (final.state !== "JOB_STATE_COMPLETED") {
      throw new Error(`job failed: ${final.message ?? final.state}`);
    }
    cid = final.blob?.ref?.$link;
    if (!cid) throw new Error("completed job missing blob CID");
    console.log(`Completed: cid=${cid}`);
  } else {
    if (!did || !cid) {
      throw new Error("--skip-upload requires --did and --cid");
    }
  }

  ({ playlist, thumbnail } = cdnUrls(did!, cid!));

  try {
    const playlistProbe = await fetch(playlist);
    if (!playlistProbe.ok) {
      console.warn(
        `Warning: playlist returned HTTP ${playlistProbe.status}. Page will still open; check ffmpeg/HLS output.`,
      );
    } else {
      console.log(`Playlist OK (${playlistProbe.headers.get("content-type")})`);
    }
  } catch (err) {
    console.warn(`Warning: could not reach playlist (${err}). Page will still open.`);
  }

  const html = renderPage({ did: did!, cid: cid!, playlist, thumbnail, jobId });

  const handler = (req: Request): Response => {
    const url = new URL(req.url);
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(html, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }
    return new Response("Not Found", { status: 404 });
  };

  console.log(`Demo page: http://127.0.0.1:${DEMO_PORT}/`);
  console.log(`CDN playlist: ${playlist}`);
  Deno.serve({ port: DEMO_PORT, hostname: "127.0.0.1" }, handler);
}

if (import.meta.main) {
  await main();
}
