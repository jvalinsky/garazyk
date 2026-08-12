#!/usr/bin/env -S deno run -A
/**
 * Relay admin loopback + firehose-under-polling smoke (WS11 M4).
 *
 * Starts a minimal PLC/PDS/relay binary topology with zuk's embedded admin
 * listener on loopback, keeps a subscribeRepos consumer open, hammers the
 * HTMX partial endpoints while posts flow through the relay, and verifies
 * session-scoped responses stay healthy.
 *
 * Usage: deno run -A scripts/test/relay_admin_loopback_smoke.ts
 */

import { join } from "@std/path";
import {
  initRunDir,
  repoRoot,
  stopLocalNetwork,
} from "../../packages/hamownia/atproto_network.ts";
import {
  startBinaryServices,
  stopBinaryServices,
} from "../../packages/hamownia/binary_services.ts";
import { FirehoseClient } from "../lib/deno/firehose.ts";
import { createAccountOrLogin } from "../lib/deno/runner.ts";
import { XrpcClient } from "../lib/deno/client.ts";

const HOST = "127.0.0.1";
const ADMIN_PASSWORD = Deno.env.get("RELAY_ADMIN_PASSWORD") ??
  "relay-loopback-smoke-password";
const POLL_ROUNDS = 24;
const POLL_INTERVAL_MS = 500;

let failures = 0;

function ok(msg: string): void {
  console.log(`[OK] ${msg}`);
}

function fail(msg: string): void {
  failures++;
  console.error(`[FAIL] ${msg}`);
}

function toWebSocketUrl(httpUrl: string): string {
  return httpUrl.replace(/^http:/, "ws:").replace(/^https:/, "wss:");
}

async function reservePort(): Promise<number> {
  const listener = Deno.listen({ hostname: HOST, port: 0 });
  const port = (listener.addr as Deno.NetAddr).port;
  listener.close();
  return port;
}

function parseSetCookies(headers: Headers): string[] {
  const raw = headers.getSetCookie?.() ?? [];
  if (raw.length > 0) return raw;
  const single = headers.get("set-cookie");
  return single ? [single] : [];
}

function cookieJar(cookies: string[]): string {
  return cookies.map((c) => c.split(";")[0]).join("; ");
}

async function waitForHttp(url: string, timeoutMs = 30_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url);
      if (res.ok || res.status === 302 || res.status === 401) return true;
    } catch {
      // not ready
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

async function adminLogin(baseUrl: string): Promise<string | null> {
  const loginPage = await fetch(`${baseUrl}/admin/login`);
  if (!loginPage.ok) {
    fail(`GET /admin/login status=${loginPage.status}`);
    return null;
  }
  const cookies = parseSetCookies(loginPage.headers);
  const csrfCookie = cookies.find((c) => c.includes("_nonce="));
  if (!csrfCookie) {
    fail("missing CSRF nonce cookie on login page");
    return null;
  }
  const nonceValue = csrfCookie.split(";")[0].split("=").slice(1).join("=");
  const loginRes = await fetch(`${baseUrl}/admin/login`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Cookie: cookieJar(cookies),
      "X-UI-Admin-Nonce": nonceValue,
    },
    body: JSON.stringify({ password: ADMIN_PASSWORD }),
  });
  if (!loginRes.ok) {
    fail(`POST /admin/login status=${loginRes.status}`);
    return null;
  }
  const sessionCookies = [...cookies, ...parseSetCookies(loginRes.headers)];
  return cookieJar(sessionCookies);
}

