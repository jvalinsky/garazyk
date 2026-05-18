#!/usr/bin/env -S deno run --allow-read

import { relative } from "@std/path";

export type PackageName =
  | "gruszka"
  | "schemat"
  | "laweta"
  | "hamownia"
  | "narzedzia"
  | "dashboard";

export interface BoundaryRule {
  readonly packageName: PackageName;
  readonly denied: ReadonlySet<PackageName>;
  readonly description: string;
}

export interface Violation {
  readonly file: string;
  readonly line: number;
  readonly specifier: string;
  readonly message: string;
  readonly baselineKey: string;
}

const root = Deno.args[0] ?? Deno.cwd();

const rules: readonly BoundaryRule[] = [
  {
    packageName: "gruszka",
    denied: new Set([
      "gruszka",
      "schemat",
      "laweta",
      "hamownia",
      "narzedzia",
      "dashboard",
    ]),
    description: "packages/gruszka must remain standalone",
  },
  {
    packageName: "schemat",
    denied: new Set(["laweta", "hamownia", "narzedzia", "dashboard"]),
    description:
      "packages/schemat must not depend on laweta, hamownia, narzedzia or dashboard",
  },
  {
    packageName: "laweta",
    denied: new Set(["schemat", "hamownia", "narzedzia", "dashboard"]),
    description:
      "packages/laweta must not depend on schemat, hamownia, narzedzia or dashboard",
  },
  {
    packageName: "narzedzia",
    denied: new Set(["hamownia", "laweta", "dashboard"]),
    description:
      "packages/narzedzia must not depend on hamownia, laweta, or dashboard",
  },
  {
    packageName: "dashboard",
    denied: new Set(["narzedzia"]),
    description: "packages/dashboard must not depend on narzedzia",
  },
];

const currentBaseline = new Set<string>([]);

const importPattern =
  /\b(?:import|export)\s+(?:type\s+)?(?:[^"']*?\s+from\s+)?["'](@garazyk\/(gruszka|schemat|laweta|hamownia|narzedzia|dashboard)(?:\/[^"']*)?)["']|\bimport\s*\(\s*["'](@garazyk\/(gruszka|schemat|laweta|hamownia|narzedzia|dashboard)(?:\/[^"']*)?)["']\s*\)/g;

export async function checkBoundaries(
  root: string,
  rules: readonly BoundaryRule[],
  baseline: Set<string>,
): Promise<Violation[]> {
  const violations: Violation[] = [];

  for (const rule of rules) {
    const packageDir = `${root}/packages/${rule.packageName}`;
    for await (const file of walkTypeScriptFiles(packageDir)) {
      const text = await Deno.readTextFile(file);
      const lineStarts = lineStartOffsets(text);

      for (const match of text.matchAll(importPattern)) {
        const specifier = match[1] ?? match[3];
        const importedPackage = (match[2] ?? match[4]) as PackageName;
        if (!rule.denied.has(importedPackage)) {
          continue;
        }

        const relFile = relative(root, file);
        violations.push({
          file: relFile,
          line: lineForOffset(lineStarts, match.index ?? 0),
          specifier,
          message: rule.description,
          baselineKey: `${relFile} -> @garazyk/${importedPackage}`,
        });
      }
    }
  }

  return violations;
}

export async function main() {
  const violations = await checkBoundaries(root, rules, currentBaseline);
  const newViolations = violations.filter((violation) =>
    !currentBaseline.has(violation.baselineKey)
  );
  const staleBaseline = [...currentBaseline].filter((key) =>
    !violations.some((violation) => violation.baselineKey === key)
  );

  if (newViolations.length > 0) {
    console.error("Module boundary check failed with new violation(s):");
    for (const violation of newViolations) {
      console.error(
        `${violation.file}:${violation.line}: ${violation.specifier} (${violation.message})`,
      );
    }
  }

  if (staleBaseline.length > 0) {
    console.error("Module boundary baseline contains resolved violation(s):");
    for (const key of staleBaseline) {
      console.error(`  ${key}`);
    }
    console.error("Remove resolved entries from currentBaseline.");
  }

  if (newViolations.length > 0 || staleBaseline.length > 0) {
    Deno.exit(1);
  }

  const knownCount = violations.length;
  if (knownCount === 0) {
    console.log("Module boundary checks passed.");
  } else {
    console.log(
      `Module boundary checks passed with ${knownCount} known baseline violation(s).`,
    );
  }
}

export async function* walkTypeScriptFiles(
  dir: string,
): AsyncGenerator<string> {
  let entries: Deno.DirEntry[];
  try {
    entries = [];
    for await (const entry of Deno.readDir(dir)) {
      entries.push(entry);
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return;
    }
    throw error;
  }

  entries.sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory) {
      yield* walkTypeScriptFiles(path);
    } else if (entry.isFile && path.endsWith(".ts")) {
      yield path;
    }
  }
}

export function lineStartOffsets(text: string): number[] {
  const starts = [0];
  for (let i = 0; i < text.length; i += 1) {
    if (text.charCodeAt(i) === 10) {
      starts.push(i + 1);
    }
  }
  return starts;
}

export function lineForOffset(
  starts: readonly number[],
  offset: number,
): number {
  let low = 0;
  let high = starts.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (starts[mid] <= offset) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return high + 1;
}

if (import.meta.main) {
  await main();
}
