# Typing Remediation Results

## Goal Status: COMPLETED

All 6 packages pass `deno check` and `deno publish --dry-run` with zero
slow-type errors. Only the pre-existing warning (unanalyzable-dynamic-import in
hamownia/host_child_runner.ts) remains.

## Changes by Package

### @garazyk/narzedzia — 10 fixes
- 7 CLI `*Main` functions: added `: Promise<void>` return type
- `lineStartOffsets`: already had `: number[]` (false positive)
- `scripts/docs/repo_docs.ts:3`: wrapped `repoDocsMain()` with `Deno.exit()`
  to preserve exit code

### @garazyk/hamownia — 7 HIGH, 3 MEDIUM fixes
- `otel.ts`: imported real `Tracer`/`Meter`/`Counter`/`Gauge`/`Span`/`Exception`
  types from `@opentelemetry/api` (type-only imports, no runtime cost).
  Replaced all `any` with proper types. Fixed `SpanStatusCode` semantic bug
  (`code: 0` → `OTEL_STATUS.OK`, where `OK=1` not `0`). Added `SdkProvider`
  interface for `forceFlush()`/`shutdown()`.
- `service_command.ts`: added `: Promise<void>` on `serviceCommandMain`
- `instrumentation.ts`: added `MetricSeriesEntry` type, replaced `Record<string, any>`
  in `getTimeSeries()`, added `: Promise<void>` on `writeJson`

### @garazyk/gruszka — 15 method types, 3 sig fixes
- `search.ts`: 7 methods now return `QueryOutput<>`/`ProcedureOutput<>` generics
- `contact.ts`: 8 methods now return proper typed generics
- `seed.ts:84`: `as any` → `as unknown as ProcedureOutput<"com.atproto.server.createSession">`
- `raw.ts`: fallback overloads `Promise<any>` → `Promise<unknown>`

### @garazyk/schemat — 1 fix
- `topology_compiler.ts`: typed `renderNetworks` `networks` param from `any`
  to `string[] | Record<string, { aliases?: string[] }>`

### Not Done (cancelled)
- Lexicon generator unresolved refs + BlobRef: touches generated code and
  generator, scoped out of this pass

## Assets
- Decision graph: node 128 (goal) → 7 actions, 4 outcomes, 3 decisions
- Beads: 7 tasks created, 6 closed, 1 cancelled
- Scratchpad: `.agents/scratchpad/2026-05-18-typing-remediation/`
