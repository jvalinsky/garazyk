# Refactoring Deep Dives and Technical Specs: Mikrus, Beskid, and Syrena

This document specifies the recommended extractions after source validation. The
top candidates remain the database runner and XRPC/identity helpers, but the
implementation boundaries should be narrower than the initial draft.

## 1. SQLite Query Runner

### Problem

`MikrusDatabase` and `BeskidDatabase` both implement:

- `executeQuery:params:error:`
- `executeUpdate:params:connection:error:`
- `performWriteTransaction:error:`

The methods use the same connection-manager flow and the same low-level SQLite
primitives. The only meaningful service-specific behavior is error construction
and the SQL each caller passes in.

### Proposed Extraction

Create `ATProtoDatabaseQueryRunner.[hm]` under
`Garazyk/Sources/Database/Utils/`.

```objc
// ATProtoDatabaseQueryRunner.h
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Database/Connection/ATProtoConnectionManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSError * _Nonnull (^ATProtoDatabaseQueryRunnerErrorFactory)(sqlite3 * _Nullable db,
                                                                     NSInteger code,
                                                                     NSString *fallback);

@interface ATProtoDatabaseQueryRunner : NSObject

@property (nonatomic, readonly, strong) id<ATProtoConnectionManager> connectionManager;

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain;

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)errorFactory NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                            params:(nullable NSArray *)params
                                             error:(NSError **)error;

- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
           connection:(sqlite3 *)db
                error:(NSError **)error;

- (BOOL)performWriteTransaction:(BOOL (^)(sqlite3 *db, NSError **error))block
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
```

Implementation requirements:

- Use `ATProtoDBBindParams` and `ATProtoDBColumnValue`.
- Use `PDS_SQLITE_AUTORELEASE_STMT` from `PDSSQLiteUtils.h` to avoid manual
  finalize paths.
- Preserve Mikrus/Beskid row semantics: include `[NSNull null]` for SQLite null
  values.
- Preserve service error domains through either `errorDomain` or `errorFactory`.
- Propagate `ATProtoConnectionManager execute:` and `transact:` failures.
- Do not port AppView in this phase.

### Characterization Tests

Add `ATProtoDatabaseQueryRunnerTests.m` under `Garazyk/Tests/Database/`.

Cover:

- successful query with text, integer, real, blob, and null values,
- successful update inside a transaction,
- prepare failure error domain,
- step failure error domain,
- transaction rollback when block returns `NO`,
- no statement leak on early return.

## 2. XRPC Route Support and DID Document Fields

### Problem

`MikrusXrpcRoutePack.m` and `BeskidXrpcRoutePack.m` duplicate route-level
helpers:

- IP rate-limit response construction,
- required query parameter validation,
- invalid request response construction,
- database error response construction,
- DID document handle/PDS/signing-key extraction.

The initial report proposed a broad `GZXrpcHelper`. That would centralize too
many unrelated responsibilities and duplicate existing helpers.

### Proposed Extraction

Split the work into two small primitives.

#### Route Support

Create a small route support helper under `Garazyk/Sources/Network/`, for
example `GZXrpcRouteSupport.[hm]`.

```objc
@interface GZXrpcRouteSupport : NSObject

+ (BOOL)checkIPRateLimitForRequest:(HttpRequest *)request
                           response:(HttpResponse *)response;

+ (nullable NSString *)requiredQueryParam:(NSString *)name
                                  request:(HttpRequest *)request
                                 response:(HttpResponse *)response;

+ (BOOL)parseLimitForRequest:(HttpRequest *)request
                defaultLimit:(NSInteger)defaultLimit
                         min:(NSInteger)minLimit
                         max:(NSInteger)maxLimit
                      output:(NSInteger *)output
                    response:(HttpResponse *)response;

@end
```

Implementation requirements:

- Delegate error JSON to `XrpcErrorHelper`.
- Delegate rate-limit header generation to `RateLimiter` where possible.
- Keep database-domain-specific conversion in the route packs unless a second
  service proves the exact mapping is shared.

#### DID Document Fields

Add public parsing helpers to `DIDDocument` or create a small
`ATProtoDIDDocumentFields` helper under `Garazyk/Sources/Identity/`.

```objc
@interface ATProtoDIDDocumentFields : NSObject

+ (nullable NSString *)normalizedHandleFromDocument:(DIDDocument *)document;
+ (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)document;
+ (nullable NSString *)atprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document;

@end
```

Implementation requirements:

- Support current `verificationMethod` array documents.
- Support legacy PLC-style `verificationMethods` dictionary documents where
  existing services already expect it.
- Normalize `at://handle` and trailing slash handling exactly once.
- Prefer exact `#atproto` method IDs before fallback keys.

### Characterization Tests

Add tests with fixtures for:

- `alsoKnownAs: ["at://Alice.Example/"]` normalizes to `alice.example`,
- service array with `AtprotoPersonalDataServer` returns `serviceEndpoint`,
- modern `verificationMethod` array with `#atproto`,
- fallback verification method when no `#atproto` method exists,
- legacy `verificationMethods: { "atproto": "did:key:..." }`,
- malformed types return nil instead of throwing.

## 3. Configuration Parsing Utilities

### Problem

Mikrus, Beskid, and AppView all parse environment values and dictionaries by
hand. Mikrus/Beskid also duplicate bounded port parsing and rate-limit key
parsing. AppView is similar but has more service-specific fields and no
rate-limit settings.

### Proposed Extraction

Start with utility functions instead of inheritance:

```objc
@interface GZConfigurationParsing : NSObject

+ (NSArray<NSString *> *)csvValuesFromString:(NSString *)value;
+ (BOOL)parseUnsignedInteger:(id)value
                         min:(NSUInteger)min
                         max:(NSUInteger)max
                      output:(NSUInteger *)output;
+ (BOOL)parseTimeInterval:(id)value
                      min:(NSTimeInterval)min
                   output:(NSTimeInterval *)output;
+ (BOOL)parseBool:(id)value output:(BOOL *)output;

@end
```

Use these utilities in service configuration classes one at a time.

Do not start with `GZBaseConfiguration` inheritance. A base class would force
AppView, Mikrus, and Beskid into shared properties that do not cleanly match,
especially rate limiting and AppView partial/backfill settings.

### Characterization Tests

Add direct tests for:

- CSV trimming and empty-value filtering,
- numeric string validation with full-string scanning,
- `UINT16_MAX` port bound,
- ephemeral port `0` for dictionary values where allowed,
- boolean parsing behavior matching current `boolValue` semantics.

Then update service-specific configuration tests for Mikrus, Beskid, and
AppView.

## 4. Deferred AppView Connection Migration

AppView's database path should not be folded into the first query-runner
refactor. It currently uses raw `_db`, `safeExecuteSync`, and
`PDS_SQLITE_AUTORELEASE_STMT`, and callers rely on serialized access.

A later migration can introduce `ATProtoConnectionManagerSerial` first, then
evaluate a pool. That migration needs a separate concurrency plan and
AppView-specific tests for backfill, write proxy, and ingestion behavior.
