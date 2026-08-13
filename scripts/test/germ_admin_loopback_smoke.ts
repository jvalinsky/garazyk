#!/usr/bin/env -S deno run -A
/**
 * Germ admin loopback + live metrics partial smoke (WS11 M4 remainder).
 *
 * Starts a local `germ` binary with the embedded admin UI on :2599, logs in,
 * polls the HTMX metrics partials, and asserts aggregate-only live counters
 * render (not the "Unavailable" fallback). Also checks `/_admin/metrics`
 * JSON never contains forbidden privacy keys.
 *
 * Usage: deno run -A scripts/test/germ_admin_loopback_smoke.ts
 */

import { join } from "@std/path";
import { repoRoot } from "../../packages/hamownia/atproto_network.ts";

const HOST = "127.0.0.1";
const GERM_PORT = 8082;
const ADMIN_PORT = 2599;
const ADMIN_PASSWORD = Deno.env.get("GERM_ADMIN_PASSWORD") ??
  "germ-loopback-smoke-password";
const POLL_ROUNDS = 8;
const POLL_INTERVAL_MS = 400;

const FORBIDDEN_METRIC_KEYS = [
  "ciphertext",
  "address",
  "mailbox",
  "agent",
  "token",
  "did",
  "accessJwt",
  "refreshJwt",
];

let failures = 0;
let germChild: Deno.ChildProcess | null = null;

function ok(msg: string): void {
  console.log(`[OK] ${msg}`);
}

function fail(msg: string): void {
  failures++;
  console.error(`[FAIL] ${msg}`);
}

function cookieJar(cookies: string[]): string {
  return cookies.map((c) => c.split(";")[0]).join("; ");
}

function parseSetCookies(headers: Headers): string[] {
  const raw = headers.getSetCookie?.() ?? [];
  if (raw.length > 0) return raw;
  const single = headers.get("set-cookie");
  return single ? [single] : [];
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
  return cookieJar([...cookies, ...parseSetCookies(loginRes.headers)]);
}

function assertNoForbiddenKeys(value: unknown, path = ""): void {
  if (value === null || value === undefined) return;
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertNoForbiddenKeys(v, `${path}[${i}]`));
    return;
  }
  if (typeof value !== "object") return;
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    const lower = k.toLowerCase();
    for (const banned of FORBIDDEN_METRIC_KEYS) {
      if (lower.includes(banned)) {
        fail(`forbidden metrics key at ${path}.${k}`);
      }
    }
    assertNoForbiddenKeys(v, path ? `${path}.${k}` : k);
  }
}

async function checkMetricsJson(germBase: string): Promise<void> {
  const res = await fetch(`${germBase}/_admin/metrics`);
  if (!res.ok) {
    fail(`GET /_admin/metrics status=${res.status}`);
    return;
  }
  const json = await res.json();
  assertNoForbiddenKeys(json);
  for (const key of [
    "pendingMessages",
    "expiredCount",
    "ephemeralCount",
    "rendezvousCount",
  ]) {
    if (!(key in json)) fail(`metrics missing aggregate key ${key}`);
  }
  ok("/_admin/metrics aggregate counters present and privacy-safe");
}

async function pollPartials(adminBase: string, cookie: string): Promise<void> {
  const checks: Array<{ path: string; mustInclude: string[]; mustNot: string[] }> =
    [
      {
        path: "/admin/partials/germ-health",
        mustInclude: ["Pending messages", "Expired awaiting cleanup"],
        mustNot: ["Unavailable"],
      },
      {
        path: "/admin/partials/germ-flow",
        mustInclude: ["Ephemeral addresses", "Rendezvous addresses"],
        mustNot: ["Metrics unavailable"],
      },
      {
        path: "/admin/partials/germ-storage",
        mustInclude: ["Database size", "Pending messages"],
        mustNot: ["Metrics unavailable"],
      },
    ];

  for (let round = 0; round < POLL_ROUNDS; round++) {
    for (const check of checks) {
      const res = await fetch(`${adminBase}${check.path}`, {
        headers: { Cookie: cookie },
        redirect: "manual",
      });
      if (res.status !== 200) {
        fail(`${check.path} round ${round + 1} status=${res.status}`);
        continue;
      }
      const body = await res.text();
      for (const needle of check.mustInclude) {
        if (!body.includes(needle)) {
          fail(`${check.path} round ${round + 1} missing "${needle}"`);
        }
      }
      for (const banned of check.mustNot) {
        if (body.includes(banned)) {
          fail(`${check.path} round ${round + 1} unexpectedly contains "${banned}"`);
        }
      }
      for (const banned of ["ciphertext", "accessJwt", "did:plc:"]) {
        if (body.toLowerCase().includes(banned.toLowerCase())) {
          fail(`${check.path} round ${round + 1} leaked "${banned}"`);
        }
      }
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  ok(`${POLL_ROUNDS} polling rounds on germ health/flow/storage partials`);
}

async function startGerm(bin: string, dataDir: string): Promise<void> {
  await Deno.mkdir(dataDir, { recursive: true });
  germChild = new Deno.Command(bin, {
    args: ["serve", "--port", String(GERM_PORT), "--data-dir", dataDir],
    env: {
      ...Deno.env.toObject(),
      GERM_ADMIN_PASSWORD: ADMIN_PASSWORD,
    },
    stdout: "null",
    stderr: "null",
  }).spawn();
}

async function stopGerm(): Promise<void> {
  if (!germChild) return;
  try {
    germChild.kill("SIGTERM");
  } catch {
    // already exited
  }
  try {
    await Promise.race([
      germChild.status,
      new Promise((r) => setTimeout(r, 5000)),
    ]);
  } catch {
    // ignore
  }
  germChild = null;
}

async function main(): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") ?? join(root, "build/bin");
  const germBin = join(buildBin, "germ");
  try {
    Deno.statSync(germBin);
  } catch {
    throw new Error(`Missing germ at ${germBin}; build first`);
  }

  const runId = `germ-admin-smoke-${Date.now()}`;
  const dataDir = join(root, "scripts/test-results", runId, "data");
  const germBase = `http://${HOST}:${GERM_PORT}`;
  const adminBase = `http://${HOST}:${ADMIN_PORT}`;

  console.log(`Germ admin smoke (api=${germBase}, admin=${adminBase})`);

  try {
    await startGerm(germBin, dataDir);
    if (!await waitForHttp(`${germBase}/_health`)) {
      throw new Error("germ health never became ready");
    }
    if (!await waitForHttp(`${adminBase}/admin/login`)) {
      throw new Error("germ admin login never became ready");
    }
    ok("germ protocol + loopback admin listeners ready");

    await checkMetricsJson(germBase);

    const cookie = await adminLogin(adminBase);
    if (!cookie) throw new Error("admin login failed");
    ok("germ admin login succeeded");

    const overview = await fetch(`${adminBase}/admin/partials/germ`, {
      headers: { Cookie: cookie },
      redirect: "manual",
    });
    if (overview.status !== 200) {
      fail(`GET /admin/partials/germ status=${overview.status}`);
    } else {
      const html = await overview.text();
      if (!html.includes("Mailbox flow") || !html.includes("germ-flow")) {
        fail("overview missing live metrics shell markers");
      } else {
        ok("overview renders HTMX metrics shell");
      }
    }

    await pollPartials(adminBase, cookie);
  } finally {
    await stopGerm();
  }

  if (failures > 0) {
    console.error(`\n❌ germ admin loopback smoke: ${failures} failure(s)`);
    Deno.exit(1);
  }
  console.log("\n✅ germ admin loopback smoke completed");
}

if (import.meta.main) {
  await main();
}
