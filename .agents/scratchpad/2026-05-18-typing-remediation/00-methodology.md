# Typing Remediation Methodology

## Goal
Eliminate all `any`, `Promise<any>`, `as any`, and missing return types across
JSR-published Garazyk packages (gruszka, narzedzia, hamownia, schemat).

## Scoring Criteria
- **HIGH**: causes real bugs (exit code loss, unchecked runtime casts, intersection narrowing)
- **MEDIUM**: blocks type-level safety but currently works; would fail stricter lint rules
- **LOW**: idiom-safe usage (test mocks, generic dispatch, ATProto open unions)

## Approach per package
| Package | Strategy |
|---------|----------|
| narzedzia | Mechanical: add `: Promise<void>` to all CLI `*Main` exports, fix exit code |
| hamownia | OTel type imports + missing return annotations + remove `Record<string, any>` |
| gruszka | Pointer: `QueryOutput<>`/`ProcedureOutput<>` for search/contact clients, fix `as any` in seed, tighten `raw.ts` fallbacks, fix lexicon generator |
| schemat | Define intermediate Docker compose interfaces |

## Verification
```bash
deno check packages/*/mod.ts
deno publish --dry-run --allow-dirty
```

## Priority ordering
1. narzedzia (fastest ROI, 30min)
2. hamownia otel.ts (highest bug density, type imports available)
3. gruszka search/contact.ts (highest value per-file)
4. gruszka seed.ts as any bug
5. gruszka raw.ts tightening
6. gruszka lexicon generator unresolved refs
7. schemat topology_compiler.ts
