# Refactoring Audit Methodology: Mikrus, Beskid, and Syrena

This audit reviews shared code, repeated patterns, and refactoring opportunities
across three service binaries:

- **Mikrus**: link index service.
- **Beskid**: edge record and identity cache service.
- **Syrena**: standalone AppView service.

The original audit identified the right high-value areas, but the follow-up
review tightened several claims against source truth. The final plan should
distinguish exact duplication from similar implementation patterns and should
prefer existing shared helpers before introducing new broad utility classes.

## Audit Objectives

1. Inventory overlapping architecture in entrypoints, runtime bootstrap,
   database setup, configuration loading, and XRPC routing.
2. Separate exact copy/paste from similar-but-not-identical code paths.
3. Score extraction targets by boundary risk, structural drag, test leverage,
   change safety, and payoff.
4. Produce staged refactoring candidates that keep service behavior intact.
5. Define characterization tests before any implementation refactor.

## Evidence Sources

Primary files reviewed:

- **Binaries**
  - `Garazyk/Binaries/mikrus/main.m`
  - `Garazyk/Binaries/beskid/main.m`
  - `Garazyk/Binaries/syrena/main.m`
- **Configuration Layers**
  - `Garazyk/Sources/Mikrus/MikrusConfiguration.[hm]`
  - `Garazyk/Sources/Beskid/BeskidConfiguration.[hm]`
  - `Garazyk/Sources/AppView/Server/Config/AppViewConfiguration.[hm]`
  - `Garazyk/Sources/MediaCore/ATProtoMediaServiceConfiguration.[hm]`
- **Runtime Layers**
  - `Garazyk/Sources/Mikrus/MikrusRuntime.[hm]`
  - `Garazyk/Sources/Beskid/BeskidRuntime.[hm]`
  - `Garazyk/Sources/AppView/Server/AppViewRuntime.[hm]`
- **Database Layers**
  - `Garazyk/Sources/Mikrus/MikrusDatabase.[hm]`
  - `Garazyk/Sources/Beskid/BeskidDatabase.[hm]`
  - `Garazyk/Sources/AppView/Server/AppViewDatabase.[hm]`
  - `Garazyk/Sources/Database/Connection/ATProtoConnectionManager*.h`
  - `Garazyk/Sources/Database/Utils/ATProtoDatabaseUtilities.h`
  - `Garazyk/Sources/Database/Utils/PDSSQLiteUtils.h`
- **XRPC, Rate Limit, and Identity Helpers**
  - `Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.[hm]`
  - `Garazyk/Sources/Beskid/BeskidXrpcRoutePack.[hm]`
  - `Garazyk/Sources/Network/XrpcErrorHelper.[hm]`
  - `Garazyk/Sources/Network/RateLimiter.[hm]`
  - `Garazyk/Sources/Network/XrpcIdentityHelper.[hm]`
  - `Garazyk/Sources/Core/DID.[hm]`

Useful verification commands:

```bash
rg -n "executeQuery:|executeUpdate:|performWriteTransaction:" Garazyk/Sources/Mikrus Garazyk/Sources/Beskid
rg -n "executeParameterizedQuery:|executeParameterizedUpdate:" Garazyk/Sources/AppView/Server/AppViewDatabase.m
rg -n "RateLimitExceeded|X-RateLimit-Limit|requiredParam:|handleFromDocument:|pdsEndpointFromDocument:|signingKeyFromDocument:" Garazyk/Sources
rg -n "alsoKnownAs|AtprotoPersonalDataServer|verificationMethod|verificationMethods" Garazyk/Sources
```

## Scoring Criteria

Each candidate is scored from 1 to 5:

1. **Boundary Risk**: higher means lower risk of leaking service-specific
   behavior into shared code.
2. **Structural Drag**: higher means more duplicate boilerplate or operational
   friction.
3. **Test Leverage**: higher means a shared module can be tested more directly
   than the current code.
4. **Change Safety**: higher means lower chance of behavioral regressions during
   extraction.
5. **Refactor Payoff**: higher means the extraction materially reduces future
   maintenance cost.

## Review Corrections

- The final report file named by the initial summary was missing from the
  workspace. This review creates `refactor_opportunity_audit_report.md`.
- The SQLite query/update helpers are exact in shape between Mikrus and Beskid,
  but not character-for-character because each service uses its own error
  constructor/domain.
- AppView has similar parameterized SQL logic, but it is not the same extraction
  target in phase 1. It uses a raw serialized `sqlite3` connection,
  `safeExecuteSync`, and `PDS_SQLITE_AUTORELEASE_STMT`.
- The XRPC route-pack duplication should build on existing helpers
  (`XrpcErrorHelper`, `RateLimiter`, `DIDDocument`/`DIDResolver`) instead of
  creating a broad helper that re-implements them.
- Configuration duplication is real, but inheritance is not the safest first
  move. Shared parser functions or a small configuration parsing helper are
  safer than a base class that forces AppView and rate-limited services into one
  shape.

## Staging and Rollback Strategy

Recommended refactors should use progressive extraction:

1. Add characterization tests around the current behavior.
2. Add the shared primitive without changing callers.
3. Port Beskid first where the surface area is smaller.
4. Port Mikrus next.
5. Treat AppView database concurrency changes as a separate migration after the
   helper has proven stable.

Rollback should be code-level and per phase: keep each extraction in a small
branch/commit so the changed service can return to its local implementation
without schema changes or data migrations.
