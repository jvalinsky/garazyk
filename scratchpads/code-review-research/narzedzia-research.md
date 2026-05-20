# Narzedzia: Boundary Checker, Static Analysis, Doc Coverage — Research Plan

## Package Summary
Repository-level static analysis and codegen tooling. Includes boundary checker, doc coverage, TSDoc coverage, SPDX header checks, and VitePress migration tools.

## Key Techniques
1. **Module boundary enforcement** — Regex-based import analysis with configurable deny rules
2. **Baseline violation tracking** — `currentBaseline` set for known violations
3. **Binary search line lookup** — `lineForOffset()` for mapping regex match to line number
4. **Doc coverage analysis** — `doc_coverage.ts` measures documentation completeness
5. **TSDoc coverage analysis** — `tsdoc_coverage.ts` measures TSDoc annotation completeness
6. **SPDX license header checking** — `spdx_headers.ts` validates license headers
7. **Repo documentation generation** — `repo_docs.ts` generates documentation from source
8. **VitePress migration** — `vitepress_migration.ts` for docs site migration

## Research Queries (for sub-agents)

### Q1: Module boundary enforcement in TypeScript monorepos
- Search: "TypeScript monorepo module boundary enforcement tools"
- Search: "monorepo package dependency constraints static analysis"
- Search: "Sheriff TSLint boundary rules TypeScript monorepo"
- Focus: How do other tools enforce package boundaries? Is regex-based import analysis sufficient or are there better approaches (AST-based)?

### Q2: Import regex vs AST analysis tradeoffs
- Search: "regex import analysis vs AST TypeScript static analysis"
- Search: "TypeScript import specifier extraction regex limitations"
- Focus: The current regex `importPattern` — does it miss dynamic imports? Type-only imports? Re-exports? `import.type()`?

### Q3: Doc coverage metrics and tooling
- Search: "TypeScript documentation coverage metrics tools"
- Search: "TSDoc coverage analysis tool comparison"
- Focus: How do other tools measure doc coverage? What metrics are useful? Is the narzedzia approach complete?

### Q4: SPDX license header automation
- Search: "SPDX license header checking automation tools"
- Search: "license header linting best practices open source"
- Focus: Best practices for automated license header checking — is the narzedzia approach standard?

### Q5: Binary search for line number mapping
- Search: "source code line number from character offset binary search"
- Focus: The `lineForOffset()` implementation — is it correct? Edge cases with CRLF, BOM, empty files?

## Additional Code Review Concerns (from deep survey)
- `doc_coverage.ts` uses heuristic regex scanning for ObjC headers — counts can drift with unusual formatting
- `doc_validator.ts` `validateDocDiagrams()` and `checkDocPatterns()` are stubs returning `false` — `docValidationMain()` will exit non-zero
- `repo_docs.ts` regex-based markdown parsing, HEAD-only external checks, in-place doc mutation, silent dropping of missing files
- `tsdoc_coverage.ts` shells out `deno doc --json` per source file — performance concern; depends on JSON shape stability
- `spdx_headers.ts` only scans `.h`, `.m`, `.c` — skips other file types; treats any file with SPDX identifier as done
- `ops_command.ts` security-sensitive: path sanitization, DID validation, SQL generation, Cloudflare API calls; `runBackup` doesn't inspect tar exit code; `validateDid()` may be stricter than full `did:web` space
- `vitepress_migration.ts` front-matter conversion only writes when `layout:` removed; link regex can rewrite code samples; assumes LF formatting
- `cli/ops.ts` casts Cliffy option objects back to typed shapes — bypasses type safety

## Code Review Concerns to Investigate
- `importPattern` regex — does it handle `import type { X } from "..."` correctly? The pattern has `type\s+` but it's inside an alternation
- `importPattern` doesn't handle `require()` or `import.meta.resolve()`
- Dynamic `import()` is only partially handled — the regex expects a single string literal
- `walkTypeScriptFiles()` sorts entries for determinism — good, but `Deno.readDir` order is OS-dependent
- `currentBaseline` is hardcoded as empty set — should it be loaded from a file?
- No `deno.json` exports for `doc_validator.ts` — dead code?
- `ops_command.ts` — what does it do? Is it documented?
- `vitepress_migration.ts` — is this still needed or is it a one-time migration tool?

## Deciduous Link
- Node 285: narzedzia action
