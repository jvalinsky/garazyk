#!/usr/bin/env -S deno run -A

/**
 * Measures HeaderDoc coverage in Garazyk Objective-C headers.
 *
 * @module doc_coverage
 */

import { join, normalize } from "@std/path";

/**
 * Objective-C declaration categories counted by the coverage scanner.
 *
 * @public
 */
export type Bucket =
  | "classes"
  | "methods"
  | "properties"
  | "enums"
  | "categories"
  | "protocols";

/** Documented and total declaration counts for one category. @public */
export type Count = { total: number; documented: number };

/** Declaration counts keyed by coverage category. @public */
export type Counts = Record<Bucket, Count>;

/** Missing declaration counts keyed by coverage category. @public */
export type MissingCounts = Record<Bucket, number>;

/**
 * Source subsystem names used for coverage grouping and thresholds.
 *
 * @public
 */
export type Subsystem =
  | "Core"
  | "Database"
  | "Blob"
  | "Chat"
  | "AppView"
  | "Services"
  | "AdminUIServer"
  | "Other";

/**
 * Parsed command-line options for the HeaderDoc coverage scan.
 *
 * @public
 */
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

/**
 * Coverage details for one Objective-C header.
 *
 * @public
 */
export type FileReport = {
  path: string;
  subsystem: Subsystem;
  totals: Counts;
  overall: Count & { percent: number };
  missing: MissingCounts;
};

/**
 * Complete HeaderDoc coverage result, including optional threshold checks.
 *
 * @public
 */
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

/**
 * Creates zeroed declaration counts for every coverage category.
 *
 * @returns A mutable count record with independent entries
 * @public
 */
export function emptyCounts(): Counts {
  return Object.fromEntries(
    buckets.map((bucket) => [bucket, { total: 0, documented: 0 }]),
  ) as Counts;
}

/**
 * Creates zeroed missing-documentation counts.
 *
 * @returns A mutable missing-count record
 * @public
 */
export function emptyMissingCounts(): MissingCounts {
  return Object.fromEntries(
    buckets.map((bucket) => [bucket, 0]),
  ) as MissingCounts;
}

/**
 * Adds source declaration counts into an existing aggregate.
 *
 * @param target - Mutable aggregate to update
 * @param source - Counts to add
 * @public
 */
export function addCounts(target: Counts, source: Counts): void {
  for (const bucket of buckets) {
    target[bucket].total += source[bucket].total;
    target[bucket].documented += source[bucket].documented;
  }
}

/**
 * Computes undocumented declarations for each category.
 *
 * @param counts - Documented and total declaration counts
 * @returns Missing counts keyed by declaration category
 * @public
 */
export function missingCounts(counts: Counts): MissingCounts {
  const results = emptyMissingCounts();
  for (const bucket of buckets) {
    results[bucket] = counts[bucket].total - counts[bucket].documented;
  }
  return results;
}

/**
 * Counts Objective-C declarations and their adjacent documentation comments.
 *
 * @remarks
 * The scanner intentionally uses lightweight line matching rather than a full
 * Objective-C parser. A declaration is documented when a `/**` or `/*!`
 * comment begins within the category-specific lookback window.
 *
 * @param content - Header source text
 * @returns Declaration and documentation counts
 * @public
 */
