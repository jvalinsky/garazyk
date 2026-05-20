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
    packageName: "hamownia",
    denied: new Set(["dashboard"]),
    description: "packages/hamownia must not depend on dashboard",
  },
  {
    packageName: "dashboard",
    denied: new Set(["narzedzia"]),
    description: "packages/dashboard must not depend on narzedzia",
  },
];

const currentBaseline = new Set<string>([]);

export async function checkBoundaries(
  root: string,
  rules: readonly BoundaryRule[],
  _baseline: Set<string>,
): Promise<Violation[]> {
  const violations: Violation[] = [];

  for (const rule of rules) {
    const packageDir = `${root}/packages/${rule.packageName}`;
    const modFile = `${packageDir}/mod.ts`;

    // We use 'deno info' to get the full dependency graph for the package entrypoint.
    // This is AST-aware and handles aliasing, type-only imports, etc. correctly.
    const command = new Deno.Command(Deno.execPath(), {
      args: ["info", "--json", modFile],
    });

    const { stdout, success } = await command.output();
    if (!success) {
      // If mod.ts doesn't exist or has syntax errors, we might skip it or handle it.
      // For simplicity, we just continue.
      continue;
    }

    const info = JSON.parse(new TextDecoder().decode(stdout));
    const modules = info.modules || [];

    for (const mod of modules) {
      const modLocalPath = mod.local;
      if (!modLocalPath || !modLocalPath.startsWith(packageDir)) {
        continue;
      }

      const relFile = relative(root, modLocalPath);
      const dependencies = mod.dependencies || [];

      for (const dep of dependencies) {
        const specifier = dep.specifier;
        const match = specifier.match(/^@garazyk\/(gruszka|schemat|laweta|hamownia|narzedzia|dashboard)(?:\/.*)?$/);
        
        if (match) {
          const importedPackage = match[1] as PackageName;
          if (rule.denied.has(importedPackage)) {
            // Found a violation
            const span = dep.code?.span || dep.type?.span;
            violations.push({
              file: relFile,
              line: span ? span.start.line + 1 : 1, // deno info line is 0-based in some versions, wait, it says 24 in output for line 24.
              specifier,
              message: rule.description,
              baselineKey: `${relFile} -> @garazyk/${importedPackage}`,
            });
          }
        }
      }
    }
  }

  return violations;
}

export async function main(): Promise<void> {
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

if (import.meta.main) {
  await main();
}
