/**
 * @module scenarios/59_web_client_browser_flow
 *
 * Scenario: 59 web client browser flow
 *
 * Behavior:
 * - Executes the 59 web client browser flow scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { SERVICE_URLS, WEB_CLIENT_TOPOLOGY } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { attachPublicNetworkLeakGuard } from "../../lib/deno/browser_flow.ts";
import { chromium } from "npm:playwright";
import { join } from "@std/path";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

export async function run(): Promise<ScenarioResult> {
  const flow = Deno.env.get("ATPROTO_CLIENT_FLOW") || "smoke";
  const result = new ScenarioResult(`Web Client Browser Flow (${flow})`);
  result.start();

  const webClientUrl = (SERVICE_URLS.webClient || SERVICE_URLS.ui).replace(/\/$/, "");
  const diagnosticsDir = Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") || "/tmp";
  const browserDir = join(diagnosticsDir, "browser");
  await Deno.mkdir(browserDir, { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await context.newPage();
  const publicNetworkLeaks = attachPublicNetworkLeakGuard(page);
  const consoleErrors: string[] = [];

  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => consoleErrors.push(error.message));

  await timedCall(
    result,
    "Web app loads",
    async () => {
      const response = await page.goto(webClientUrl, {
        waitUntil: "domcontentloaded",
        timeout: 30000,
      });
      assert.isTrue(!!response, "no navigation response");
      assert.isTrue((response?.status() || 0) < 500, `status=${response?.status()}`);
      await page.screenshot({ path: join(browserDir, `web-client-${flow}.png`), fullPage: true });
      return response?.status();
    },
    (status) => `status=${status}`,
  );

  await timedCall(
    result,
    "Browser console is clean",
    () => {
      assert.isTrue(consoleErrors.length === 0, consoleErrors.slice(0, 5).join("\n"));
    },
  );

  await timedCall(
    result,
    "No public ATProto network leak",
    () => {
      assert.isTrue(publicNetworkLeaks.length === 0, publicNetworkLeaks.slice(0, 5).join("\n"));
    },
  );

  if (flow === "login" || flow === "deep") {
    const adapterPath = WEB_CLIENT_TOPOLOGY?.browserFlow[flow as "login" | "deep"];
    result.stepSkipped(
      `${flow} adapter flow`,
      adapterPath
        ? `adapter-owned selector flow declared at ${adapterPath}`
        : "no web-client topology selected",
    );
  }

  await browser.close();
  result.recordArtifact("browser", {
    screenshots_dir: browserDir,
    web_client_url: webClientUrl,
    web_client: WEB_CLIENT_TOPOLOGY || null,
  });
  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
