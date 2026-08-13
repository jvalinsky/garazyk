/**
 * Focused live-browser visual + overview smoke for the embedded PDS Admin UI.
 *
 * Boots `build/bin/kaszlak serve` with a temp data dir and ephemeral ports,
 * then checks:
 *   1. Login page layout (no horizontal overflow at 640px)
 *   2. Minimum 44px touch targets on password + submit
 *   3. Focus-visible indicator on the autofocused password field
 *   4. prefers-reduced-motion zeroes CSS transitions
 *   5. Operator login + `/admin/partials/pds-stats` overview (health/sessions)
 *
 * Usage:
 *   deno run -A npm:playwright@1.52.0 install chromium   # once
 *   deno run -A scripts/admin_ui_visual_smoke_test.ts
 */

import { chromium } from "npm:playwright@1.52.0";

const HOST = "127.0.0.1";
const PASSWORD = "admin-ui-visual-smoke-password";

async function waitForLogin(baseUrl: string): Promise<void> {
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    try {
      if ((await fetch(`${baseUrl}/admin/login`)).ok) return;
    } catch {
      // The local server has not bound its port yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Admin UI did not become ready: ${baseUrl}/admin/login`);
}

async function reservePort(): Promise<number> {
  const listener = Deno.listen({ hostname: HOST, port: 0 });
  const port = (listener.addr as Deno.NetAddr).port;
  listener.close();
  return port;
}

async function main(): Promise<void> {
  const root = Deno.cwd();
  const binary = `${root}/build/bin/kaszlak`;
  const assets = `${root}/build/bin/Assets`;
  try {
    await Deno.stat(binary);
  } catch {
    throw new Error(`Missing ${binary}; build kaszlak first`);
  }

  const protocolPort = await reservePort();
  const uiPort = await reservePort();
  const baseUrl = `http://${HOST}:${uiPort}`;
  const dataDir = await Deno.makeTempDir({ prefix: "pds-admin-visual-" });
  const logPath = `${dataDir}/kaszlak.stderr.log`;
  const logFile = await Deno.open(logPath, {
    create: true,
    write: true,
    truncate: true,
  });

  const server = new Deno.Command(binary, {
    args: [
      "serve",
      "--foreground",
      "--port",
      String(protocolPort),
      "--data-dir",
      dataDir,
    ],
    env: {
      ...Deno.env.toObject(),
      PDS_ADMIN_PASSWORD: PASSWORD,
      PDS_ADMIN_UI_HOST: HOST,
      PDS_ADMIN_UI_PORT: String(uiPort),
      PDS_ADMIN_UI_PUBLIC_URL: `${baseUrl}/admin`,
      GARAZYK_ADMIN_UI_ASSETS_DIR: assets,
      PDS_USE_KEYCHAIN: "false",
    },
    stdout: "null",
    stderr: logFile.rid,
  }).spawn();

  let browser: Awaited<ReturnType<typeof chromium.launch>> | undefined;
  try {
    await waitForLogin(baseUrl);
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({
      viewport: { width: 640, height: 800 },
    });
    await page.goto(`${baseUrl}/admin/login`, {
      waitUntil: "domcontentloaded",
    });

    const horizontalOverflow = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.documentElement.scrollWidth >
        doc.documentElement.clientWidth + 1;
    });
    if (horizontalOverflow) {
      throw new Error("Admin UI has page-level horizontal overflow at 640px");
    }

    const undersizedTargets = await page.locator(
      "#password, form#login-form button[type=submit]",
    ).evaluateAll((elements) =>
      elements.map((element) => {
        const rect = element.getBoundingClientRect();
        return { width: rect.width, height: rect.height };
      }).filter(({ width, height }) => width < 44 || height < 44)
    );
    if (undersizedTargets.length > 0) {
      throw new Error(
        `Admin UI has undersized touch targets: ${
          JSON.stringify(undersizedTargets)
        }`,
      );
    }

    await page.locator("#password").focus();
    const focus = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const win = globalThis as any;
      const active = win.document.activeElement;
      const style = active ? win.getComputedStyle(active) : null;
      return {
        id: active?.id ?? null,
        focusVisible: active?.matches(":focus-visible") ?? false,
        outlineStyle: style?.outlineStyle ?? "none",
        outlineWidth: parseFloat(style?.outlineWidth ?? "0"),
        boxShadow: style?.boxShadow ?? "none",
      };
    });
    if (
      focus.id !== "password" || !focus.focusVisible ||
      ((focus.outlineStyle === "none" || focus.outlineWidth < 2) &&
        focus.boxShadow === "none")
    ) {
      throw new Error(
        `Admin UI password focus indicator is insufficient: ${
          JSON.stringify(focus)
        }`,
      );
    }

    await page.emulateMedia({ reducedMotion: "reduce" });
    const reducedDuration = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const win = globalThis as any;
      const probe = win.document.createElement("div");
      probe.style.transition = "opacity 300ms";
      win.document.body.appendChild(probe);
      const duration = parseFloat(
        win.getComputedStyle(probe).transitionDuration,
      );
      probe.remove();
      return duration;
    });
    if (reducedDuration > 0.0001) {
      throw new Error(
        `Reduced-motion transition duration is ${reducedDuration}s`,
      );
    }

    // Login and assert the cheap overview snapshot partial is wired.
    await page.fill("#password", PASSWORD);
    await Promise.all([
      page.waitForURL(`${baseUrl}/admin`, { timeout: 15_000 }),
      page.click("form#login-form button[type=submit]"),
    ]);

    const statsRes = await page.request.get(
      `${baseUrl}/admin/partials/pds-stats`,
    );
    if (!statsRes.ok()) {
      throw new Error(
        `pds-stats partial failed: HTTP ${statsRes.status()}`,
      );
    }
    const statsHtml = await statsRes.text();
    for (const needle of ["Health", "Accounts", "Active sessions"]) {
      if (!statsHtml.includes(needle)) {
        throw new Error(
          `pds-stats missing "${needle}": ${statsHtml.slice(0, 500)}`,
        );
      }
    }
    // Snapshot wiring adds these when the embedded overview is attached.
    for (const needle of ["Sequencer head", "Actor DB pool", "Service DB"]) {
      if (!statsHtml.includes(needle)) {
        throw new Error(
          `pds-stats missing snapshot field "${needle}": ${
            statsHtml.slice(0, 500)
          }`,
        );
      }
    }

    // 200% zoom: CSS zoom keeps layout metrics while stressing overflow.
    await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      (globalThis as any).document.documentElement.style.zoom = "200%";
    });
    await page.waitForTimeout(200);
    const zoomOverflow = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.documentElement.scrollWidth >
        doc.documentElement.clientWidth + 2;
    });
    if (zoomOverflow) {
      throw new Error("Admin UI has page-level horizontal overflow at 200% zoom");
    }
    await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      (globalThis as any).document.documentElement.style.zoom = "";
    });

    console.log("✅ Admin UI visual smoke completed");
  } catch (error) {
    try {
      const logText = await Deno.readTextFile(logPath);
      if (logText.trim().length > 0) {
        console.error("--- kaszlak stderr ---");
        console.error(logText.slice(-4000));
      }
    } catch {
      // ignore missing log
    }
    throw error;
  } finally {
    await browser?.close();
    try {
      server.kill("SIGTERM");
    } catch {
      // The server has already exited.
    }
    try {
      await server.status;
    } catch {
      // best-effort
    }
    try {
      logFile.close();
    } catch {
      // already closed via writable transfer
    }
    try {
      await Deno.remove(dataDir, { recursive: true });
    } catch {
      // best-effort cleanup
    }
  }
}

if (import.meta.main) {
  await main().catch((error) => {
    console.error(error);
    Deno.exit(1);
  });
}
