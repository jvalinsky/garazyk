#!/usr/bin/env -S deno run -A
/**
 * Browser HLS soak against jelcz peer demo (Chromium + CDP).
 *
 * Drives peer+play via in-page fetch/HLS.js (does not rely on catalog click),
 * then samples stats for SOAK_SECS (default 120).
 */

const UI = Deno.env.get("JELCZ_UI") ?? "http://127.0.0.1:2596";
const SOAK_SECS = Number(Deno.env.get("SOAK_SECS") ?? "120");
const CHROMIUM = Deno.env.get("CHROMIUM") ??
  "/Applications/Chromium.app/Contents/MacOS/Chromium";
const DEBUG_PORT = Number(Deno.env.get("CDP_PORT") ?? "9222");
const VOD_URI = Deno.env.get("VOD_URI") ??
  "at://did:plc:rbvrr34edl5ddpuwcubjiost/place.stream.video/3mipbxjavnf2m";

type Stats = {
  peeredObjectCount?: number;
  proxyServeCount?: number;
  proxiedByteCount?: number;
  localServeCount?: number;
  recentServes?: Array<{ mode?: string; bytes?: number; cid?: string }>;
};

function log(msg: string) {
  console.log(`[hls-soak] ${msg}`);
}

async function waitPort(port: number, ms = 20000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return await res.json();
    } catch {
      // retry
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`CDP not up on :${port}`);
}

