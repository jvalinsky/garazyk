---
name: garazyk-narzedzia
description: Dev tools for the Garazyk monorepo — boundary checking, doc/TSDoc coverage, SPDX license headers, repo docs automation, and ops commands. Use when checking package import boundaries, auditing API documentation coverage, adding or verifying SPDX headers, generating repo docs, or running operational tasks (backup, DNS, PDS setup).
---

# Narzedzia — Dev Tools

`@garazyk/narzedzia` provides build-time and CI tooling for the Garazyk monorepo. Boundary rules: narzedzia must NOT import from hamownia, laweta, or dashboard.

## When to Use

- Enforce package import boundaries between monorepo packages
- Audit TSDoc or doc-coverage across the codebase
- Add or verify SPDX license headers on source files
- Generate or validate repo documentation (markdown, index pages, link checking)
- Run operational commands (Cloudflare DNS, PDS setup, config validation, backup)

## Quick Start

```ts
// Boundary checking
import { checkBoundaries } from "@garazyk/narzedzia";
const violations = checkBoundaries();

// TSDoc coverage
import { buildTsdocCoverageReport, printTsdocCoverageReport } from "@garazyk/narzedzia";
const report = buildTsdocCoverageReport("./packages");
printTsdocCoverageReport(report);

// SPDX headers
import { addSpdxHeader, hasSpdx } from "@garazyk/narzedzia";
if (!hasSpdx(content)) await addSpdxHeader(filePath, header);

// Repo docs
import { analyzeLinks, generateIndexPages } from "@garazyk/narzedzia";
const analysis = analyzeLinks(docs);
```

Subpath imports for focused usage:

```ts
import { checkBoundaries } from "@garazyk/narzedzia/boundary-check";
import { buildTsdocCoverageReport } from "@garazyk/narzedzia/tsdoc-coverage";
import { repoDocsMain } from "@garazyk/narzedzia/repo-docs";
import { addSpdxHeader } from "@garazyk/narzedzia/spdx-headers";
import { runBackup } from "@garazyk/narzedzia/ops-command";
```

## API Reference

### Boundary Checking

| Export | Type | Description |
|--------|------|-------------|
| `checkBoundaries()` | `() => Violation[]` | Check all package import boundaries |
| `boundaryCheckMain()` | `() => Promise<void>` | CLI entry point |
| `BoundaryRule` | type | `{ from: PackageName, allowed: PackageName[] }` |
| `PackageName` | type | String union of package names |
| `Violation` | type | `{ from, to, file, importPath }` |

### Doc / TSDoc Coverage

| Export | Type | Description |
|--------|------|-------------|
| `buildTsdocCoverageReport(dir)` | `(string) => CoverageReport` | Build coverage report for source dir |
| `collectSourceFiles(dir)` | `(string) => ...` | Collect source files for analysis |
| `printTsdocCoverageReport(report)` | `(CoverageReport) => void` | Print formatted coverage output |
| `tsdocCoverageMain()` | `() => Promise<void>` | CLI entry point |
| `loadDocJson(path)` | `(string) => ...` | Load a doc.json file |

### Repo Docs

| Export | Type | Description |
|--------|------|-------------|
| `repoDocsMain()` | `() => Promise<void>` | CLI entry point |
| `analyzeLinks(docs)` | `(docs) => LinkAnalysis` | Analyze internal/external links |
| `buildRegistry(docs)` | `(docs) => DocRecord[]` | Build document registry |
| `checkExternalLinks(records)` | `(DocRecord[]) => ExternalLinkReport` | Validate external links |
| `generateIndexPages(paths)` | `(RepoDocsPaths) => void` | Generate index pages |
| `discoverMarkdownFiles(dir)` | `(string) => ...` | Find markdown files recursively |
| `walkMarkdown(path)` | `(string) => ...` | Parse markdown frontmatter + links |
| `computeOrphans(registry)` | `(DocRecord[]) => OrphanAnalysis` | Find orphaned docs |

### SPDX Headers

| Export | Type | Description |
|--------|------|-------------|
| `addSpdxHeader(filePath, header)` | `(string, string) => Promise<void>` | Add license header to file |
| `hasSpdx(content)` | `(string) => boolean` | Check if content has SPDX header |
| `spdxHeadersMain()` | `() => Promise<void>` | CLI entry point |
| `processSpdxFile(filePath)` | `(string) => Promise<void>` | Process single file |
| `walkSpdx(dir)` | `(string) => ...` | Walk directory for SPDX processing |

### Ops Commands

| Export | Type | Description |
|--------|------|-------------|
| `CloudflareClient` | class | Cloudflare API client |
| `runBackup(opts)` | `(BackupOptions) => Promise<void>` | Run backup operation |
| `runBackfill(opts)` | `(BackfillOptions) => Promise<void>` | Run backfill operation |
| `runDnsAdd(opts)` | `(DnsAddOptions) => Promise<void>` | Add DNS record via Cloudflare |
| `runSetupPds(opts)` | `(SetupPdsOptions) => Promise<void>` | Set up a PDS instance |
| `runValidateConfig(opts)` | `(ValidateConfigOptions) => Promise<void>` | Validate PDS config |

### Vitepress Migration

| Export | Type | Description |
|--------|------|-------------|
| `MigrationTool` | class | Migrate docs to Vitepress format |
| `vitepressMigrationMain()` | `() => Promise<void>` | CLI entry point |

## Key Patterns

### Run boundary check (most common)

```bash
deno run -A packages/narzedzia/boundary_check.ts
```

Programmatic:

```ts
import { checkBoundaries } from "@garazyk/narzedzia";
const violations = checkBoundaries();
for (const v of violations) {
  console.error(`${v.from} -> ${v.to}: ${v.importPath} in ${v.file}`);
}
```

### Check TSDoc coverage

```bash
deno run -A packages/narzedzia/tsdoc_coverage.ts
```

Programmatic:

```ts
import { buildTsdocCoverageReport, printTsdocCoverageReport } from "@garazyk/narzedzia";
const report = buildTsdocCoverageReport("./packages/tui");
printTsdocCoverageReport(report);
```

### Add SPDX headers

```bash
deno run -A packages/narzedzia/spdx_headers.ts
```

Programmatic:

```ts
import { hasSpdx, processSpdxFile } from "@garazyk/narzedzia";
const content = Deno.readTextFileSync(filePath);
if (!hasSpdx(content)) {
  await processSpdxFile(filePath);
}
```

## Related Skills

- **garazyk-laweta** — Docker infrastructure (boundary rule: narzedzia must not import laweta)
- **garazyk-hamownia** — Scenario orchestration (boundary rule: narzedzia must not import hamownia)
- **tsdoc-standards** — TSDoc writing conventions