async function pollPartials(baseUrl: string, cookie: string): Promise<void> {
  const paths = ["/admin/partials/relay-metrics", "/admin/partials/relay-sources"];
  for (let round = 0; round < POLL_ROUNDS; round++) {
    for (const path of paths) {
      const res = await fetch(`${baseUrl}${path}`, {
        headers: { Cookie: cookie },
        redirect: "manual",
      });
      if (res.status !== 200) {
        fail(`${path} round ${round + 1} status=${res.status}`);
        continue;
      }
      const body = await res.text();
      if (path.includes("relay-metrics") && !body.includes("Sequence")) {
        fail(`${path} round ${round + 1} missing Sequence marker`);
      }
      if (path.includes("relay-sources") && !body.includes("Source")) {
        fail(`${path} round ${round + 1} missing sources table header`);
      }
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  ok(`${POLL_ROUNDS} polling rounds on metrics + sources partials`);
}

async function generateRepoTraffic(pdsUrl: string): Promise<void> {
  const pds = new XrpcClient(pdsUrl);
  await pds.waitForHealthy(30);
  const handle = `relay-smoke-${Date.now()}.test`;
  const session = await createAccountOrLogin(pds, {
    handle,
    password: "relay-smoke-hunter2-pass",
    email: `${handle}@example.test`,
  });
  if (!session?.accessJwt) {
    fail("could not create smoke account");
    return;
  }
  for (let i = 0; i < 6; i++) {
    await pds.as(session).repo.createRecord({
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: `relay smoke ${i} ${Date.now()}`,
        createdAt: new Date().toISOString(),
      },
    });
    await new Promise((r) => setTimeout(r, 200));
  }
  ok("created repo posts to drive firehose traffic");
}

async function main(): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") ?? join(root, "build/bin");
  for (const bin of ["campagnola", "kaszlak", "zuk"]) {
    try {
      Deno.statSync(join(buildBin, bin));
    } catch {
      throw new Error(`Missing ${bin} at ${buildBin}/${bin}; build first`);
    }
  }

  const adminPort = await reservePort();
  const adminBase = `http://${HOST}:${adminPort}`;
  const relayPort = 2584;
  const relayHttp = `http://${HOST}:${relayPort}`;
  const pdsHttp = `http://${HOST}:2583`;
  const runId = `relay-admin-smoke-${Date.now()}`;
  const ctx = initRunDir(runId);

  console.log(`Relay admin smoke (admin=${adminBase}, relay=${relayHttp})`);

  try {
    await startBinaryServices(ctx, {
      services: ["plc", "pds", "relay"],
      isolation: "legacy-fixed",
      env: {
        relay: {
          RELAY_ADMIN_PASSWORD: ADMIN_PASSWORD,
          GARAZYK_RELAY_ADMIN_UI_HOST: HOST,
          GARAZYK_RELAY_ADMIN_UI_PORT: String(adminPort),
        },
      },
      args: {
        relay: [
          "serve",
          "--port",
          String(relayPort),
          "--upstream",
          `${toWebSocketUrl(pdsHttp)}/xrpc/com.atproto.sync.subscribeRepos`,
          "--data-dir",
          join(ctx.runDir, "data/relay"),
          "--admin-ui-host",
          HOST,
          "--admin-ui-port",
          String(adminPort),
        ],
      },
      servicePorts: { plc: 2582, pds: 2583, relay: relayPort },
      serviceUrls: {
        plc: `http://${HOST}:2582`,
        pds: pdsHttp,
        relay: relayHttp,
      },
    });

    if (!await waitForHttp(`${relayHttp}/api/relay/health`)) {
      throw new Error("relay health never became ready");
    }
    if (!await waitForHttp(`${adminBase}/admin/login`)) {
      throw new Error("relay admin login never became ready");
    }
    ok("relay protocol + loopback admin listeners ready");

    const cookie = await adminLogin(adminBase);
    if (!cookie) throw new Error("admin login failed");

    const firehose = new FirehoseClient(
      relayHttp.replace(/^http/, "ws"),
    );
    let firehoseEvents = 0;
    const firehoseAbort = new AbortController();
    const firehoseDone = firehose.subscribe((event) => {
      if (event.type === "#commit") firehoseEvents++;
    }, 120, undefined, firehoseAbort.signal);

    const trafficDone = generateRepoTraffic(pdsHttp);
    const pollDone = pollPartials(adminBase, cookie);
    await Promise.all([trafficDone, pollDone]);
    firehoseAbort.abort();
    await firehoseDone;

    if (firehoseEvents < 1) {
      fail(`expected firehose commits during polling, saw ${firehoseEvents}`);
    } else {
      ok(`firehose delivered ${firehoseEvents} commit events during admin polling`);
    }
  } finally {
    await stopBinaryServices(ctx, ["relay", "pds", "plc"]);
    await stopLocalNetwork({ runId });
  }

  if (failures > 0) {
    console.error(`\n❌ relay admin loopback smoke: ${failures} failure(s)`);
    Deno.exit(1);
  }
  console.log("\n✅ relay admin loopback smoke completed");
}

if (import.meta.main) {
  await main();
}
