#!/usr/bin/env -S deno run -A
import { join } from "jsr:@std/path@1";

type Bucket =
  | "classes"
  | "methods"
  | "properties"
  | "enums"
  | "categories"
  | "protocols";
type Counts = Record<Bucket, { total: number; documented: number }>;

const buckets: Bucket[] = [
  "classes",
  "methods",
  "properties",
  "enums",
  "categories",
  "protocols",
];

function emptyCounts(): Counts {
  return Object.fromEntries(
    buckets.map((bucket) => [bucket, { total: 0, documented: 0 }]),
  ) as Counts;
}

function countDocumentation(content: string): Counts {
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
        previous5.includes("/*!")
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

async function* walkHeaders(dir: string): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(dir)) {
    const path = join(dir, entry.name);
    if (path.includes("/Compat/")) continue;
    if (entry.isDirectory) {
      yield* walkHeaders(path);
    } else if (entry.isFile && entry.name.endsWith(".h")) {
      yield path;
    }
  }
}

function pct(total: number, documented: number): number {
  return total === 0 ? 100 : Math.floor((documented * 100) / total);
}

async function main() {
  const searchDir = Deno.args[0] || "Garazyk/Sources";
  const totals = emptyCounts();
  let fileCount = 0;

  for await (const path of walkHeaders(searchDir)) {
    fileCount++;
    let content = "";
    try {
      content = await Deno.readTextFile(path);
    } catch {
      continue;
    }
    const results = countDocumentation(content);
    for (const bucket of buckets) {
      totals[bucket].total += results[bucket].total;
      totals[bucket].documented += results[bucket].documented;
    }
  }

  console.log("\nDOCUMENTATION COVERAGE REPORT");
  console.log("==============================\n");
  for (const bucket of buckets) {
    const { total, documented } = totals[bucket];
    console.log(
      `${bucket.charAt(0).toUpperCase() + bucket.slice(1).padEnd(11)} ${
        String(documented).padStart(5)
      } / ${String(total).padEnd(5)} (${String(pct(total, documented)).padStart(3)}%)`,
    );
  }

  console.log("\n------------------------------");
  const grandTotal = buckets.reduce(
    (sum, bucket) => sum + totals[bucket].total,
    0,
  );
  const grandDoc = buckets.reduce(
    (sum, bucket) => sum + totals[bucket].documented,
    0,
  );
  const overall = pct(grandTotal, grandDoc);
  console.log(
    `${"OVERALL".padEnd(12)} ${String(grandDoc).padStart(5)} / ${String(grandTotal).padEnd(5)} (${
      String(overall).padStart(3)
    }%)`,
  );
  console.log(`\nFiles analyzed: ${fileCount}\n`);

  if (overall >= 90) {
    console.log("[PASS] Coverage >= 90%");
  } else if (overall >= 70) {
    console.log("[WARN] Coverage < 90%");
  } else {
    console.log("[FAIL] Coverage < 70%");
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
