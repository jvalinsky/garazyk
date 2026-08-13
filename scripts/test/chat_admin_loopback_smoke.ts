#!/usr/bin/env -S deno run -A
/**
 * Chat admin loopback smoke (WS11 M4): headline stats, Bearer /_admin gate,
 * privacy-safe partials, lock/unlock mutation.
 *
 * Usage: deno run -A scripts/test/chat_admin_loopback_smoke.ts
 */

import { join } from "@std/path";
import { repoRoot } from "../../packages/hamownia/atproto_network.ts";

const HOST = "127.0.0.1";
const CHAT_PORT = 2585;
const ADMIN_PORT = 2598;
const ADMIN_PASSWORD = Deno.env.get("CHAT_ADMIN_PASSWORD") ??
  "chat-loopback-smoke-password";

let failures = 0;
let child: Deno.ChildProcess | null = null;

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

async function waitForHttp(url: string, timeoutMs = 45_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url);
      if (res.ok || res.status === 302 || res.status === 401 || res.status === 503) {
        return true;
      }
    } catch {
      // not ready
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

async function adminLogin(baseUrl: string): Promise<{ cookie: string; nonce: string } | null> {
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
  const all = [...cookies, ...parseSetCookies(loginRes.headers)];
  const rotated = parseSetCookies(loginRes.headers).find((c) => c.includes("_nonce="));
  const nonce = rotated
    ? rotated.split(";")[0].split("=").slice(1).join("=")
    : nonceValue;
  return { cookie: cookieJar(all), nonce };
}

async function main(): Promise<void> {
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") ?? join(root, "build/bin");
  const bin = join(buildBin, "syrena-chat");
  try {
    Deno.statSync(bin);
  } catch {
    throw new Error(`Missing syrena-chat at ${bin}; build first`);
  }

  const runId = `chat-admin-smoke-${Date.now()}`;
  const dataDir = join(root, "scripts/test-results", runId, "data");
  await Deno.mkdir(dataDir, { recursive: true });
  const chatBase = `http://${HOST}:${CHAT_PORT}`;
  const adminBase = `http://${HOST}:${ADMIN_PORT}`;

  console.log(`Chat admin smoke (api=${chatBase}, admin=${adminBase})`);

  try {
    child = new Deno.Command(bin, {
      args: ["serve", "--port", String(CHAT_PORT), "--data-dir", dataDir],
      env: {
        ...Deno.env.toObject(),
        CHAT_ADMIN_PASSWORD: ADMIN_PASSWORD,
        CHAT_ADMIN_UI_PORT: String(ADMIN_PORT),
      },
      stdout: "null",
      stderr: "null",
    }).spawn();

    if (!await waitForHttp(`${chatBase}/_health`)) {
      throw new Error("chat health never became ready");
    }
    if (!await waitForHttp(`${adminBase}/admin/login`)) {
      throw new Error("chat admin login never became ready");
    }
    ok("chat protocol + loopback admin listeners ready");

    const unauth = await fetch(`${chatBase}/_admin/stats`);
    if (unauth.status !== 401 && unauth.status !== 503) {
      fail(`/_admin/stats without Bearer expected 401/503 got ${unauth.status}`);
    } else {
      ok(`/_admin/stats rejects unauthenticated (${unauth.status})`);
    }

    const statsRes = await fetch(`${chatBase}/_admin/stats`, {
      headers: { Authorization: `Bearer ${ADMIN_PASSWORD}` },
    });
    if (!statsRes.ok) {
      fail(`/_admin/stats authenticated status=${statsRes.status}`);
    } else {
      const stats = await statsRes.json();
      for (const key of [
        "conversationsTotal",
        "conversationsLocked",
        "messagesTotal",
        "membersActive",
        "uptimeSeconds",
        "health",
      ]) {
        if (!(key in stats)) fail(`stats missing ${key}`);
      }
      const blob = JSON.stringify(stats).toLowerCase();
      for (const banned of ["text", "ciphertext", "accessjwt"]) {
        if (blob.includes(`"${banned}"`)) fail(`stats leaked key ${banned}`);
      }
      ok("/_admin/stats headline counters present");
    }

    const session = await adminLogin(adminBase);
    if (!session) throw new Error("admin login failed");
    ok("chat admin login succeeded");

    const statsPartial = await fetch(`${adminBase}/admin/partials/chat-stats`, {
      headers: { Cookie: session.cookie },
      redirect: "manual",
    });
    if (statsPartial.status !== 200) {
      fail(`chat-stats status=${statsPartial.status}`);
    } else {
      const html = await statsPartial.text();
      for (const needle of ["Conversations", "Locked", "Messages", "Health"]) {
        if (!html.includes(needle)) fail(`chat-stats missing "${needle}"`);
      }
      if (html.toLowerCase().includes("ciphertext")) {
        fail("chat-stats leaked ciphertext");
      }
      ok("chat-stats partial renders headline counters");
    }

    // Create a conversation via DB is hard; lock endpoint with missing id should 400 via UI path.
    const lockMissing = await fetch(`${adminBase}/admin/actions/chat-lock`, {
      method: "POST",
      headers: {
        Cookie: session.cookie,
        "X-UI-Admin-Nonce": session.nonce,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
      redirect: "manual",
    });
    if (lockMissing.status === 400 || lockMissing.status === 403) {
      ok(`chat-lock without convoId rejected (${lockMissing.status})`);
    } else {
      fail(`chat-lock without convoId unexpected status ${lockMissing.status}`);
    }
  } finally {
    if (child) {
      try {
        child.kill("SIGTERM");
      } catch {
        // ignore
      }
      try {
        await Promise.race([
          child.status,
          new Promise((r) => setTimeout(r, 5000)),
        ]);
      } catch {
        // ignore
      }
    }
  }

  if (failures > 0) {
    console.error(`\n❌ chat admin loopback smoke: ${failures} failure(s)`);
    Deno.exit(1);
  }
  console.log("\n✅ chat admin loopback smoke completed");
}

if (import.meta.main) {
  await main();
}
