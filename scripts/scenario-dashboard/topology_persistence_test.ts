/**
 * Browser e2e test: topology localStorage persistence
 *
 * Starts the dashboard dev server, opens a headless browser with Playwright,
 * selects a topology, reloads the page, and verifies the selection survived.
 *
 * Usage:
 *   deno run -A scripts/scenario-dashboard/topology_persistence_test.ts
 *
 * Requirements:
 *   Playwright with Chromium installed (npx playwright install chromium)
 */

import { runBrowserTest } from "./browser_test_helpers.ts";

const DASHBOARD_DIR = new URL(".", import.meta.url);
const PORT = 3098;

async function main() {
  await runBrowserTest(DASHBOARD_DIR, PORT, async ({ page }) => {
    const select = page.locator("select#topology-select");
    await select.waitFor({ state: "attached", timeout: 10_000 });
    console.log("[OK] Topology select found");

    // Read initial value
    const initialValue = await select.inputValue();
    console.log(`[OK] Initial topology: ${initialValue}`);

    // Verify localStorage matches initial value
    const initialStored = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-topology")
    );
    if (!initialStored) {
      throw new Error(
        "localStorage 'garazyk-dashboard-topology' is missing on first load",
      );
    }
    if (initialStored !== initialValue) {
      throw new Error(
        `localStorage value '${initialStored}' doesn't match select value '${initialValue}'`,
      );
    }
    console.log(`[OK] localStorage matches: ${initialStored}`);

    // Select a different topology (if available)
    const options = await select.locator("option").all();
    const optionValues = await Promise.all(
      options.map((opt) => opt.getAttribute("value")),
    );
    const other = optionValues.find(
      (v): v is string => v !== null && v !== initialValue,
    );
    if (!other) {
      console.log("[SKIP] Only one topology available — cannot test selection change");
    } else {
      await select.selectOption(other);
      const newValue = await select.inputValue();
      if (newValue !== other) {
        throw new Error(`Failed to select '${other}', got '${newValue}'`);
      }
      console.log(`[OK] Switched topology to: ${other}`);

      const storedAfterChange = await page.evaluate(() =>
        localStorage.getItem("garazyk-dashboard-topology")
      );
      if (storedAfterChange !== other) {
        throw new Error(
          `localStorage should be '${other}' after change, got '${storedAfterChange}'`,
        );
      }
      console.log("[OK] localStorage updated after selection change");
    }

    // Reload and verify persistence
    await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    const selectAfterReload = page.locator("select#topology-select");
    await selectAfterReload.waitFor({ state: "attached", timeout: 10_000 });
    console.log("[OK] Page reloaded");

    const expected = other ?? initialValue;
    const valueAfterReload = await selectAfterReload.inputValue();
    if (valueAfterReload !== expected) {
      throw new Error(
        `After reload, topology should be '${expected}', got '${valueAfterReload}'`,
      );
    }
    console.log(`[OK] Topology '${valueAfterReload}' survived reload`);

    const storedAfterReload = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-topology")
    );
    if (storedAfterReload !== expected) {
      throw new Error(
        `After reload, localStorage should be '${expected}', got '${storedAfterReload}'`,
      );
    }
    console.log("[OK] localStorage persistence confirmed after reload");

    console.log("\n✅ All topology persistence tests passed!");
  });
}

if (import.meta.main) {
  await main().catch((err) => {
    console.error(`\n❌ TEST FAILED: ${err.message}`);
    Deno.exit(1);
  });
}
