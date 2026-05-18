# Verification Log

## Phase 0 Baseline

- `git status --short`: working tree had unrelated changes (`.letta/`, `.claude/`, `.agents/skills/atproto-*`, etc.) — all pre-existing, left untouched.
- `deno task boundaries`: passed (2 known baseline violations).
- `deno check packages/*/mod.ts scripts/*.ts`: passed.
- `deno task dashboard:check`: passed.

## Phase 1 — Gruszka Generated Contract and Binary Routing

**Files changed:**
- `packages/gruszka/scripts/generate.ts` — added `inputEncoding`, `outputEncoding`, `isBinaryEncoding`, `LEXICON_METHOD_INPUT_ENCODINGS`, `LEXICON_METHOD_OUTPUT_ENCODINGS`, `BinaryXrpcResponse`, and encoding-aware helper types.
- `packages/gruszka/lexicons.ts` — regenerated (446 lexicons) with encoding fields, `BinaryXrpcResponse`, and exact type contracts.
- `packages/gruszka/generated_types.ts` — replaced loose `any`/`string` shims with re-exports from `lexicons.ts`.
- `packages/gruszka/client.ts` — `XrpcClient.query()` and `.procedure()` add overloads; `createAgentProxy` and `createGeneratedClient` route binary endpoints through `getBinary`/`postBinary`.
- `packages/gruszka/clients/raw.ts` — `RawClient.query()` and `.procedure()` auto-dispatch binary methods; added `postBinary()` helper wrapper.
- `packages/gruszka/scripts/generate_test.ts` — added test for binary encoding preservation.
- `packages/gruszka/client_test.ts` — added binary dispatch routing test; updated existing tests with `contentType` and `bodyIsBinary` fields.
- `packages/gruszka/generated_types_test.ts` — new file with type-negative tests using `@ts-expect-error` for bad NSIDs, missing params, wrong shapes.

**Public API changes:**
- `generated_types.ts` now re-exports exact types from `lexicons.ts` (no loose `any`/`string` shims).
- `BinaryXrpcResponse` exposed as `[status: number, contentType: string, data: Uint8Array]`.
- `LEXICON_METHOD_INPUT_ENCODINGS` and `LEXICON_METHOD_OUTPUT_ENCODINGS` constants available.
- New encoding metadata fields on `LexiconQuery` and `LexiconProcedure`.

**Tests run:**
- `deno test -A packages/gruszka/scripts/generate_test.ts` — 6/6 passed.
- `deno test -A packages/gruszka/client_test.ts` — 3/3 passed.

**Blockers:** None.

## Phase 2 — Firehose Frame Decoding

**Files changed:**
- `packages/gruszka/firehose.ts` — added `parseFirehoseFrame()` (two concatenated DAG-CBOR objects), `firehoseEventFromFrame()`, `FirehoseFrameHeader`, `FirehoseFrameBody`, `FirehoseFrame`, `FirehoseFrameParseError`; updated `FirehoseEvent` with `header`/`body` fields; legacy `payload` preserved as raw `Uint8Array`.
- `packages/gruszka/firehose_test.ts` — new file: 4 tests for normal commit, error frame, malformed, trailing bytes.
- `scripts/scenarios/scenarios/09_firehose_streaming.ts` — added firehose frame decoding assertion step; removed `any` casts.
- `scripts/scenarios/scenarios/63_firehose_cursor_recovery.ts` — added decoded frame assertions in baseline, resubscribe, and cursor recovery phases; removed `any` casts.
- `deno.json` — added `cborg` import (`npm:cborg@5.1.1`).

**Tests run:**
- `deno test -A packages/gruszka/firehose_test.ts` — 4/4 passed.
- `deno check packages/gruszka/mod.ts scripts/scenarios/scenarios/09_firehose_streaming.ts scripts/scenarios/scenarios/63_firehose_cursor_recovery.ts` — passed.

**Blockers:** None.

## Phase 3 — Dashboard Report Import Validation

**Files changed:**
- `packages/dashboard/services/report_scanner.ts` — added Zod v3 schema for `ReportFile` with `nonNegativeInteger`, `nonNegativeNumber` refinements; `readRunReportFile()` helper with `safeParse` and per-file diagnostic logging; `scanReports()` uses shared helper; `importRunReports()` validates all files before opening DB transaction.
- `packages/dashboard/services/report_scanner_test.ts` — new file: 2 tests for invalid file skipping and validated-only import.

**Tests run:**
- `deno test -A packages/dashboard/services/report_scanner_test.ts` — 2/2 passed.
- `deno task dashboard:check` — passed.

**Blockers:** None.

## Final Integration

- `deno task boundaries` — passed (2 known baseline violations).
- `deno check packages/*/mod.ts scripts/run_scenarios.ts` — passed.
- `deno task dashboard:check` — passed.
- `deno fmt packages/ scripts/changed-files` — lexicons.ts reformatted; all changed files clean.
- `deno test -A packages/gruszka packages/dashboard packages/schemat packages/hamownia/*test.ts` — 291 passed, 1 failed.

**Note on `tui_test.ts` failure:** The single failing test (`renderTuiFrame includes scenario and run summaries`) is a pre-existing issue from `packages/dashboard/db/index.ts:28-35` — `scanReports()` is called via `setTimeout` at module init, creating an async operation that completes during test execution. This leak existed before our changes but was timing-dependent. It is unrelated to the 4 findings.

**Scenario verification (requires local stack):**
```sh
deno run -A scripts/run_scenarios.ts 09
deno run -A scripts/run_scenarios.ts 63
```