async function cdpSend(
  ws: WebSocket,
  id: number,
  method: string,
  params: Record<string, unknown> = {},
): Promise<unknown> {
  return await new Promise((resolve, reject) => {
    const onMsg = (ev: MessageEvent) => {
      try {
        const msg = JSON.parse(String(ev.data));
        if (msg.id !== id) return;
        ws.removeEventListener("message", onMsg);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      } catch (err) {
        ws.removeEventListener("message", onMsg);
        reject(err);
      }
    };
    ws.addEventListener("message", onMsg);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function fetchStats(): Promise<Stats> {
  const res = await fetch(`${UI}/demo/streamplace/api/stats`);
  if (!res.ok) throw new Error(`stats HTTP ${res.status}`);
  return await res.json();
}

async function main() {
  const tmp = await Deno.makeTempDir({ prefix: "jelcz-hls-soak-" });
  const chromium = new Deno.Command(CHROMIUM, {
    args: [
      `--remote-debugging-port=${DEBUG_PORT}`,
      "--headless=new",
      "--disable-gpu",
      "--autoplay-policy=no-user-gesture-required",
      "--no-first-run",
      "--no-default-browser-check",
      `--user-data-dir=${tmp}`,
      `${UI}/demo/streamplace`,
    ],
    stdout: "null",
    stderr: "null",
  }).spawn();

  try {
    await waitPort(DEBUG_PORT);
    const tabs = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/list`))
      .json() as Array<{ type: string; webSocketDebuggerUrl: string; url: string }>;
    const page = tabs.find((t) => t.type === "page" && t.url.includes("demo/streamplace")) ??
      tabs.find((t) => t.type === "page") ??
      tabs[0];
    if (!page?.webSocketDebuggerUrl) throw new Error("no CDP page target");

    const ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise<void>((resolve, reject) => {
      ws.onopen = () => resolve();
      ws.onerror = () => reject(new Error("CDP websocket failed"));
    });

    let nextId = 1;
    await cdpSend(ws, nextId++, "Runtime.enable");
    await cdpSend(ws, nextId++, "Page.enable");

    await cdpSend(ws, nextId++, "Runtime.evaluate", {
      expression: `(() => new Promise((resolve, reject) => {
        const t0 = Date.now();
        const tick = () => {
          if (window.Hls) return resolve(true);
          if (Date.now() - t0 > 30000) return reject(new Error("Hls.js not loaded"));
          setTimeout(tick, 200);
        };
        tick();
      }))()`,
      awaitPromise: true,
    });
    log("Hls.js ready");

    const before = await fetchStats();
    log(
      `before proxyServe=${before.proxyServeCount ?? 0} proxiedBytes=${before.proxiedByteCount ?? 0} local=${before.localServeCount ?? 0}`,
    );

    const peerPlay = await cdpSend(ws, nextId++, "Runtime.evaluate", {
      expression: `(() => new Promise(async (resolve, reject) => {
        try {
          const uri = ${JSON.stringify(VOD_URI)};
          const res = await fetch("/demo/streamplace/api/peer", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ uri, kind: "vod" }),
          });
          const session = await res.json();
          if (!res.ok || !session.localPlaylistURL) {
            throw new Error(session.message || session.error || ("peer HTTP " + res.status));
          }
          const video = document.getElementById("video");
          if (!video) throw new Error("missing video element");
          if (window.__soakHls) { try { window.__soakHls.destroy(); } catch (_) {} }
          const hls = new Hls({ enableWorker: true });
          window.__soakHls = hls;
          hls.loadSource(session.localPlaylistURL);
          hls.attachMedia(video);
          await new Promise((res2, rej2) => {
            const t = setTimeout(() => rej2(new Error("manifest timeout")), 60000);
            hls.on(Hls.Events.MANIFEST_PARSED, async () => {
              clearTimeout(t);
              try { await video.play(); } catch (_) {}
              res2(true);
            });
            hls.on(Hls.Events.ERROR, (_, data) => {
              if (data.fatal) {
                clearTimeout(t);
                rej2(new Error("HLS " + data.type + "/" + data.details));
              }
            });
          });
          resolve({
            playlist: session.localPlaylistURL,
            objects: (session.objects || []).map((o) => ({ status: o.status, size: o.size })),
            readyState: video.readyState,
            currentTime: video.currentTime,
          });
        } catch (err) {
          reject(err);
        }
      }))()`,
      awaitPromise: true,
    });
    log(`peer+play: ${JSON.stringify(peerPlay)}`);

    const samples: Array<Record<string, unknown>> = [];
    const tEnd = Date.now() + SOAK_SECS * 1000;
    while (Date.now() < tEnd) {
      const st = await fetchStats();
      const playback = await cdpSend(ws, nextId++, "Runtime.evaluate", {
        expression: `(() => {
          const v = document.getElementById("video");
          return v ? {
            paused: v.paused,
            ended: v.ended,
            readyState: v.readyState,
            currentTime: Number(v.currentTime.toFixed(2)),
            buffered: v.buffered.length ? Number(v.buffered.end(v.buffered.length - 1).toFixed(2)) : 0,
          } : null;
        })()`,
        returnByValue: true,
      }) as { result?: { value?: unknown } };

      const modes = (st.recentServes ?? []).reduce<Record<string, number>>((acc, e) => {
        const m = e.mode || "?";
        acc[m] = (acc[m] || 0) + 1;
        return acc;
      }, {});
      const row = {
        t: new Date().toISOString(),
        proxyServeCount: st.proxyServeCount,
        proxiedByteCount: st.proxiedByteCount,
        localServeCount: st.localServeCount,
        peeredObjectCount: st.peeredObjectCount,
        modes,
        playback: playback?.result?.value ?? playback,
      };
      samples.push(row);
      const elapsed = Math.round((SOAK_SECS * 1000 - (tEnd - Date.now())) / 1000);
      log(
        `t+${elapsed}s proxy=${st.proxyServeCount} bytes=${st.proxiedByteCount} local=${st.localServeCount} play=${JSON.stringify(row.playback)}`,
      );
      await new Promise((r) => setTimeout(r, 5000));
    }

    const after = await fetchStats();
    const deltaProxy = (after.proxyServeCount ?? 0) - (before.proxyServeCount ?? 0);
    const deltaBytes = (after.proxiedByteCount ?? 0) - (before.proxiedByteCount ?? 0);
    const deltaLocal = (after.localServeCount ?? 0) - (before.localServeCount ?? 0);
    const lastPlay = samples.at(-1)?.playback as
      | { currentTime?: number; readyState?: number; paused?: boolean; buffered?: number }
      | undefined;

    const ok = deltaProxy > 0 && deltaBytes > 0 &&
      (lastPlay?.readyState ?? 0) >= 2 &&
      ((lastPlay?.currentTime ?? 0) > 1 || (lastPlay?.buffered ?? 0) > 1);

    console.log(JSON.stringify({
      ok,
      ui: UI,
      soakSecs: SOAK_SECS,
      vodUri: VOD_URI,
      deltaProxyServeCount: deltaProxy,
      deltaProxiedBytes: deltaBytes,
      deltaLocalServeCount: deltaLocal,
      lastPlayback: lastPlay,
      samples: samples.length,
    }, null, 2));

    ws.close();
    if (!ok) Deno.exit(1);
  } finally {
    try {
      chromium.kill("SIGTERM");
    } catch {
      // ignore
    }
    try {
      await Deno.remove(tmp, { recursive: true });
    } catch {
      // ignore
    }
  }
}

main().catch((err) => {
  console.error(err);
  Deno.exit(1);
});
