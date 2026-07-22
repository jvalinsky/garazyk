/**
 * Focused live-browser visual accessibility smoke for the standalone Admin UI.
 *
 * Usage: deno run -A scripts/admin_ui_visual_smoke_test.ts
 */

import { chromium } from "npm:playwright@1.52.0";

const HOST = "127.0.0.1";
const PASSWORD = "admin-ui-visual-smoke-password";

async function waitForLogin(baseUrl: string): Promise<void> {
  const deadline = Date.now() + 30_000;
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
  const binary = `${root}/build/bin/garazyk-ui`;
  const assets = `${root}/build/bin/Assets`;
  const port = await reservePort();
  const baseUrl = `http://${HOST}:${port}`;
  const server = new Deno.Command(binary, {
    args: ["serve", "--host", HOST, "--port", String(port)],
    env: {
      ...Deno.env.toObject(),
      GARAZYK_UI_ADMIN_PASSWORD: PASSWORD,
      GARAZYK_UI_ASSETS_DIR: assets,
    },
    stdout: "null",
    stderr: "null",
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

    await page.keyboard.press("Tab");
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

    console.log("✅ Admin UI visual smoke completed");
  } finally {
    await browser?.close();
    try {
      server.kill();
    } catch {
      // The server has already exited.
    }
  }
}

if (import.meta.main) {
  await main().catch((error) => {
    console.error(error);
    Deno.exit(1);
  });
}
