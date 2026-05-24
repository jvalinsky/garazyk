# Refactoring Deep-Dives & Technical Specs: Mikrus, Beskid, and Syrena

This document provides a highly technical deep-dive into the architectural
extraction designs for our high-scoring candidates: **Candidate D** (SQLite
connection wrappers), **Candidate F** (XRPC & Identity parsers), and **Candidate
C** (unified Configuration base class).

---

## 1. Candidate D: SQLite Connection-Pool Execution Wrappers

### The Duplication Problem

Both `MikrusDatabase` and `BeskidDatabase` implement their own
`executeQuery:params:error:` and `executeUpdate:params:connection:error:`
wrappers. They both hold a connection manager conforming to
`<ATProtoConnectionManager>` and manually run SQL prepares, steps, column
fetches, and finalizations.

### The Proposed Extraction

We propose creating a reusable class called `ATProtoDatabaseQueryRunner` under
`Garazyk/Sources/Database/Utils/` that encapsulates these patterns.

```objc
// ATProtoDatabaseQueryRunner.h
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Database/Connection/ATProtoConnectionManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoDatabaseQueryRunner : NSObject

@property (nonatomic, readonly, strong) id<ATProtoConnectionManager> connectionManager;
@property (nonatomic, readonly, copy) NSString *errorDomain;

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain NS_DESIGNATED_INITIALIZER;
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

By instantiating this query runner during initialization, we can rewrite
database calls in both `MikrusDatabase.m` and `BeskidDatabase.m` to:

```objc
_queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:self.connectionManager
                                                                 errorDomain:MikrusDatabaseErrorDomain];
...
NSArray *rows = [_queryRunner executeQuery:sql params:params error:error];
```

This removes over 150 lines of duplicate code instantly!

---

## 2. Candidate F: XRPC Route Helpers & Identity Parsers

### The Duplication Problem

`MikrusXrpcRoutePack.m` and `BeskidXrpcRoutePack.m` duplicate several methods:

1. `checkRateLimitForRequest:response:`
2. `requiredParam:request:response:`
3. `writeInvalidRequest:response:` and `writeDatabaseError:response:`
4. `handleFromDocument:`, `pdsEndpointFromDocument:`, and
   `signingKeyFromDocument:`

### The Proposed Extraction

We propose creating a shared class `GZXrpcHelper` inside the shared network
namespace to house these stateless utility helpers.

```objc
// GZXrpcHelper.h
#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Identity/DIDDocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface GZXrpcHelper : NSObject

// Rate limit checks
+ (BOOL)checkRateLimitForRequest:(HttpRequest *)request
                        response:(HttpResponse *)response;

// Query parameter assertions
+ (nullable NSString *)requiredParam:(NSString *)name
                             request:(HttpRequest *)request
                            response:(HttpResponse *)response;

+ (BOOL)parseLimitFromRequest:(HttpRequest *)request
                 defaultLimit:(NSInteger)defaultLimit
                       output:(NSInteger *)output
                     response:(HttpResponse *)response;

// DID document property extraction
+ (nullable NSString *)handleFromDocument:(DIDDocument *)doc;
+ (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)doc;
+ (nullable NSString *)signingKeyFromDocument:(DIDDocument *)doc;

// Standard HTTP error responses
+ (void)writeInvalidRequest:(nullable NSString *)message
                   response:(HttpResponse *)response;

+ (void)writeDatabaseError:(NSError *)error
               errorDomain:(NSString *)errorDomain
                  response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
```

This isolates route packs from having to contain identical HTTP utility and
parsing details, bringing lines of code down substantially.

---

## 3. Candidate C: Unified Base Configuration Class

### The Duplication Problem

All service configuration models (`MikrusConfiguration`, `BeskidConfiguration`,
`AppViewConfiguration`) implement manual logic in
`+configurationFromEnvironment` and `-loadFromDictionary:` to scan environment
mappings and cast port parameters.

### The Proposed Extraction

We propose a base class `GZBaseConfiguration` that houses shared configuration
parameters and general parsing methods.

```objc
// GZBaseConfiguration.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GZBaseConfiguration : NSObject

@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, assign) NSUInteger httpPort;

// Rate limiting values (shared between Mikrus & Beskid)
@property (nonatomic, assign) BOOL rateLimitEnabled;
@property (nonatomic, assign) NSInteger rateLimitIpLimit;
@property (nonatomic, assign) NSTimeInterval rateLimitIpWindowSeconds;

// Environment / dictionary loaders
- (void)loadCommonEnvironmentOverrides:(NSDictionary<NSString *, NSString *> *)env
                                 prefix:(NSString *)prefix;

- (void)loadCommonDictionaryValues:(NSDictionary *)dictionary;

// Static parsing utilities
+ (NSArray<NSString *> *)splitCSV:(NSString *)value;
+ (NSUInteger)parsePortFromValue:(id)port defaultPort:(NSUInteger)defaultPort;

@end

NS_ASSUME_NONNULL_END
```

This base configuration class guarantees that any new service added to the
Garazyk stack automatically gains robust command-line override capabilities, CSV
parsers, rate limit configurations, and port scanning protections out of the
box.
