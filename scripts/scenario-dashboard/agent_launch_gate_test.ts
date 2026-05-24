/**
 * Browser e2e: Agent checkbox is gated on agent launch, not localStorage.
 *
 * Usage:
 *   deno run -A scripts/scenario-dashboard/agent_launch_gate_test.ts
 */

import { runBrowserTest } from "./browser_test_helpers.ts";

const DASHBOARD_DIR = new URL(".", import.meta.url);
const PORT = 3098;

async function main() {
  await runBrowserTest(DASHBOARD_DIR, PORT, async ({ page }) => {
    const checkbox = page.locator("input#agentMode");
    await checkbox.waitFor({ state: "attached", timeout: 10_000 });

    if (await checkbox.isChecked()) {
      throw new Error("Agent checkbox should start unchecked for a normal launch");
    }
    if (!(await checkbox.isDisabled())) {
      throw new Error("Agent checkbox should be disabled without agent launch");
    }
    console.log("[OK] Human launch: unchecked and disabled");

    await page.goto(`http://127.0.0.1:${PORT}/?agentLaunch=1`, {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
    });
    await checkbox.waitFor({ state: "attached", timeout: 10_000 });

    if (!(await checkbox.isChecked())) {
      throw new Error("Agent checkbox should be checked when opened with ?agentLaunch=1");
    }
    if (await checkbox.isDisabled()) {
      throw new Error("Agent checkbox should be enabled for agent launch URL");
    }

    const stored = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-agentMode")
    );
    if (stored === "true") {
      throw new Error("Agent mode must not be restored from localStorage");
    }
    console.log("[OK] Agent URL launch: checked, enabled, no localStorage");

    console.log("\n✅ Agent launch gate tests passed!");
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`\n❌ TEST FAILED: ${err.message}`);
    Deno.exit(1);
  });
}
