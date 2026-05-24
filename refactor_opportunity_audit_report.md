# Refactor Opportunity Audit Report: Mikrus, Beskid, and Syrena

## Review Status

This report is the revised final audit. The initial summary referenced
`refactor_opportunity_audit_report.md`, but that file was not present in the
repo workspace. The original Gemini artifact was later found under
`~/.gemini/antigravity-cli/brain/d517cead-09f6-4f12-a0f4-9015e5a89c3c/`.
That report and the scratchpad notes under
`scratchpads/refactor-audit-2026-05-23/` were reviewed against source files and
corrected where the claims were too broad.

## Executive Summary

The strongest refactor opportunity is the Mikrus/Beskid SQLite query runner.
Both services duplicate the same `ATProtoConnectionManager`-based
prepare/bind/step/finalize flow and transaction wrapper. Extracting that into
`ATProtoDatabaseQueryRunner` gives a clear shared primitive with direct tests
and low service-boundary risk.

The second-highest opportunity is route support plus DID document field
extraction. Mikrus and Beskid duplicate XRPC rate-limit, required-parameter, and
DID document parsing helpers. This should not become a broad all-purpose
`GZXrpcHelper`; it should reuse existing `XrpcErrorHelper`, `RateLimiter`, and
DID-related helpers.

Configuration and CLI parsing are worthwhile, but they should come after the
database and route work. AppView database pooling is explicitly deferred because
it changes concurrency assumptions rather than just removing duplicated
boilerplate.

## Corrected Findings

| Rank | Candidate                               | Recommendation                                                       |
| ---: | --------------------------------------- | -------------------------------------------------------------------- |
|    1 | SQLite query/update/transaction helpers | Extract `ATProtoDatabaseQueryRunner` for Mikrus and Beskid first.    |
|    2 | XRPC route support and DID fields       | Add narrow route helpers and shared DID document field parsing.      |
|    3 | CLI option parsing                      | Add a schema-driven parser after database and route refactors.       |
|    4 | Configuration parsing                   | Add parsing utilities; avoid a base configuration class at first.    |
|    5 | Entrypoint lifecycle setup              | Extract only after preserving Syrena-specific crash/category checks. |
|    6 | AppView connection unification          | Defer; requires a separate concurrency migration.                    |

## Key Evidence

- `Garazyk/Sources/Mikrus/MikrusDatabase.m` and
  `Garazyk/Sources/Beskid/BeskidDatabase.m` duplicate the same SQLite
  query/update/transaction helper structure.
- `Garazyk/Sources/AppView/Server/AppViewDatabase.m` has similar parameterized
  SQL logic but runs through raw `_db`, `safeExecuteSync`, and
  `PDS_SQLITE_AUTORELEASE_STMT`.
- `Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m` and
  `Garazyk/Sources/Beskid/BeskidXrpcRoutePack.m` duplicate IP rate-limit
  responses, required query parameter checks, and DID document field extraction.
- `Garazyk/Sources/Network/XrpcErrorHelper.[hm]`,
  `Garazyk/Sources/Network/RateLimiter.[hm]`, and
  `Garazyk/Sources/Core/DID.[hm]` already provide part of the intended shared
  surface.
- `Garazyk/Binaries/syrena/main.m` has extra exception/SIGABRT handling and
  Linux category verification, so lifecycle cleanup must support
  service-specific hooks.

## Recommended Technical Specs

### `ATProtoDatabaseQueryRunner`

Place under `Garazyk/Sources/Database/Utils/`.

Responsibilities:

- execute `SELECT` statements through `<ATProtoConnectionManager>`,
- execute updates on an existing transaction connection,
- wrap write transactions,
- use `ATProtoDBBindParams`, `ATProtoDBColumnValue`, and
  `PDS_SQLITE_AUTORELEASE_STMT`,
- preserve service-specific error domains,
- preserve Mikrus/Beskid `[NSNull null]` row semantics.

Do not port AppView in this phase.

### XRPC Route Support

Add a narrow helper under `Garazyk/Sources/Network/` for:

- IP rate-limit checks,
- required query parameters,
- bounded integer query parsing.

It should delegate JSON error formatting to `XrpcErrorHelper` and rate-limit
headers to `RateLimiter`.

### DID Document Field Parsing

Add public helpers on `DIDDocument` or a small `ATProtoDIDDocumentFields` class
for:

- normalized handle extraction,
- `AtprotoPersonalDataServer` endpoint extraction,
- ATProto signing key extraction.

Tests must cover current `verificationMethod` arrays and legacy
`verificationMethods` dictionaries.

### Configuration Parsing

Prefer `GZConfigurationParsing` utility methods over `GZBaseConfiguration`
inheritance. The services share parser mechanics, but their configuration
surfaces differ enough that a parent class would create avoidable coupling.

## Execution Roadmap

1. Baseline current behavior:

```bash
cmake --build build --target AllTests --parallel
./build/tests/AllTests --filter 'Beskid*'
./build/tests/AllTests --filter 'Mikrus*'
./build/tests/AllTests --filter 'AppViewDatabaseTests*'
```

2. Implement and test `ATProtoDatabaseQueryRunner`.
3. Port Beskid database helpers, then Mikrus database helpers.
4. Implement route support and DID field helpers.
5. Port Beskid route helpers, then Mikrus route helpers.
6. Add CLI parser extraction.
7. Add configuration parsing utilities.
8. Only then revisit AppView database connection management as a separate
   concurrency project.

## Non-Goals

- Do not implement AppView pooling as part of the Mikrus/Beskid query-runner
  extraction.
- Do not introduce a broad helper class that owns unrelated XRPC, error,
  identity, and database behavior.
- Do not remove Syrena's Linux category verification or SIGABRT diagnostics
  during lifecycle cleanup.

## Supporting Notes

Detailed scoring and phase notes are in:

- `scratchpads/refactor-audit-2026-05-23/00-methodology.md`
- `scratchpads/refactor-audit-2026-05-23/01-inventory-matrix.md`
- `scratchpads/refactor-audit-2026-05-23/02-risk-scores.md`
- `scratchpads/refactor-audit-2026-05-23/03-deep-dives.md`
- `scratchpads/refactor-audit-2026-05-23/04-ranked-roadmap.md`
- `scratchpads/refactor-audit-2026-05-23/05-skill-notes.md`
