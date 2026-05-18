#!/usr/bin/env -S deno run -A
import { join, normalize } from "@std/path";

export type Bucket =
  | "classes"
  | "methods"
  | "properties"
  | "enums"
  | "categories"
  | "protocols";

export type Count = { total: number; documented: number };
export type Counts = Record<Bucket, Count>;
export type MissingCounts = Record<Bucket, number>;
export type Subsystem =
  | "Core"
  | "Database"
  | "Blob"
  | "Chat"
  | "AppView"
  | "Services"
  | "AdminUIServer"
  | "Other";

export type Options = {
  searchDir: string;
  minOverall?: number;
  minSubsystems: Map<Subsystem, number>;
  json: boolean;
  bySubsystem: boolean;
  files: boolean;
  subsystem?: Subsystem;
  includeFrameworks: boolean;
};

export type FileReport = {
  path: string;
  subsystem: Subsystem;
  totals: Counts;
  overall: Count & { percent: number };
  missing: MissingCounts;
};

export type Report = {
  searchRoots: string[];
  filesAnalyzed: number;
  totals: Counts;
  overall: Count & { percent: number };
  files?: FileReport[];
  subsystems?: Record<Subsystem, {
    filesAnalyzed: number;
    totals: Counts;
    overall: Count & { percent: number };
  }>;
  threshold?: {
    minOverall: number;
    passed: boolean;
  };
  subsystemThresholds?: Array<{
    subsystem: Subsystem;
    minimum: number;
    actual: number;
    passed: boolean;
  }>;
};

const buckets: Bucket[] = [
  "classes",
  "methods",
  "properties",
  "enums",
  "categories",
  "protocols",
];

const subsystems: Subsystem[] = [
  "Core",
  "Database",
  "Blob",
  "Chat",
  "AppView",
  "Services",
  "AdminUIServer",
  "Other",
];

export function emptyCounts(): Counts {
  return Object.fromEntries(
    buckets.map((bucket) => [bucket, { total: 0, documented: 0 }]),
  ) as Counts;
}

export function emptyMissingCounts(): MissingCounts {
  return Object.fromEntries(
    buckets.map((bucket) => [bucket, 0]),
  ) as MissingCounts;
}

export function addCounts(target: Counts, source: Counts): void {
  for (const bucket of buckets) {
    target[bucket].total += source[bucket].total;
    target[bucket].documented += source[bucket].documented;
  }
}

export function missingCounts(counts: Counts): MissingCounts {
  const results = emptyMissingCounts();
  for (const bucket of buckets) {
    results[bucket] = counts[bucket].total - counts[bucket].documented;
  }
  return results;
}

