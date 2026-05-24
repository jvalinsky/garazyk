/**
 * Browser e2e test: runner localStorage persistence
 *
 * Starts the dashboard dev server, opens a headless browser with Playwright,
 * selects a runner, reloads the page, and verifies the selection survived.
 *
 * Usage:
 *   deno run -A scripts/scenario-dashboard/runner_persistence_test.ts
 *
 * Requirements:
 *   Playwright with Chromium installed (npx playwright install chromium)
 */

import { runBrowserTest } from "./browser_test_helpers.ts";

const DASHBOARD_DIR = new URL(".", import.meta.url);
const PORT = 3097;

async function main() {
  await runBrowserTest(DASHBOARD_DIR, PORT, async ({ page }) => {
    const select = page.locator("select#runner-select");
    await select.waitFor({ state: "attached", timeout: 10_000 });
    console.log("[OK] Runner select found");

    // Verify default is "host"
    const initialValue = await select.inputValue();
    if (initialValue !== "host") {
      throw new Error(`Runner should default to 'host', got '${initialValue}'`);
    }
    console.log("[OK] Runner defaults to 'host'");

    // Verify localStorage
    const initialStored = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-runner")
    );
    if (!initialStored) {
      throw new Error("localStorage 'garazyk-dashboard-runner' is missing on first load");
    }
    if (initialStored !== "host") {
      throw new Error(`localStorage should be 'host', got '${initialStored}'`);
    }
    console.log("[OK] localStorage has garazyk-dashboard-runner = 'host'");

    // Switch to docker
    await select.selectOption("docker");
    const switched = await select.inputValue();
    if (switched !== "docker") {
      throw new Error(`Failed to switch runner to 'docker', got '${switched}'`);
    }
    console.log("[OK] Switched runner to 'docker'");

    const storedDocker = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-runner")
    );
    if (storedDocker !== "docker") {
      throw new Error(`Expected localStorage 'docker', got '${storedDocker}'`);
    }
    console.log("[OK] localStorage updated to 'docker'");

    // Reload and verify persistence
    await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    const selectAfterReload = page.locator("select#runner-select");
    await selectAfterReload.waitFor({ state: "attached", timeout: 10_000 });
    console.log("[OK] Page reloaded");

    const afterReload = await selectAfterReload.inputValue();
    if (afterReload !== "docker") {
      throw new Error(
        `After reload, runner should be 'docker', got '${afterReload}'`,
      );
    }
    console.log("[OK] Runner 'docker' survived reload");

    // Verify localStorage also survived
    const storedAfterReload = await page.evaluate(() =>
      localStorage.getItem("garazyk-dashboard-runner")
    );
    if (storedAfterReload !== "docker") {
      throw new Error(
        `After reload, localStorage should be 'docker', got '${storedAfterReload}'`,
      );
    }
    console.log("[OK] localStorage persistence confirmed after reload");

    // Switch back to host, reload, verify round-trip
    await selectAfterReload.selectOption("host");
    const backToHost = await selectAfterReload.inputValue();
    if (backToHost !== "host") {
      throw new Error(`Failed to switch back to 'host', got '${backToHost}'`);
    }

    await page.reload({ waitUntil: "domcontentloaded", timeout: 15_000 });
    const finalSelect = page.locator("select#runner-select");
    await finalSelect.waitFor({ state: "attached", timeout: 10_000 });

    const finalValue = await finalSelect.inputValue();
    if (finalValue !== "host") {
      throw new Error(
        `After switching back and reloading, runner should be 'host', got '${finalValue}'`,
      );
    }
    console.log("[OK] docker → host → reload → host — round-trip works!");

    console.log("\n✅ All runner persistence tests passed!");
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`\n❌ TEST FAILED: ${err.message}`);
    Deno.exit(1);
  });
}
