# narzedzia package research findings

## 1) Module boundary enforcement

The strongest pattern across boundary-enforcement tools is not regex-only import scanning, but rule-based analysis over a parsed dependency graph. Sheriff, Nx’s `enforce-module-boundaries`, eslint-plugin-boundaries, and dependency-cruiser all rely on parsed module references plus resolver-aware rules so they can distinguish package boundaries, aliases, deep imports, and type-only dependencies. Madge is useful too, but it is primarily a visualization and cycle-detection tool rather than a policy engine; it helps explain the graph, while the other tools actively fail builds when boundaries are violated.

A recurring best practice is to define a package’s public API explicitly, usually via `index.ts`/barrel files, and then enforce that consumers stay on those boundaries. Tools also tend to support richer dependency categories than plain `import` strings: type-only imports, re-exports, dynamic imports, and alias-based resolution are all treated as first-class concerns. That matters because boundary rules often need to distinguish “legal type dependency” from “illegal runtime dependency,” or “public import” from “deep import.”

**Code review implication for narzedzia:** if the checker is only using regex over text, it should be treated as a stopgap. For a repository-level boundary tool, parser-backed analysis is the safer default, especially when the codebase uses aliases, barrels, type-only imports, or mixed TS/JS patterns.

## 2) Import regex vs AST

The search results were consistent: regex can be fast, but AST- or lexer-backed approaches are much more reliable for static analysis. Tools such as TypeScript’s own services, dependency-cruiser, Madge’s underlying detectors, and es-module-lexer style parsers can identify static imports, dynamic imports, re-exports, `import type`, and CommonJS `require()` forms much more accurately than text matching. They also avoid false positives from comments, string literals, or multiline syntax.

TypeScript-specific import syntax is a major source of edge cases. `import type { X } from '...'` is a real import form, but it has different runtime semantics from a normal `import`. Likewise, re-exports (`export { X } from '...'`, `export type { X } from '...'`) are often part of the dependency surface. Tools that ignore those forms will undercount dependencies or misclassify them. Dynamic imports are especially tricky: many tools only treat them as valid when the specifier is a constant string literal, and anything more complex becomes “unknown” or must be handled separately.

**Code review implication for narzedzia:** a regex like `importPattern` is likely to miss or mis-handle:
- dynamic `import()` expressions that are not a single literal,
- `require()` and `import.meta.resolve()`-style resolution paths,
- re-exports,
- type-only imports if the alternation is fragile,
- and any syntactic variation outside the expected formatting.
If boundary correctness matters, AST-backed parsing is the better approach. If regex is kept for performance, it should be a prefilter only, not the source of truth.

## 3) Documentation coverage tooling

Modern documentation-coverage tools measure more than “does a file have comments.” TypeDoc plugins and API Extractor/TSDoc workflows usually report coverage over the public API surface, respect a configuration such as `requiredToBeDocumented`, and provide machine-readable output plus thresholds for CI. Useful metrics are per-symbol coverage, per-file or per-folder grouping, and “missing documentation” lists that point directly to the undocumented API surface. TSDoc also adds value by validating tag definitions and surfacing unsupported or misspelled tags.

The important distinction is that documentation coverage is usually model-based, not line-based. The best tools use the TypeScript program or API model to understand declarations, signatures, and symbol visibility, then decide what should count toward coverage. That makes coverage stable even when code formatting changes, and it gives meaningful outputs for public API review. Regex scanning can be useful for a narrow header check, but it is not a good foundation for TSDoc coverage metrics.

**Code review implication for narzedzia:** the current approach sounds incomplete if it relies on regex heuristics, especially for things like `doc_coverage.ts` and `doc_validator.ts`. The stubs returning `false` are a clear red flag, and any “coverage” metric based on text scanning will drift as formatting changes. Coverage should ideally be derived from a structured parser or API model, with JSON output and thresholds that CI can enforce.

## 4) SPDX license header automation

The SPDX/header-checking ecosystem is fairly mature. Common patterns include CI check mode, auto-fix mode, explicit allowlists of accepted SPDX identifiers, file-type-specific comment handling, and skipping generated/vendor/docs content. Tools like addlicense, copywrite, enarx/spdx, eslint-plugin-license-header, and check-spdx-headers all converge on the same model: detect language, validate the top-of-file license block, and fail the build if it is missing or malformed. Some tools also support updating existing headers in place, but they usually separate “check” from “rewrite” so CI can stay non-destructive.

