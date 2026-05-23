/**
 * Runner preflight checks — verifying staged binaries, Docker health,
 * and Playwright browser availability before scenario execution.
 *
 * @module preflight
 */

import { join } from "@std/path";
import { repoRoot, serviceUrl } from "@garazyk/schemat/runtime";
import { neededPorts } from "@garazyk/schemat/runtime";
import { brightRed, green, yellow } from "@std/fmt/colors";
import { waitForHttp } from "@garazyk/laweta";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { ResourceIsolationMode } from "@garazyk/schemat";

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

interface PlaywrightModule {
  chromium: {
    launch(options: { timeout: number }): Promise<{ close(): Promise<void> }>;
  };
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
    "beskid",
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
export async function checkPlaywright(
  required: boolean,
): Promise<PreflightResult> {
  try {
    // Playwright is an optional runtime dependency for browser scenarios.
    const { chromium } = await import(
      "npm:playwright@1.52.0"
    ) as PlaywrightModule;
    const browser = await chromium.launch({ timeout: 2000 });
    await browser.close();
    return { ok: true, fatal: required };
  } catch (err) {
    return {
      ok: false,
      fatal: required,
      message: `Playwright browser not found or failed to launch: ${
        err instanceof Error ? err.message : String(err)
      }`,
      fixHint: "npx playwright install --with-deps chromium",
    };
  }
}

/** Kill host processes blocking ports needed by the local network. */
export async function checkHostPorts(
  opts: { withPds2?: boolean; otel?: boolean },
): Promise<void> {
  const ports = neededPorts(opts);
  const knownBinaries = new Set([
    "kaszlak",
    "garazyk-ui",
    "campagnola",
    "zuk",
    "syrena",
    "syrena-chat",
    "jelcz",
    "germ",
    "mikrus",
    "beskid",
  ]);
  for (const port of ports) {
    try {
      const lsofProc = new Deno.Command("lsof", {
        args: ["-ti", `:${port}`],
        stdout: "piped",
        stderr: "piped",
      });
      const { code, stdout } = await lsofProc.output();
      if (code !== 0) continue;
      const pids = new TextDecoder().decode(stdout).trim().split("\n").filter(
        Boolean,
      );
      for (const pid of pids) {
        const psProc = new Deno.Command("ps", {
          args: ["-p", pid, "-o", "comm="],
          stdout: "piped",
        });
        const { code: pc, stdout: pout } = await psProc.output();
        if (pc !== 0) continue;
        const cmd = new TextDecoder().decode(pout).trim();
        if (
          knownBinaries.has(cmd) || cmd.startsWith("garazyk") ||
          cmd.startsWith("atproto")
        ) {
          console.warn(
            yellow(
              `[WARN]  Stale process on port ${port} (PID: ${pid}, ${cmd}) — killing`,
            ),
          );
          await new Deno.Command("kill", { args: ["-9", pid] }).output();
        }
      }
    } catch { /* skip */ }
  }
  await new Promise((resolve) => setTimeout(resolve, 1000));
}

/** Health probe config for a single service. */
interface HealthProbe {
  key: string;
  path: string;
  timeoutSeconds: number;
  headers?: Record<string, string>;
}

const DEFAULT_PROBES: HealthProbe[] = [
  { key: "plc", path: "/_health", timeoutSeconds: 5 },
  {
    key: "pds",
    path: "/xrpc/com.atproto.server.describeServer",
    timeoutSeconds: 5,
  },
  { key: "relay", path: "/api/relay/health", timeoutSeconds: 5 },
  { key: "appview", path: "/admin/backfill/status", timeoutSeconds: 10 },
  { key: "chat", path: "/_health", timeoutSeconds: 5 },
  { key: "germ", path: "/_health", timeoutSeconds: 5 },
];

const PDS2_PROBE: HealthProbe = {
  key: "pds2",
  path: "/xrpc/com.atproto.server.describeServer",
  timeoutSeconds: 5,
};

const UI_PROBE: HealthProbe = {
  key: "ui",
  path: "/lab",
  timeoutSeconds: 5,
};

/** Verify that all expected ATProto services respond to health probes.
 *
 * Intended for --no-setup runs where the network is expected to already be
 * running. Exits with code 1 if any required service is unreachable.
 */
export async function verifyNetworkHealth(opts: {
  withPds2?: boolean;
  withUi?: boolean;
}): Promise<void> {
  const appviewAdminSecret = Deno.env.get("APPVIEW_ADMIN_SECRET") ||
    "localdevadmin";
  const probes = DEFAULT_PROBES.map((probe) =>
    probe.key === "appview"
      ? {
        ...probe,
        headers: { "Authorization": `Bearer ${appviewAdminSecret}` },
      }
      : probe
  );
  if (opts.withPds2) probes.push(PDS2_PROBE);
  if (opts.withUi) probes.push(UI_PROBE);

  console.log(yellow("\n[PREFLIGHT] Verifying network health..."));
  let allOk = true;
  for (const probe of probes) {
    const url = `${serviceUrl(probe.key)}${probe.path}`;
    const ok = await waitForHttp(
      url,
      probe.key,
      probe.timeoutSeconds,
      probe.headers,
    );
    if (!ok) {
      allOk = false;
      console.error(
        brightRed(`[FAIL]  ${probe.key} not reachable at ${url}`),
      );
    }
  }

  if (!allOk) {
    console.error(
      brightRed(
        "\n[PREFLIGHT] Network health check failed — ensure services are running before using --no-setup\n",
      ),
    );
    Deno.exit(1);
  }

  console.log(green("[PREFLIGHT] All services healthy\n"));
}

/** Run all relevant preflight checks based on runner configuration. */
export async function runPreflight(options: {
  useBinary: boolean;
  clientFlow: string;
  selectedScenarios: ScenarioInfo[];
  withPds2?: boolean;
  noSetup?: boolean;
  isolation?: ResourceIsolationMode;
}): Promise<void> {
  if (options.isolation === "legacy-fixed") {
    await checkHostPorts({ withPds2: options.withPds2 });
  }
  const withUi = options.selectedScenarios.some((scenario) =>
    scenario.requires.some((req) => req.role === "ui")
  );

  if (options.noSetup) {
    await verifyNetworkHealth({ withPds2: options.withPds2, withUi });
  }

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
        console.warn(
          yellow(`\n[WARN]  Browser scenarios will be skipped: ${pw.message}`),
        );
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