export function countDocumentation(content: string): Counts {
  const results = emptyCounts();
  const lines = content.split("\n");
  let docBlockStart = -1000;
  let inDocBlock = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.includes("/*!") || line.includes("/**")) {
      inDocBlock = true;
      docBlockStart = i;
    }
    if (line.includes("*/") && inDocBlock) inDocBlock = false;

    const previous10 = lines.slice(Math.max(0, i - 10), i).join("\n");
    const previous5 = lines.slice(Math.max(0, i - 5), i).join("\n");

    if (/^@interface\s+\w+\s*[:{<]/.test(line)) {
      results.classes.total++;
      if (previous10.includes("@class") || previous10.includes("@abstract")) {
        results.classes.documented++;
      }
    }
    if (/^@interface\s+\w+\s*\(/.test(line)) {
      results.categories.total++;
      if (
        previous10.includes("@category") || previous10.includes("@abstract")
      ) {
        results.categories.documented++;
      }
    }
    if (/^@protocol\s+\w+/.test(line)) {
      results.protocols.total++;
      if (
        previous10.includes("@protocol") || previous10.includes("@abstract")
      ) {
        results.protocols.documented++;
      }
    }
    if (line.includes("@property")) {
      results.properties.total++;
      if (
        previous5.includes("@abstract") || previous5.includes("@property") ||
        previous5.includes("/*!") || previous5.includes("/**")
      ) {
        results.properties.documented++;
      }
    }
    if (/^[+-]\s*\(/.test(line)) {
      results.methods.total++;
      if (i - docBlockStart <= 10 && docBlockStart >= 0) {
        results.methods.documented++;
      }
    }
    if (
      line.includes("typedef NS_ENUM") || line.includes("typedef NS_OPTIONS")
    ) {
      results.enums.total++;
      if (previous10.includes("@enum") || previous10.includes("@abstract")) {
        results.enums.documented++;
      }
    }
  }

  return results;
}

export async function* walkHeaders(dir: string): AsyncGenerator<string> {
  try {
    for await (const entry of Deno.readDir(dir)) {
      const path = join(dir, entry.name);
      if (path.includes("/Compat/")) continue;
      if (entry.isDirectory) {
        yield* walkHeaders(path);
      } else if (entry.isFile && entry.name.endsWith(".h")) {
        yield path;
      }
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(`Search directory not found: ${dir}`);
    }
    throw error;
  }
}

export function pct(total: number, documented: number): number {
  return total === 0 ? 100 : Math.floor((documented * 100) / total);
}

export function summarize(counts: Counts): Count & { percent: number } {
  const total = buckets.reduce((sum, bucket) => sum + counts[bucket].total, 0);
  const documented = buckets.reduce(
    (sum, bucket) => sum + counts[bucket].documented,
    0,
  );

  return { total, documented, percent: pct(total, documented) };
}

export function subsystemForPath(path: string): Subsystem {
  const normalized = normalize(path);

  if (normalized.includes("Garazyk/Sources/Core/")) return "Core";
  if (normalized.includes("Garazyk/Sources/Database/")) return "Database";
  if (normalized.includes("Garazyk/Sources/Blob/")) return "Blob";
  if (normalized.includes("Garazyk/Sources/Chat/")) return "Chat";
  if (normalized.includes("Garazyk/Sources/AppView/")) return "AppView";
  if (normalized.includes("Garazyk/Sources/Services/")) return "Services";
  if (normalized.includes("Garazyk/Sources/AdminUIServer/")) {
    return "AdminUIServer";
  }
  if (normalized.includes("Garazyk/Sources/Mikrus/")) return "Services";
  if (normalized.includes("Garazyk/Sources/Registration/")) return "Services";
  if (normalized.includes("Garazyk/Sources/PLC/")) return "Core";
  if (normalized.includes("Garazyk/Sources/Sync/")) return "Core";
  if (normalized.includes("Garazyk/Sources/Security/")) return "Core";
  if (normalized.includes("Garazyk/Sources/Repository/")) return "Core";
  if (normalized.includes("Garazyk/Sources/Video/")) return "Services";

  return "Other";
}

function isSubsystem(value: string): value is Subsystem {
  return (subsystems as string[]).includes(value);
}

function parseMinOverall(value: string | undefined): number {
  if (value === undefined) {
    throw new Error("--min-overall requires a numeric value");
  }

  const threshold = Number(value);
  if (!Number.isInteger(threshold) || threshold < 0 || threshold > 100) {
    throw new Error("--min-overall must be an integer from 0 to 100");
  }

  return threshold;
}

function parseSubsystemThreshold(
  value: string | undefined,
): [Subsystem, number] {
  if (value === undefined) {
    throw new Error("--min-subsystem requires a value like Chat=60");
  }

  const [subsystem, thresholdText] = value.split("=");
  if (!subsystem || !thresholdText || !isSubsystem(subsystem)) {
    throw new Error(
      `--min-subsystem must use a known subsystem, got: ${value}`,
    );
  }

  return [subsystem, parseMinOverall(thresholdText)];
}

export function classifyDoc(path: string): string {
  const normalized = normalize(path);
  if (
    normalized.includes("docs/archive/") ||
    normalized.includes("docs/scratchpad/")
  ) {
    return "archive";
  }
  if (normalized.includes("docs/")) {
    return "canonical";
  }
  if (normalized.endsWith("README.md")) {
    return "entrypoint";
  }
  return "internal-reference";
}

export function inferOwner(path: string): string {
  if (path.startsWith("docs/")) {
    if (path.startsWith("docs/security/")) return "security";
    if (path.startsWith("docs/tests/")) return "quality";
    if (path.startsWith("docs/plans/")) return "planning";
    return "docs";
  }
  if (path.startsWith("Garazyk/Sources/Admin/")) return "admin";
  if (path.startsWith("Garazyk/")) return "core";
  if (path.startsWith("tooling/")) return "tooling";
  if (path.startsWith("skills/")) return "skills";
  if (path.startsWith("scripts/")) return "tooling";
  if (path.startsWith("examples/")) return "docs";
  return "docs";
}

export function inferStatus(classification: string): string {
  if (classification === "canonical" || classification === "entrypoint") {
    return "active";
  }
  if (classification === "archive") return "archived";
  return "reference";
}

export function inferCanonicalTarget(
  path: string,
  classification: string,
): string {
  if (classification === "canonical") return path;

  const explicit: Record<string, string> = {
    "README.md": "docs/index.md",
    "BUILD.md": "docs/01-getting-started/setup.md",
    "CONTRIBUTING.md": "docs/index.md",
    "DOCUMENTATION.md": "docs/11-reference/documentation-map.md",
    "AGENTS.md": "docs/11-reference/documentation-map.md",
    "AGENTS_QUICKREF.md": "docs/11-reference/documentation-map.md",
    "ADMINUI_START_HERE.md": "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_QUICKSTART.md": "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_PROJECT_COMPLETE.md":
      "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_DEPLOYMENT_GUIDE.md":
      "docs/11-reference/admin-ui-documentation.md",
  };
  if (explicit[path]) return explicit[path];
  if (path.startsWith("docs/security/")) {
    return "docs/11-reference/security-audit-guide.md";
  }
  if (path.startsWith("docs/tests/")) return "docs/11-reference/testing-map.md";
  if (path.startsWith("docs/oauth2/")) {
    return "docs/06-authentication/oauth2-dpop.md";
  }
  if (path.startsWith("docs/architecture/")) {
    return "docs/01-getting-started/architecture-overview.md";
  }
  if (path.startsWith("docs/guides/")) return "docs/index.md";
  if (path.startsWith("docs/plans/") || path.startsWith("docs/plan/")) {
    return "docs/archive/planning/README.md";
  }
  if (path.startsWith("docs/scratchpad/")) {
    return "docs/archive/planning/README.md";
  }
  if (path.startsWith("Garazyk/Sources/Admin/")) {
    return "docs/11-reference/admin-ui-documentation.md";
  }
  if (path.startsWith("Garazyk/")) {
    return "docs/11-reference/source-adjacent-documentation.md";
  }
  if (path.startsWith("skills/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("tooling/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("scripts/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("examples/")) return "docs/10-tutorials/index.md";
  return "docs/index.md";
}

export function createSubsystemReport(): Record<Subsystem, {
  filesAnalyzed: number;
  totals: Counts;
  overall: Count & { percent: number };
}> {
  return Object.fromEntries(
    subsystems.map((subsystem) => [
      subsystem,
      {
        filesAnalyzed: 0,
        totals: emptyCounts(),
        overall: { total: 0, documented: 0, percent: 100 },
      },
    ]),
  ) as Record<Subsystem, {
    filesAnalyzed: number;
    totals: Counts;
    overall: Count & { percent: number };
  }>;
}

export function printCounts(
  title: string,
  counts: Counts,
  filesAnalyzed?: number,
): void {
  console.log(title);
  console.log("=".repeat(title.length));
  console.log("");

  for (const bucket of buckets) {
    const { total, documented } = counts[bucket];
    console.log(
      `${bucket.charAt(0).toUpperCase() + bucket.slice(1).padEnd(11)} ${
        String(documented).padStart(5)
      } / ${String(total).padEnd(5)} (${
        String(pct(total, documented)).padStart(3)
      }%)`,
    );
  }

  const overall = summarize(counts);
  console.log("");
  console.log("------------------------------");
  console.log(
    `${"OVERALL".padEnd(12)} ${String(overall.documented).padStart(5)} / ${
      String(overall.total).padEnd(5)
    } (${String(overall.percent).padStart(3)}%)`,
  );

  if (filesAnalyzed !== undefined) {
    console.log(`\nFiles analyzed: ${filesAnalyzed}`);
  }
  console.log("");
}

function missingTotal(counts: MissingCounts): number {
  return buckets.reduce(
    (sum, bucket) => sum + counts[bucket],
    0,
  );
}

export function printFileReports(files: FileReport[]): void {
  const rows = files
    .filter((file) => missingTotal(file.missing) > 0)
    .sort((left, right) =>
      missingTotal(right.missing) - missingTotal(left.missing)
    );

  if (rows.length === 0) {
    console.log("No undocumented declarations found in matching files.");
    return;
  }

  console.log("File Coverage Gaps");
  console.log("==================");
  console.log("");
  for (const file of rows) {
    const missing = buckets
      .filter((bucket) => file.missing[bucket] > 0)
      .map((bucket) => `${bucket}:${file.missing[bucket]}`)
      .join(" ");
    console.log(
      `${String(missingTotal(file.missing)).padStart(4)} missing  ${
        String(file.overall.percent).padStart(3)
      }%  ${file.subsystem.padEnd(13)} ${file.path}  ${missing}`,
    );
  }
  console.log("");
}

export function printTextReport(report: Report): void {
  console.log("\nDOCUMENTATION COVERAGE REPORT");
  console.log("==============================\n");
  console.log(`Search roots: ${report.searchRoots.join(", ")}\n`);

  if (
    !report.files || !report.files.every((file) => file.subsystem !== "Other")
  ) {
    printCounts("Overall", report.totals, report.filesAnalyzed);
  }

  if (report.subsystems) {
    for (const subsystem of subsystems) {
      const entry = report.subsystems[subsystem];
      if (report.files && report.files.length > 0) {
        const hasMatchingFiles = report.files.some((file) =>
          file.subsystem === subsystem
        );
        if (!hasMatchingFiles) continue;
      }
      if (entry.filesAnalyzed === 0 && entry.overall.total === 0) continue;

      printCounts(`${subsystem} Subsystem`, entry.totals, entry.filesAnalyzed);
    }
  }

  if (report.files) {
    printFileReports(report.files);
  }

  if (report.threshold) {
    if (report.threshold.passed) {
      console.log(`[PASS] Coverage >= ${report.threshold.minOverall}%`);
    } else {
      console.log(`[FAIL] Coverage < ${report.threshold.minOverall}%`);
    }
  } else {
    console.log("[INFO] No coverage threshold configured.");
  }

  if (report.subsystemThresholds) {
    for (const threshold of report.subsystemThresholds) {
      const status = threshold.passed ? "PASS" : "FAIL";
      console.log(
        `[${status}] ${threshold.subsystem} coverage ${
          threshold.passed ? ">=" : "<"
        } ${threshold.minimum}% (actual ${threshold.actual}%)`,
      );
    }
  }
}

export async function buildReport(options: Options): Promise<Report> {
  const searchRoots = [options.searchDir];
  if (options.includeFrameworks) {
    searchRoots.push("Garazyk/Frameworks");
  }

  const totals = emptyCounts();
  const subsystemReport =
    (options.bySubsystem || options.minSubsystems.size > 0)
      ? createSubsystemReport()
      : undefined;
  const fileReports: FileReport[] = [];
  let fileCount = 0;

  for (const root of searchRoots) {
    for await (const path of walkHeaders(root)) {
      const subsystem = subsystemForPath(path);
      if (options.subsystem && subsystem !== options.subsystem) {
        continue;
      }

      let content = "";
      try {
        content = await Deno.readTextFile(path);
      } catch {
        continue;
      }

      fileCount++;
      const results = countDocumentation(content);
      addCounts(totals, results);

      if (subsystemReport) {
        subsystemReport[subsystem].filesAnalyzed++;
        addCounts(subsystemReport[subsystem].totals, results);
      }

      if (options.files) {
        const overall = summarize(results);
        fileReports.push({
          path,
          subsystem,
          totals: results,
          overall,
          missing: missingCounts(results),
        });
      }
    }
  }

  if (subsystemReport) {
    for (const subsystem of subsystems) {
      subsystemReport[subsystem].overall = summarize(
        subsystemReport[subsystem].totals,
      );
    }
  }

  const overall = summarize(totals);
  const subsystemThresholds = subsystemReport
    ? [...options.minSubsystems.entries()].map(([subsystem, minimum]) => {
      const actual = subsystemReport[subsystem].overall.percent;
      return {
        subsystem,
        minimum,
        actual,
        passed: actual >= minimum,
      };
    })
    : undefined;

  return {
    searchRoots,
    filesAnalyzed: fileCount,
    totals,
    overall,
    files: options.files ? fileReports : undefined,
    subsystems: subsystemReport,
    threshold: options.minOverall === undefined ? undefined : {
      minOverall: options.minOverall,
      passed: overall.percent >= options.minOverall,
    },
    subsystemThresholds,
  };
}

function printUsage(): void {
  console.log(`Usage: doc-coverage.ts [search-dir] [options]

Options:
  --min-overall <0-100>  Fail when overall coverage is below this percentage.
  --min-subsystem Name=N Fail when a subsystem is below this percentage.
  --by-subsystem         Print coverage grouped by major Garazyk subsystem.
  --subsystem <name>     Focus text and file output on one subsystem.
  --files                Print per-header undocumented counts.
  --json                 Print machine-readable JSON instead of text.
  --include-frameworks   Also scan Garazyk/Frameworks.
  --help                 Show this help text.

Examples:
  deno run -A packages/narzedzia/doc_coverage.ts Garazyk/Sources --files
  deno run -A packages/narzedzia/doc_coverage.ts Garazyk/Sources --subsystem Chat --files
  deno run -A packages/narzedzia/doc_coverage.ts Garazyk/Sources --min-subsystem Chat=60`);
}

function formatBucket(bucket: Bucket): string {
  return bucket.charAt(0).toUpperCase() + bucket.slice(1).padEnd(11);
}

export async function parseArgs(
  args: string[],
  defaultSearchDir = "Garazyk/Sources",
): Promise<Options> {
  const options: Options = {
    searchDir: defaultSearchDir,
    minSubsystems: new Map<Subsystem, number>(),
    json: false,
    bySubsystem: false,
    files: false,
    includeFrameworks: false,
  };

  let searchDirSet = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case "--min-overall":
        options.minOverall = parseMinOverall(args[++i]);
        break;
      case "--min-subsystem": {
        const [subsystem, threshold] = parseSubsystemThreshold(args[++i]);
        options.minSubsystems.set(subsystem, threshold);
        options.bySubsystem = true;
        break;
      }
      case "--json":
        options.json = true;
        break;
      case "--by-subsystem":
        options.bySubsystem = true;
        break;
      case "--files":
        options.files = true;
        break;
      case "--subsystem": {
        const subsystem = args[++i];
        if (subsystem === undefined || !isSubsystem(subsystem)) {
          throw new Error(
            `--subsystem must be one of: ${subsystems.join(", ")}`,
          );
        }
        options.subsystem = subsystem;
        options.bySubsystem = true;
        break;
      }
      case "--include-frameworks":
        options.includeFrameworks = true;
        break;
      case "--help":
        printUsage();
        Deno.exit(0);
        break;
      default:
        if (arg.startsWith("--")) {
          throw new Error(`Unknown option: ${arg}`);
        }
        if (searchDirSet) {
          throw new Error(`Unexpected extra argument: ${arg}`);
        }
        options.searchDir = arg;
        searchDirSet = true;
    }
  }

  return options;
}

export async function main(): Promise<void> {
  try {
    const options = await parseArgs(Deno.args);
    const report = await buildReport(options);

    if (options.json) {
      console.log(JSON.stringify(report, null, 2));
    } else {
      printTextReport(report);
    }

    const failedSubsystemThreshold = report.subsystemThresholds?.some(
      (threshold) => !threshold.passed,
    ) ?? false;

    if (
      (report.threshold && !report.threshold.passed) || failedSubsystemThreshold
    ) {
      Deno.exit(1);
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(2);
  }
}

if (import.meta.main) {
  await main();
}
