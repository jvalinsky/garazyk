# Findings Inventory

## Finding 1: Root generated types are loose shims

- Evidence: `packages/gruszka/generated_types.ts` exports `LexiconIds`, `LexiconQueryIds`, and `LexiconProcedureIds` as `string`.
- Evidence: `QueryParams` is `Record<string, unknown>`, `ProcedureInput` is `unknown`, and outputs use a dynamic escape hatch.
- Risk: callers can pass invalid NSIDs, missing parameters, and malformed procedure bodies without type feedback.
- Priority: high because this is public API surface.

## Finding 2: Generated binary XRPC methods are not routed by encoding metadata

- Evidence: `packages/gruszka/clients/raw.ts` typed `query()` always calls `transport.get()` and typed `procedure()` always calls `transport.post()`.
- Evidence: `postBinary()` and `xrpcGetBinary()` exist, but generated typed dispatch does not use lexicon input/output `encoding`.
- Risk: CAR/blob methods can accidentally use JSON transport, losing response headers and binary bytes.
- Priority: high because it breaks wire compatibility for encoding-only bodies.

## Finding 3: Firehose frames are not decoded as two DAG-CBOR objects

- Evidence: `packages/gruszka/firehose.ts` calls `cbor.decode(buf)` and then treats the result as `[header, _]`.
- Evidence: parse failures are swallowed, resulting in `seq = 0` and `type = "unknown"`.
- Risk: scenarios can pass while not validating real subscribeRepos frames, cursor ordering, or error frames.
- Priority: high because it hides malformed or incompatible firehose data.

## Finding 4: Dashboard report import trusts parsed JSON

- Evidence: `packages/dashboard/services/report_scanner.ts` parses report files with `JSON.parse(content) as ReportFile`.
- Evidence: numeric counts, timestamps, and durations are inserted into SQLite without runtime validation.
- Risk: malformed files can insert `NaN`, invalid counts, or partial data into historical run records.
- Priority: medium-high because report files are external filesystem inputs.
