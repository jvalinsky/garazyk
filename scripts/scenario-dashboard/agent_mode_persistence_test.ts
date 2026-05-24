/**
 * Browser e2e test: agentMode localStorage persistence
 *
 * Starts the dashboard dev server, opens a headless browser with Playwright,
 * toggles the Agent checkbox, reloads the page, and verifies the checkbox
 * state survives the reload.
 *
 * Usage:
 *   deno run -A scripts/scenario-dashboard/agent_mode_persistence_test.ts
 *
 * Requirements:
 *   Playwright with Chromium installed (npx playwright install chromium)
 */

import { runBrowserTest } from "./browser_test_helpers.ts";

const DASHBOARD_DIR = new URL(".", import.meta.url);
const PORT = 3099;

async function main() {
  await runBrowserTest(DASHBOARD_DIR, PORT, async ({ page }) => {
    const checkbox = page.locator('input[type="checkbox"]#agentMode');
    await checkbox.waitFor({ state: "attached", timeout: 10_000 });

    // Verify it starts unchecked (default: false)
    let checked = await checkbox.isChecked();
    if (checked) {
      throw new Error("Agent checkbox should start unchecked (default false)");
    }
    console.log("[OK] Checkbox starts unchecked");

    // Check the box
    await checkbox.check();
    checked = await checkbox.isChecked();
    if (!checked) {
      throw new Error("Failed to check Agent checkbox");
    }
    console.log("[OK] Checkbox checked");

    // Verify localStorage was written
    const storedBefore = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-agentMode")
    );
    if (storedBefore !== "true") {
      throw new Error(
        `Expected localStorage key 'garazyk-dashboard-agentMode' to be 'true', got '${storedBefore}'`,
      );
    }
    console.log("[OK] localStorage has garazyk-dashboard-agentMode = 'true'");

    // Reload and verify persistence
    await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    const checkboxAfter = page.locator('input[type="checkbox"]#agentMode');
    await checkboxAfter.waitFor({ state: "attached", timeout: 10_000 });
    console.log("[OK] Page reloaded");

    const checkedAfter = await checkboxAfter.isChecked();
    if (!checkedAfter) {
      throw new Error(
        "Agent checkbox should still be checked after reload. localStorage persistence failed.",
      );
    }
    console.log("[OK] Checkbox still checked after reload — persistence works!");

    // Verify localStorage value survived
    const storedAfter = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-agentMode")
    );
    if (storedAfter !== "true") {
      throw new Error(
        `After reload, localStorage should still be 'true', got '${storedAfter}'`,
      );
    }
    console.log("[OK] localStorage still has 'true' after reload");

    // Uncheck, reload, verify it stays unchecked
    await checkboxAfter.uncheck();
    const unchecked = await checkboxAfter.isChecked();
    if (unchecked) {
      throw new Error("Failed to uncheck Agent checkbox");
    }

    const storedUnchecked = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-agentMode")
    );
    if (storedUnchecked !== "false") {
      throw new Error(
        `After unchecking, localStorage should be 'false', got '${storedUnchecked}'`,
      );
    }

    await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    const finalCheckbox = page.locator('input[type="checkbox"]#agentMode');
    await finalCheckbox.waitFor({ state: "attached", timeout: 10_000 });
    const finalChecked = await finalCheckbox.isChecked();
    if (finalChecked) {
      throw new Error(
        "Agent checkbox should be unchecked after reload when localStorage was 'false'",
      );
    }
    console.log("[OK] Uncheck → reload → still unchecked — round-trip works!");

    console.log("\n✅ All agent mode persistence tests passed!");
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`\n❌ TEST FAILED: ${err.message}`);
    Deno.exit(1);
  });
}