Best practice is to avoid assuming one regex or one comment style fits every file. Language detection by extension or shebang is common, and tools usually exclude JSON, generated code, and vendored trees. For SPDX specifically, the more standard the header format, the easier it is to maintain compliance and keep false positives low.

**Code review implication for narzedzia:** a header checker based on simple heuristics can be acceptable if it is narrow and well-scoped, but it should be conservative about supported file types and should not mutate files unless explicitly running in a fix mode. If the current implementation rewrites files in place, that logic should be isolated and gated. If it only checks a small subset of files, it should document that scope clearly.

## Review Checklist

| Concern | What the research suggests | Review action |
|---|---|---|
| `importPattern` regex handles `import type { X } from '...'` | Boundary tools usually distinguish type-only imports explicitly and rely on AST/resolver data | Verify the regex cannot misclassify type-only imports; prefer AST-based parsing if boundary correctness matters |
| `importPattern` does not handle `require()` or `import.meta.resolve()` | Real-world dependency tools track CommonJS, dynamic imports, and special resolution forms separately | Add explicit support if these forms matter, or document them as intentionally unsupported |
| Dynamic `import()` only partially handled | Most tools treat dynamic imports as a separate dependency type and only parse literal constants reliably | Decide whether non-literal dynamic imports should be ignored, flagged, or resolved via a parser |
| `walkTypeScriptFiles()` sorts entries, but `Deno.readDir` is OS-dependent | Deterministic traversal is a known best practice for stable reports | Keep the sort; add tests that prove report ordering stays stable across runs |
| `currentBaseline` is hardcoded as empty set | Coverage/boundary tools usually support persisted baselines or config-driven thresholds | Load the baseline from a file or config so the checker can detect regressions instead of always comparing to zero |
| No `deno.json` exports for `doc_validator.ts` | Unexported tooling code becomes dead code unless it is invoked indirectly | Either expose it as a CLI/module entrypoint or remove it if unused |
| `doc_coverage.ts` uses heuristic regex scanning for ObjC headers | Coverage metrics should be model-based; text heuristics drift with formatting | Replace or supplement with structured parsing; add fixture coverage for weird formatting and multiline comments |
| `doc_validator.ts` stubs return `false` | Stubs in validator paths make the tool incomplete by definition | Implement or remove the stubs; if temporary, gate them behind explicit “not implemented” errors |
| `repo_docs.ts` uses regex markdown parsing, HEAD-only external checks, in-place mutation | Markdown and links are best handled with parsers; mutation should be opt-in and dry-run capable | Move to parser-based markdown handling, avoid HEAD-only assumptions where possible, and add a dry-run mode before mutation |
| `tsdoc_coverage.ts` shells out `deno doc --json` per source file | Coverage tools often use a shared program/model to avoid repeated work | Cache results or build once per package instead of per file; measure and cap runtime in CI |
| `ops_command.ts` is security-sensitive (path sanitization, DID validation, SQL generation, Cloudflare API calls) | Security-focused tools rely on allowlists, structured validation, and parameterized operations | Treat this as a hardening hotspot: validate inputs strictly, parameterize SQL, sanitize paths, and avoid free-form command construction |
| `vitepress_migration.ts` front-matter conversion only writes when `layout:` is removed; link regex can rewrite code samples | Source-to-source tools should parse structured markdown/MDX, not rewrite with broad regex | Use a markdown AST or front-matter parser, and ensure code fences/inline code are excluded from link rewrites |

## Cross-Cutting Concerns

- **Parser-first beats regex-first for repository tooling.** Across boundary checks, doc coverage, and markdown migration, the safer pattern is to parse the underlying structure and then apply rules.
- **Keep check and fix paths separate.** SPDX/header tooling and doc migration tools should support non-destructive validation independently from rewrite mode.
- **Persist baselines and thresholds.** Coverage and boundary tools are most useful when they can compare against a file-backed baseline rather than a hardcoded empty set.
- **Make output deterministic.** Stable traversal order, stable sort keys, and JSON output matter for CI diffs and reproducibility.
- **Treat security-sensitive commands differently.** Anything that touches paths, SQL, network APIs, or shell commands should get stricter validation than ordinary static analysis.
- **Document unsupported syntax explicitly.** If narzedzia intentionally skips `require()`, `import.meta.resolve()`, code-fence links, or unusual header formats, that should be a conscious contract, not an accidental gap.
- **Watch package boundaries beyond narzedzia.** The same parser-vs-regex and check-vs-fix lessons apply to other repository tools, especially migration scripts and repo-wide validators.
