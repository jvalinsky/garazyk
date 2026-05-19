/**
 * Runner preflight checks — verifying staged binaries, Docker health,
 * and Playwright browser availability before scenario execution.
 *
 * @module preflight
 */

import { join } from "@std/path";
import { repoRoot } from "@garazyk/schemat/runtime";
import { brightRed, yellow } from "@std/fmt/colors";
import type { ScenarioInfo } from "./scenario_metadata.ts";

/** Results of a preflight check. */
export interface PreflightResult {
  /** Whether the check passed. */
  ok: boolean;
  /** Error message if the check failed. */
  message?: string;
  /** Hint command to fix the issue. */
  fixHint?: string;
  /** Whether the failure is fatal or can be skipped. */
  fatal: boolean;
}

/** Verify that staged Linux ELF binaries exist in the expected location. */
export async function checkStagedBinaries(): Promise<PreflightResult> {
  const root = await repoRoot();
  const stagingBin = join(root, "docker/local-network/staging/bin");
  const binaries = [
    "kaszlak",
    "campagnola",
    "zuk",
    "syrena",
    "mikrus",
    "garazyk-ui",
    "jelcz",
    "syrena-chat",
    "germ",
  ];

  const missing = [];
  for (const binary of binaries) {
    const path = join(stagingBin, binary);
    try {
      const stat = await Deno.stat(path);
      if (!stat.isFile) missing.push(binary);
    } catch {
      missing.push(binary);
    }
  }

  if (missing.length > 0) {
    return {
      ok: false,
      fatal: true,
      message: `Missing staged binaries: ${missing.join(", ")}`,
      fixHint: "deno run -A scripts/stage_binaries.ts",
    };
  }

  return { ok: true, fatal: true };
}

/** Check if Playwright browsers are installed. */
export async function checkPlaywright(required: boolean): Promise<PreflightResult> {
  try {
    // We use a dynamic import to avoid a hard dependency if playwright isn't even used.
    // In Deno, this will pull from npm if not already cached.
    const { chromium } = await import("npm:playwright");
    const browser = await chromium.launch({ timeout: 2000 });
    await browser.close();
    return { ok: true, fatal: required };
  } catch (err) {
    return {
      ok: false,
      fatal: required,
      message: `Playwright browser not found or failed to launch: ${err instanceof Error ? err.message : String(err)}`,
      fixHint: "npx playwright install --with-deps chromium",
    };
  }
}

/** Run all relevant preflight checks based on runner configuration. */
export async function runPreflight(options: {
  useBinary: boolean;
  clientFlow: string;
  selectedScenarios: ScenarioInfo[];
}): Promise<void> {
  if (!options.useBinary) {
    const staged = await checkStagedBinaries();
    if (!staged.ok) {
      printPreflightError(staged);
      Deno.exit(1);
    }
  }

  const needsBrowser = options.clientFlow !== "none" ||
    options.selectedScenarios.some((s) => s.browserFlows.length > 0);

  if (needsBrowser) {
    const pw = await checkPlaywright(options.clientFlow !== "none");
    if (!pw.ok) {
      if (pw.fatal) {
        printPreflightError(pw);
        Deno.exit(1);
      } else {
        console.warn(yellow(`\n[WARN]  Browser scenarios will be skipped: ${pw.message}`));
        console.warn(yellow(`        To enable them: \`${pw.fixHint}\`\n`));
      }
    }
  }
}

function printPreflightError(result: PreflightResult): void {
  console.error(brightRed("\nPreflight Check Failed!"));
  console.error(`Reason: ${result.message}`);
  if (result.fixHint) {
    console.error(yellow(`Hint: Run \`${result.fixHint}\` to fix this.`));
  }
  console.error("");
}
