import type { Browser, Page } from "npm:playwright@1.52.0";
import { chromium } from "npm:playwright@1.52.0";

/**
 * Shared helpers for Playwright browser e2e tests in the scenario dashboard.
 *
 * @module browser_test_helpers
 */

/** Start the dashboard dev server on a given port and wait for it to respond. */
export async function startServer(
  dashboardDir: URL,
  port: number,
): Promise<Deno.ChildProcess> {
  const cmd = new Deno.Command("deno", {
    args: ["task", "dev"],
    cwd: dashboardDir,
    env: { ...Deno.env.toObject(), DASHBOARD_PORT: String(port) },
    stdout: "null",
    stderr: "null",
  });

  const proc = cmd.spawn();

  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://localhost:${port}/api/network/health`);
      if (res.ok) {
        console.log(`[OK] Server ready on port ${port}`);
        return proc;
      }
    } catch {
      // not ready yet
    }
    await new Promise((r) => setTimeout(r, 500));
  }

  proc.kill();
  throw new Error(`Server did not start within 30 seconds on port ${port}`);
}

/** Context passed to a browser persistence test function. */
export interface BrowserTestContext {
  page: Page;
  baseUrl: string;
}

/**
 * Run a browser-based persistence test with shared setup and teardown.
 *
 * Handles server startup, browser launch, page navigation, and cleanup.
 * The test function receives the page and base URL and runs the actual assertions.
 */
export async function runBrowserTest(
  dashboardDir: URL,
  port: number,
  testFn: (ctx: BrowserTestContext) => Promise<void>,
): Promise<void> {
  const baseUrl = `http://localhost:${port}`;
  console.log(`Starting dashboard dev server on port ${port}...`);
  const serverProc = await startServer(dashboardDir, port);

  let browser: Browser | undefined;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 15_000 });
    console.log("[OK] Page loaded");

    await testFn({ page, baseUrl });
  } finally {
    if (browser) await browser.close();
    serverProc.kill();
  }
}