export function countDocumentation(content: string): Counts {
  const results = emptyCounts();
  const lines = content.split("\n");

  let lastCommentStartLine = -1000;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // Track comments
    if (line.startsWith("/*!") || line.startsWith("/**")) {
      lastCommentStartLine = i;
    }

    // Detect declarations
    // @interface ClassName(Category)
    const categoryMatch = line.match(/^@interface\s+\w+\s*\(/);
    if (categoryMatch) {
      const documented = i - lastCommentStartLine <= 10;
      results.categories.total++;
      if (documented) results.categories.documented++;
      continue;
    }

    // @interface ClassName : BaseClass
    const interfaceMatch = line.match(/^@interface\s+(\w+)\s*[:{<]/);
    if (interfaceMatch) {
      const documented = i - lastCommentStartLine <= 10;
      results.classes.total++;
      if (documented) results.classes.documented++;
      continue;
    }

    // @end
    if (line.startsWith("@end")) {
      continue;
    }

    // @protocol ProtocolName
    const protocolMatch = line.match(/^@protocol\s+(\w+)/);
    if (protocolMatch) {
      const documented = i - lastCommentStartLine <= 10;
      results.protocols.total++;
      if (documented) results.protocols.documented++;
      continue;
    }

    // @property (readonly) type name;
    if (line.startsWith("@property")) {
      const documented = i - lastCommentStartLine <= 5;
      results.properties.total++;
      if (documented) results.properties.documented++;
      continue;
    }

    // - (void)methodName:(type)arg;
    if (/^[+-]\s*\(/.test(line)) {
      const documented = i - lastCommentStartLine <= 10;
      results.methods.total++;
      if (documented) results.methods.documented++;
      continue;
    }

    // typedef NS_ENUM(type, name) { ... }
    if (line.includes("NS_ENUM") || line.includes("NS_OPTIONS")) {
      const documented = i - lastCommentStartLine <= 10;
      results.enums.total++;
      if (documented) results.enums.documented++;
      continue;
    }
  }

  return results;
}

/**
 * Recursively yields Objective-C headers below a directory.
 *
 * @remarks
 * Compatibility headers under a `Compat` path are excluded from coverage.
 *
 * @param dir - Directory to traverse
 * @returns An asynchronous sequence of header paths
 * @throws If the search directory does not exist or cannot be read
 * @public
 */
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

/**
 * Converts documented and total counts to an integer percentage.
 *
 * @param total - Total declarations
 * @param documented - Documented declarations
 * @returns A floor-rounded percentage, or 100 for an empty category
 * @public
 */
export function pct(total: number, documented: number): number {
  return total === 0 ? 100 : Math.floor((documented * 100) / total);
}

/**
 * Collapses per-category counts into one coverage summary.
 *
 * @param counts - Counts grouped by declaration category
 * @returns Aggregate documented and total counts with percentage
 * @public
 */
export function summarize(counts: Counts): Count & { percent: number } {
  const total = buckets.reduce((sum, bucket) => sum + counts[bucket].total, 0);
  const documented = buckets.reduce(
    (sum, bucket) => sum + counts[bucket].documented,
    0,
  );

  return { total, documented, percent: pct(total, documented) };
}

/**
 * Assigns a source path to its reporting subsystem.
 *
 * @param path - Objective-C header path
 * @returns The matching subsystem, or `Other` when no mapping applies
 * @public
 */
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

/**
 * Classifies a repository document by location and filename.
 *
 * @param path - Repository-relative documentation path
 * @returns A canonical, archive, entrypoint, or internal-reference label
 * @public
 */
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

/**
 * Infers the owning documentation domain for a repository path.
 *
 * @param path - Repository-relative path
 * @returns Owner label used by generated documentation metadata
 * @public
 */
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

/**
 * Maps a document classification to its lifecycle status.
 *
 * @param classification - Value returned by {@link classifyDoc}
 * @returns `active`, `archived`, or `reference`
 * @public
 */
export function inferStatus(classification: string): string {
  if (classification === "canonical" || classification === "entrypoint") {
    return "active";
  }
  if (classification === "archive") return "archived";
  return "reference";
}

/**
 * Selects the canonical documentation page for a non-canonical file.
 *
 * @param path - Repository-relative documentation path
 * @param classification - Classification returned by {@link classifyDoc}
 * @returns Repository-relative canonical target
 * @public
 */
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

/**
 * Creates zeroed coverage aggregates for every source subsystem.
 *
 * @returns Mutable subsystem report entries
 * @public
 */
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

/**
 * Prints a formatted category and overall coverage table.
 *
 * @param title - Heading displayed above the table
 * @param counts - Counts grouped by declaration category
 * @param filesAnalyzed - Optional number of scanned headers
 * @public
 */
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

/**
 * Prints headers that contain undocumented declarations.
 *
 * @param files - Per-header coverage reports
 * @public
 */
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

/**
 * Prints the complete human-readable HeaderDoc coverage report.
 *
 * @param report - Coverage result to render
 * @public
 */
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

/**
 * Scans configured source roots and builds a HeaderDoc coverage report.
 *
 * @param options - Search roots, grouping, output, and threshold options
 * @returns Coverage totals and optional file or subsystem details
 * @public
 */
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

/**
 * Parses HeaderDoc coverage command-line arguments.
 *
 * @param args - Command-line arguments excluding the executable name
 * @param defaultSearchDir - Search root used when no positional path is given
 * @returns Validated coverage options
 * @throws If an option is unknown, incomplete, or outside its valid range
 * @public
 */
export function parseArgs(
  args: string[],
  defaultSearchDir = "Garazyk/Sources",
): Options {
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

/**
 * Runs the HeaderDoc coverage CLI.
 *
 * @remarks
 * Exits with status 1 when a configured threshold fails and status 2 for
 * invalid arguments or scan errors.
 *
 * @returns A promise that resolves after report generation
 * @public
 */
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
