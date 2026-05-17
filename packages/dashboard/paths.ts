import { dirname, fromFileUrl, join, resolve } from "@std/path";

/** Options for resolving dashboard runtime paths. */
export interface DashboardPathOptions {
  /** Garażyk repository root. Defaults to GARAZYK_ROOT, then nearest parent of cwd/package. */
  rootDir?: string;
}

/** Runtime paths used by the dashboard server and tool entry points. */
export interface DashboardPaths {
  /** Directory containing this dashboard package. */
  packageDir: string;
  /** Garażyk repository root. */
  rootDir: string;
  /** Directory containing scenario runner support files. */
  scenarioScriptsDir: string;
  /** Directory containing individual scenario modules. */
  scenariosDir: string;
  /** Directory containing scenario JSON reports and dashboard DB. */
  reportsDir: string;
  /** Docker Compose project directory for the local network. */
  dockerLocalNetworkDir: string;
  /** Main scenario runner script. */
  runScenariosScript: string;
  /** SQLite database path for dashboard state. */
  dashboardDbPath: string;
  /** Active run lock file path. */
  activeRunLockPath: string;
  /** Fresh static asset directory. */
  staticDir: string;
}

const PACKAGE_DIR = dirname(fromFileUrl(import.meta.url));
let configuredRootDir: string | undefined;

/** Configure the repository root before importing route/service modules. */
export function configureDashboardPaths(
  options: DashboardPathOptions = {},
): void {
  if (options.rootDir) configuredRootDir = resolve(options.rootDir);
}

/** Return all filesystem paths used by the dashboard runtime. */
export function getDashboardPaths(): DashboardPaths {
  const rootDir = resolveGarazykRoot(
    configuredRootDir ?? Deno.env.get("GARAZYK_ROOT"),
  );
  const scenarioScriptsDir = join(rootDir, "scripts", "scenarios");
  const reportsDir = join(scenarioScriptsDir, "reports");

  return {
    packageDir: PACKAGE_DIR,
    rootDir,
    scenarioScriptsDir,
    scenariosDir: join(scenarioScriptsDir, "scenarios"),
    reportsDir,
    dockerLocalNetworkDir: join(rootDir, "docker", "local-network"),
    runScenariosScript: join(rootDir, "scripts", "run_scenarios.ts"),
    dashboardDbPath: join(reportsDir, "dashboard.db"),
    activeRunLockPath: join(reportsDir, "active-run.json"),
    staticDir: join(PACKAGE_DIR, "static"),
  };
}

/** Locate a Garażyk checkout from an optional start directory. */
export function resolveGarazykRoot(startDir?: string): string {
  const candidates = [
    startDir,
    Deno.cwd(),
    resolve(PACKAGE_DIR, "..", ".."),
  ].filter((candidate): candidate is string => Boolean(candidate));

  for (const candidate of candidates) {
    const found = findGarazykRoot(candidate);
    if (found) return found;
  }

  throw new Error(
    "Unable to locate the Garazyk repository root. Run from a checkout or set GARAZYK_ROOT.",
  );
}

function findGarazykRoot(startDir: string): string | undefined {
  let current = resolve(startDir);

  while (true) {
    if (isGarazykRoot(current)) return current;

    const parent = dirname(current);
    if (parent === current) return undefined;
    current = parent;
  }
}

function isGarazykRoot(dir: string): boolean {
  try {
    const runner = Deno.statSync(join(dir, "scripts", "run_scenarios.ts"));
    const scenarios = Deno.statSync(join(dir, "scripts", "scenarios"));
    return runner.isFile && scenarios.isDirectory;
  } catch {
    return false;
  }
}
