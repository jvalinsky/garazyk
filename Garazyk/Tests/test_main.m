// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

// Define XCTAssertIsInstance macro if not available
#ifndef XCTAssertIsInstance
#define XCTAssertIsInstance(expr, classExpr) \
    XCTAssertTrue([(expr) isKindOfClass:(classExpr)], @"Expected %@ to be instance of %@", (expr), (classExpr))
#endif
#import "App/ATProtoServiceConfiguration.h"
#import "Auth/OAuthConformanceTests.h"
#import "Auth/OAuthPublicClientTests.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Debug/GZLogger.h"
#import <objc/runtime.h>

@interface SimpleTestObserver : NSObject <XCTestObservation>
@property(nonatomic, assign) int failureCount;
@property(nonatomic, assign) int testCount;
@property(nonatomic, assign) int unexpectedFailureCount;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *testStartTimes;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *methodTimings;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *failedTests;
@end

static NSString *PDSClassNameFromTestCase(XCTestCase *testCase) {
  NSString *name = testCase.name ?: @"";
  if (([name hasPrefix:@"-["] || [name hasPrefix:@"+["]) &&
      [name hasSuffix:@"]"] && name.length > 3) {
    NSString *inner = [name substringWithRange:NSMakeRange(2, name.length - 3)];
    NSArray<NSString *> *parts =
        [inner componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (parts.count > 0 && parts[0].length > 0) {
      return parts[0];
    }
  }

  NSRange slash = [name rangeOfString:@"/"];
  if (slash.location != NSNotFound && slash.location > 0) {
    return [name substringToIndex:slash.location];
  }

  return NSStringFromClass([testCase class]);
}

static NSString *PDSMethodNameFromTestCase(XCTestCase *testCase) {
  NSString *name = testCase.name ?: @"";
  if (([name hasPrefix:@"-["] || [name hasPrefix:@"+["]) &&
      [name hasSuffix:@"]"] && name.length > 3) {
    NSString *inner = [name substringWithRange:NSMakeRange(2, name.length - 3)];
    NSArray<NSString *> *parts =
        [inner componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (parts.count > 1 && parts[1].length > 0) {
      return parts[1];
    }
  }

  NSRange slash = [name rangeOfString:@"/"];
  if (slash.location != NSNotFound && NSMaxRange(slash) < name.length) {
    return [name substringFromIndex:NSMaxRange(slash)];
  }

  return name.length > 0 ? name : @"unknown";
}

#ifdef __APPLE__
@implementation SimpleTestObserver
- (instancetype)init {
  self = [super init];
  if (self) {
    _failureCount = 0;
    _testCount = 0;
    _unexpectedFailureCount = 0;
    _testStartTimes = [NSMutableDictionary dictionary];
    _methodTimings = [NSMutableArray array];
    _failedTests = [NSMutableArray array];
  }
  return self;
}

- (void)testCaseWillStart:(XCTestCase *)testCase {
  self.testCount++;
  NSString *key = [NSString stringWithFormat:@"%p", testCase];
  self.testStartTimes[key] = [NSDate date];
}

- (void)testCase:(XCTestCase *)testCase
    didFailWithDescription:(NSString *)description
                    inFile:(nullable NSString *)filePath
                    atLine:(NSUInteger)lineNumber {
  self.failureCount++;
  NSLog(@"FAIL: %@ at %@:%lu: %@", testCase.name, filePath, (unsigned long)lineNumber, description);
  [self.failedTests addObject:@{
    @"class" : PDSClassNameFromTestCase(testCase),
    @"method" : PDSMethodNameFromTestCase(testCase),
    @"file" : filePath ?: @"(unknown)",
    @"line" : @(lineNumber),
    @"description" : description ?: @""
  }];
}

- (void)testCaseDidFinish:(XCTestCase *)testCase {
  NSString *key = [NSString stringWithFormat:@"%p", testCase];
  NSDate *start = self.testStartTimes[key];
  [self.testStartTimes removeObjectForKey:key];
  NSTimeInterval elapsed = start ? -[start timeIntervalSinceNow] : 0;
  [self.methodTimings addObject:@{
    @"class" : PDSClassNameFromTestCase(testCase),
    @"method" : PDSMethodNameFromTestCase(testCase),
    @"duration" : @(elapsed)
  }];
}
@end
#else
@implementation SimpleTestObserver
- (instancetype)init {
  self = [super init];
  if (self) {
    _failureCount = 0;
    _testCount = 0;
    _unexpectedFailureCount = 0;
    _testStartTimes = [NSMutableDictionary dictionary];
    _methodTimings = [NSMutableArray array];
    _failedTests = [NSMutableArray array];
  }
  return self;
}

- (void)testCaseWillStart:(XCTestCase *)testCase {
  self.testCount++;
  NSString *key = [NSString stringWithFormat:@"%p", testCase];
  self.testStartTimes[key] = [NSDate date];
}

- (void)testCase:(XCTestCase *)testCase
    didFailWithDescription:(NSString *)description
                    inFile:(nullable NSString *)filePath
                    atLine:(NSUInteger)lineNumber {
  self.failureCount++;
  NSLog(@"FAIL: %@ at %@:%lu: %@", testCase.name, filePath, (unsigned long)lineNumber, description);
  [self.failedTests addObject:@{
    @"class" : PDSClassNameFromTestCase(testCase),
    @"method" : PDSMethodNameFromTestCase(testCase),
    @"file" : filePath ?: @"(unknown)",
    @"line" : @(lineNumber),
    @"description" : description ?: @""
  }];
}

- (void)testCaseDidFinish:(XCTestCase *)testCase {
  NSString *key = [NSString stringWithFormat:@"%p", testCase];
  NSDate *start = self.testStartTimes[key];
  [self.testStartTimes removeObjectForKey:key];
  NSTimeInterval elapsed = start ? -[start timeIntervalSinceNow] : 0;
  [self.methodTimings addObject:@{
    @"class" : PDSClassNameFromTestCase(testCase),
    @"method" : PDSMethodNameFromTestCase(testCase),
    @"duration" : @(elapsed)
  }];
}
@end
#endif

NSArray *discoverTestMethodsForClass(Class testClass) {
  NSMutableArray *methods = [NSMutableArray array];
  unsigned int methodCount;
  Method *methodList = class_copyMethodList(testClass, &methodCount);
  for (unsigned int i = 0; i < methodCount; i++) {
    Method method = methodList[i];
    SEL selector = method_getName(method);
    NSString *methodName = NSStringFromSelector(selector);
    if ([methodName hasPrefix:@"test"]) {
      char *returnType = method_copyReturnType(method);
      int numArgs = method_getNumberOfArguments(method);
      if (returnType && strcmp(returnType, "v") == 0 && numArgs == 2) {
        [methods addObject:methodName];
      }
      free(returnType);
    }
  }
  free(methodList);
  return [methods copy];
}

static BOOL PDSEnvEnabled(const char *name) {
  const char *value = getenv(name);
  if (!value) {
    return NO;
  }
  NSString *stringValue =
      [[[NSString stringWithUTF8String:value] lowercaseString]
          stringByTrimmingCharactersInSet:[NSCharacterSet
                                              whitespaceAndNewlineCharacterSet]];
  return [stringValue isEqualToString:@"1"] ||
         [stringValue isEqualToString:@"true"] ||
         [stringValue isEqualToString:@"yes"] ||
         [stringValue isEqualToString:@"on"];
}

static NSDictionary<NSString *, id> *PDSParseTestFilter(NSString *testFilter) {
  if (testFilter.length == 0) {
    return nil;
  }

  NSMutableSet<NSString *> *classes = [NSMutableSet set];
  NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *methodsByClass =
      [NSMutableDictionary dictionary];
  NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  for (NSString *rawToken in [testFilter componentsSeparatedByString:@","]) {
    NSString *token = [rawToken stringByTrimmingCharactersInSet:trimSet];
    if (token.length == 0) {
      continue;
    }

    NSRange slash = [token rangeOfString:@"/"];
    if (slash.location == NSNotFound) {
      [classes addObject:token];
      continue;
    }

    NSString *className = [[token substringToIndex:slash.location]
        stringByTrimmingCharactersInSet:trimSet];
    NSString *methodName = [[token substringFromIndex:NSMaxRange(slash)]
        stringByTrimmingCharactersInSet:trimSet];
    if (className.length == 0) {
      continue;
    }

    [classes addObject:className];
    if (methodName.length > 0) {
      NSMutableSet<NSString *> *methods = methodsByClass[className];
      if (!methods) {
        methods = [NSMutableSet set];
        methodsByClass[className] = methods;
      }
      [methods addObject:methodName];
    }
  }

  return @{
    @"classes" : classes,
    @"methods" : methodsByClass
  };
}

static BOOL PDSFilterIncludesClass(NSDictionary<NSString *, id> *filter,
                                   NSString *className) {
  if (!filter) {
    return YES;
  }
  NSSet<NSString *> *classes = filter[@"classes"];
  return [classes containsObject:className];
}

static BOOL PDSFilterIncludesMethod(NSDictionary<NSString *, id> *filter,
                                    NSString *className,
                                    NSString *methodName) {
  if (!filter) {
    return YES;
  }
  NSDictionary<NSString *, NSSet<NSString *> *> *methodsByClass =
      filter[@"methods"];
  NSSet<NSString *> *methods = methodsByClass[className];
  if (!methods) {
    return YES;
  }
  return [methods containsObject:methodName];
}

// ── Glob pattern matching ────────────────────────────────────────────────

static BOOL PDSGlobMatches(NSString *pattern, NSString *string) {
  if (!pattern || !string) return NO;
  // Convert glob pattern to NSPredicate LIKE format.
  // * matches any sequence, ? matches single char.
  // NSPredicate LIKE uses * and ? the same way.
  NSPredicate *pred = [NSPredicate predicateWithFormat:@"self LIKE %@", pattern];
  return [pred evaluateWithObject:string];
}

static BOOL PDSAnyPatternMatches(NSArray<NSString *> *patterns, NSString *string) {
  if (!patterns || patterns.count == 0) return NO;
  for (NSString *pattern in patterns) {
    if (PDSGlobMatches(pattern, string)) return YES;
  }
  return NO;
}

// ── Category mapping ────────────────────────────────────────────────────

// Forward declarations
static NSSet<NSString *> *PDSRuntimeTestClassNames(void);

// Maps test class names to their source directory (category).
// Uses filesystem scan when available, with pattern-based fallback.
static NSDictionary<NSString *, NSString *> *PDSBuildCategoryMap(void) {
  static NSDictionary<NSString *, NSString *> *map = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSMutableDictionary<NSString *, NSString *> *builder =
        [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Strategy 1: Filesystem scan — map filename (minus .m) → parent dir
    NSString *testsRoot = nil;
    NSString *exePath = [[NSBundle mainBundle] executablePath];
    if (exePath) {
      NSString *candidate = [exePath stringByDeletingLastPathComponent];
      while (candidate.length > 0) {
        NSString *check = [candidate stringByAppendingPathComponent:@"Garazyk/Tests"];
        if ([fm fileExistsAtPath:check]) {
          testsRoot = check;
          break;
        }
        NSString *parent = [candidate stringByDeletingLastPathComponent];
        if ([parent isEqualToString:candidate]) break;
        candidate = parent;
      }
    }
    if (!testsRoot) {
      NSString *cwd = [fm currentDirectoryPath];
      NSString *check = [cwd stringByAppendingPathComponent:@"Garazyk/Tests"];
      if ([fm fileExistsAtPath:check]) {
        testsRoot = check;
      }
    }

    if (testsRoot) {
      NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:testsRoot];
      NSString *path;
      while ((path = [dirEnum nextObject])) {
        if (![path hasSuffix:@".m"]) continue;
        NSString *filename = path.lastPathComponent;
        if ([filename isEqualToString:@"test_main.m"]) continue;
        NSString *className = [filename stringByDeletingPathExtension];
        NSString *dirPath = [path stringByDeletingLastPathComponent];
        if (dirPath.length > 0) {
          NSArray *parts = [dirPath componentsSeparatedByString:@"/"];
          builder[className] = parts.lastObject ?: dirPath;
        }
      }
    }

    // Strategy 2: Pattern-based inference for classes not found by scan.
    // This handles classes defined in shared files (e.g. CIDTests in
    // CorePrimitivesTests.m) and any classes the filesystem scan missed.
    NSDictionary<NSString *, NSArray<NSString *> *> *categoryPatterns = @{
      @"Admin":          @[@"Admin"],
      @"AppView":        @[@"AppView"],
      @"Blob":           @[@"Blob"],
      @"CLI":            @[@"CLI"],
      @"Core":           @[@"CID", @"TID", @"Base58", @"ATProtoCore",
                           @"ATProtoDagCBOR", @"CBORSerialization",
                           @"ATProtoValidator", @"ATProtoBase32",
                           @"CorePrimitives", @"ProtocolCompile",
                           @"ATProtoDateTime", @"NSDateFormatterATProto",
                           @"ATProtoError", @"DIDValidation",
                           @"Identifier", @"RecordPathValidation",
                           @"ATProtoDataPaths", @"PDSAccountManager",
                           @"ATProtoServiceContainer", @"GZProviderRegistry"],
      @"Auth":           @[@"Crypto", @"JWT", @"OAuth", @"TOTP",
                           @"Secp256k1", @"PDSNonce", @"YubiKey",
                           @"WebAuthn", @"PDSOpenSSLKeyManager",
                           @"Session", @"PDSReplayCache", @"Refresh",
                           @"AuthCrypto", @"Base32Utils"],
      @"Database":       @[@"ActorStore", @"DatabasePool", @"DatabaseMigration",
                           @"PDSMigration", @"PDSDatabaseLRU", @"PDSController",
                           @"PDSHealthCheck", @"ServiceDatabases",
                           @"RecordCache", @"PDSNewArchitecture",
                           @"PDSVideoJobs", @"ConnectionPool"],
      @"Identity":       @[@"DIDResolver", @"HandleResolver", @"ATProtoHandle",
                           @"XrpcIdentityResolution"],
      @"Network":        @[@"Http", @"RateLimiter", @"RateLimiting",
                           @"ATProtoNetwork", @"PDSHttp", @"WebSocketUpgrade",
                           @"SSLPinning", @"SSRF", @"PDSIntegration",
                           @"AccountLifecycle", @"AdminAuth",
                           @"RepoAuth", @"RepoDescribe", @"ModerationIdentity",
                           @"SyncEndpoint", @"FeedSkeleton", @"StarterPack",
                           @"SecurityHardening", @"XrpcAppBsky",
                           @"XrpcChatBsky", @"XrpcToolsOzone",
                           @"XrpcProxy", @"XrpcError", @"XrpcIntegration",
                           @"XrpcMethodRegistry"],
      @"PLC":            @[@"PLCOperation", @"PLCStore", @"PLCAuditor",
                           @"PLCServer", @"PLCReplica", @"PLCDIDKey",
                           @"PLCCacheDirectory", @"PLCRotationKey",
                           @"DIDPLCResolver"],
      @"Repository":     @[@"MST", @"RepoCommit", @"CARInterop",
                           @"IPLDBlock"],
      @"Sync":           @[@"Firehose", @"Relay", @"Subscribe",
                           @"PDSWebSocket", @"WebSocket", @"EventFormatter",
                           @"RelayAPI"],
      @"Security":       @[@"CBORSecurity", @"JWTSecurity",
                           @"HandleResolverSecurity", @"ProductionSecurity",
                           @"GZAuthz", @"GZInput", @"Phase2Security"],
      @"Email":          @[@"PDSEmail", @"PDSEnvironment", @"PDSKeychain",
                           @"PDSMockEmail", @"PDSSMTP", @"PDSResend"],
      @"App":            @[@"PDSAccount", @"PDSBlob", @"PDSRecord",
                           @"PDSRepository", @"PDSRelay", @"ATProtoServiceConfiguration",
                           @"PDSPhone", @"AppDelegate", @"PDSApplication"],
      @"CharacterizationTests": @[@"ActorStoreCharacterization",
                                  @"MSTCharacterization",
                                  @"SessionCharacterization",
                                  @"KeyManagerCharacterization",
                                  @"XrpcMethodRegistryCharacterization",
                                  @"HttpConnectionCharacterization",
                                  @"WebSocketFrameCharacterization",
                                  @"WebSocketStateCharacterization"],
      @"Integration":     @[@"PDSPLCIntegration", @"CommitChain",
                           @"RelayIntegration", @"OAuthIntegration",
                           @"EmailIntegration", @"FirehoseIntegration",
                           @"FollowersCountIntegration",
                           @"MultiTenantDatabase",
                           @"PDSDatabaseIntegration",
                           @"E2EDocker", @"UILabIntegration",
                           @"ATProtoVideoTranscoderIntegration",
                           @"ATProtoVideoThumbnailGeneratorIntegration",
                           @"ATProtoVideoWorkerIntegration",
                           @"HealthEndpointIntegration",
                           @"XrpcIntegration"],
      @"Compat":         @[@"Arc4random", @"CFRelease", @"PlatformGuard",
                           @"SecItem", @"ATProtoNetworkTransportLinux"],
      @"Lexicon":        @[@"LexiconValidation", @"LexiconResolve"],
      @"Interop":        @[@"LexiconValidatorInterop", @"AtprotoInterop",
                           @"SyntaxInterop", @"MSTInterop"],
      @"Media":          @[@"ATProtoMedia", @"PDSVideo", @"ATProtoVideo", @"MimeType", @"JelczCLI"],
      @"Video":          @[@"AVFoundationTranscoder", @"FFmpegTranscoder", @"VideoRemote",
                           @"VideoLocal", @"VideoJWT", @"VideoPDS", @"VideoHLS"],
      @"Metrics":        @[@"GZMetrics"],
      @"Debug":          @[@"GZLoggerPerformance"],
      @"Deployment":     @[@"DeploymentReadiness"],
      @"Federation":     @[@"FederationClient"],
      @"Registration":   @[@"PDSRegistrationGate"],
      @"PhoneVerification": @[@"PDSTwilio", @"PDSVonage", @"PDSPlivo",
                               @"PDSTelegram"],
      @"AdminUIServer":  @[@"UIAuth", @"UIBackend", @"UIServer",
                           @"UILabAuth"],
      @"XRPC":           @[@"XrpcHandler", @"XrpcInputValidation",
                           @"XrpcErrorResponse", @"XrpcErrorHelper",
                           @"GetServiceAuth"],
      @"Services":       @[@"CoverageGap"],
      @"AppViewServer":  @[@"AppViewDatabase", @"AppViewIngestEngine",
                           @"AppViewBackfill", @"AppViewBackfillWorker",
                           @"AppViewRelevanceSet"],
    };

    // Apply pattern-based categories for any class not yet mapped
    for (NSString *category in categoryPatterns) {
      NSArray<NSString *> *prefixes = categoryPatterns[category];
      for (NSString *className in [PDSRuntimeTestClassNames() allObjects]) {
        if (builder[className].length > 0) continue;  // already mapped
        for (NSString *prefix in prefixes) {
          if ([className hasPrefix:prefix]) {
            builder[className] = category;
            break;
          }
        }
      }
    }

    map = [builder copy];
  });
  return map;
}

static NSString *PDSCategoryForClass(NSString *className) {
  return PDSBuildCategoryMap()[className];
}

// ── Gated test classes ──────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, PDSGatedMode) {
  PDSGatedModeSkip,     // skip gated tests (default)
  PDSGatedModeRun,      // run gated tests
  PDSGatedModeMarkSkip  // include but mark as skipped in output
};

static NSDictionary<NSString *, NSString *> *PDSGatedClassMap(void) {
  static NSDictionary<NSString *, NSString *> *map = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    map = @{
      // integration gate
      @"PDSPLCIntegrationTests"                       : @"integration",
      @"PDSIntegrationTests"                           : @"integration",
      @"CommitChainTests"                              : @"integration",
      @"RelayIntegrationTests"                         : @"integration",
      @"OAuthIntegrationTests"                         : @"integration",
      @"EmailIntegrationTests"                         : @"integration",
      @"FirehoseIntegrationTests"                      : @"integration",
      @"FollowersCountIntegrationTests"                 : @"integration",
      @"MultiTenantDatabaseTests"                      : @"integration",
      @"PDSDatabaseIntegrationTests"                   : @"integration",
      @"XrpcIntegrationTests"                          : @"integration",
      @"E2EDockerTests"                                : @"integration",
      @"UILabIntegrationTests"                         : @"integration",
      @"ATProtoVideoTranscoderIntegrationTests"         : @"integration",
      @"ATProtoVideoThumbnailGeneratorIntegrationTests" : @"integration",
      @"ATProtoVideoWorkerIntegrationTests"            : @"integration",
      @"SSLPinningTests"                               : @"integration",
      // socket gate
      @"HealthEndpointIntegrationTests" : @"socket",
      @"HttpServerTests"               : @"socket",
      @"OAuth2EndpointTests"            : @"socket",
      @"PDSApplicationTests"           : @"socket",
      @"ATProtoHttpServerBuilderTests"     : @"socket",
      @"PLCServerTests"                : @"socket",
      @"PLCReplicaServerTests"         : @"socket",
      @"PDSWebSocketServerTests"       : @"socket",
      @"PDSWebSocketTransportTests"    : @"socket",
      @"WebSocketServerTests"          : @"socket",
      @"MikrusRuntimeTests"     : @"socket",
      @"ATProtoMediaServiceRuntimeTests" : @"socket"
    };
  });
  return map;
}

static NSString *PDSGateNameForClass(NSString *className) {
  return PDSGatedClassMap()[className];
}

static NSString *PDSSkipReasonForClass(NSString *className, PDSGatedMode gatedMode) {
  if (gatedMode == PDSGatedModeRun) {
    return nil;  // --gated=run: don't skip anything
  }
  NSString *gateName = PDSGateNameForClass(className);
  if (!gateName) {
    return nil;  // not a gated class
  }
  if (gatedMode == PDSGatedModeMarkSkip) {
    return nil;  // --gated=include: include it (will be marked in output)
  }
  // PDSGatedModeSkip (default)
  return [NSString stringWithFormat:@"gated:%@ (use --gated=run)", gateName];
}

static BOOL PDSClassIsSubclassOf(Class testClass, Class parentClass) {
  for (Class current = testClass; current; current = class_getSuperclass(current)) {
    if (current == parentClass) {
      return YES;
    }
  }
  return NO;
}

static NSSet<NSString *> *PDSRuntimeTestClassNames(void) {
  int count = objc_getClassList(NULL, 0);
  if (count <= 0) {
    return [NSSet set];
  }

  Class *classes = (__unsafe_unretained Class *)calloc((NSUInteger)count, sizeof(Class));
  if (!classes) {
    return [NSSet set];
  }

  count = objc_getClassList(classes, count);
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  Class testCaseClass = [XCTestCase class];
  for (int i = 0; i < count; i++) {
    Class candidate = classes[i];
    if (!candidate || candidate == testCaseClass ||
        !PDSClassIsSubclassOf(candidate, testCaseClass)) {
      continue;
    }
    NSString *className = NSStringFromClass(candidate);
    if (![className hasSuffix:@"Tests"]) {
      continue;
    }
    if ([discoverTestMethodsForClass(candidate) count] == 0) {
      continue;
    }
    [names addObject:className];
  }
  free(classes);
  return names;
}

static BOOL PDSRunRegistrationAudit(NSArray<NSString *> *registeredClasses) {
  NSMutableSet<NSString *> *registered =
      [NSMutableSet setWithArray:registeredClasses];
  NSSet<NSString *> *runtime = PDSRuntimeTestClassNames();

  NSMutableSet<NSString *> *missing = [runtime mutableCopy];
  [missing minusSet:registered];

  NSMutableSet<NSString *> *stale = [registered mutableCopy];
  [stale minusSet:runtime];

  NSArray<NSString *> *missingSorted =
      [[missing allObjects] sortedArrayUsingSelector:@selector(compare:)];
  NSArray<NSString *> *staleSorted =
      [[stale allObjects] sortedArrayUsingSelector:@selector(compare:)];

  if (missingSorted.count == 0 && staleSorted.count == 0) {
    fprintf(stderr, "Registration audit passed: runner and runtime test classes match\n");
    return YES;
  }

  fprintf(stderr, "Registration audit failed\n");
  if (missingSorted.count > 0) {
    fprintf(stderr, "Runtime test classes missing from runner (%lu):\n",
            (unsigned long)missingSorted.count);
    for (NSString *name in missingSorted) {
      fprintf(stderr, "  %s\n", name.UTF8String);
    }
  }
  if (staleSorted.count > 0) {
    fprintf(stderr, "Runner classes not present at runtime (%lu):\n",
            (unsigned long)staleSorted.count);
    for (NSString *name in staleSorted) {
      fprintf(stderr, "  %s\n", name.UTF8String);
    }
  }
  return NO;
}

static void PDSPrintTimingSummary(SimpleTestObserver *observer) {
  NSArray<NSDictionary<NSString *, id> *> *methodTimings =
      observer.methodTimings ?: @[];
  if (methodTimings.count == 0) {
    return;
  }

  NSMutableDictionary<NSString *, NSNumber *> *classTotals =
      [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSNumber *> *classCounts =
      [NSMutableDictionary dictionary];
  for (NSDictionary<NSString *, id> *record in methodTimings) {
    NSString *className = record[@"class"] ?: @"(unknown)";
    NSTimeInterval duration = [record[@"duration"] doubleValue];
    classTotals[className] = @([classTotals[className] doubleValue] + duration);
    classCounts[className] = @([classCounts[className] unsignedIntegerValue] + 1);
  }

  NSArray<NSString *> *classesByDuration =
      [[classTotals allKeys] sortedArrayUsingComparator:^NSComparisonResult(
                              NSString *lhs, NSString *rhs) {
        double left = [classTotals[lhs] doubleValue];
        double right = [classTotals[rhs] doubleValue];
        if (left > right) return NSOrderedAscending;
        if (left < right) return NSOrderedDescending;
        return [lhs compare:rhs];
      }];

  NSArray<NSDictionary<NSString *, id> *> *methodsByDuration =
      [methodTimings sortedArrayUsingComparator:^NSComparisonResult(
                         NSDictionary<NSString *, id> *lhs,
                         NSDictionary<NSString *, id> *rhs) {
        double left = [lhs[@"duration"] doubleValue];
        double right = [rhs[@"duration"] doubleValue];
        if (left > right) return NSOrderedAscending;
        if (left < right) return NSOrderedDescending;
        return [lhs[@"method"] compare:rhs[@"method"]];
      }];

  fprintf(stderr, "\n=== Test Timing Summary ===\n");
  fprintf(stderr, "Class timings:\n");
  for (NSString *className in classesByDuration) {
    fprintf(stderr, "  %7.3fs  %4lu  %s\n",
            [classTotals[className] doubleValue],
            (unsigned long)[classCounts[className] unsignedIntegerValue],
            className.UTF8String);
  }

  fprintf(stderr, "Slowest test methods:\n");
  NSUInteger limit = MIN((NSUInteger)20, methodsByDuration.count);
  for (NSUInteger i = 0; i < limit; i++) {
    NSDictionary<NSString *, id> *record = methodsByDuration[i];
    fprintf(stderr, "  %7.3fs  %s/%s\n",
            [record[@"duration"] doubleValue],
            [record[@"class"] UTF8String],
            [record[@"method"] UTF8String]);
  }
}

static void PDSPrintFailureSummary(SimpleTestObserver *observer) {
  NSArray<NSDictionary<NSString *, id> *> *failedTests =
      observer.failedTests ?: @[];
  if (failedTests.count == 0) {
    return;
  }

  fprintf(stderr, "\n=== Failed Tests (%lu) ===\n",
          (unsigned long)failedTests.count);
  for (NSDictionary<NSString *, id> *failure in failedTests) {
    NSString *className = failure[@"class"] ?: @"(unknown)";
    NSString *method = failure[@"method"] ?: @"(unknown)";
    NSString *file = failure[@"file"] ?: @"(unknown)";
    NSUInteger line = [failure[@"line"] unsignedIntegerValue];
    NSString *description = failure[@"description"] ?: @"";

    fprintf(stderr, "  %s/%s\n    %s:%lu\n    %s\n",
            className.UTF8String,
            method.UTF8String,
            file.UTF8String,
            (unsigned long)line,
            description.UTF8String);
  }
}

int main(int argc, char *argv[]) {
  // Pre-scan for --json to suppress logger output before any initialization.
  BOOL jsonOutputEarly = NO;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--json") == 0) {
      jsonOutputEarly = YES;
      break;
    }
  }
  // When --json is active, redirect stdout to /dev/null during initialization
  // so the PDS logger doesn't pollute the JSON output.  We save the original
  // fd and restore it before writing the JSON result.
  int savedStdout = -1;
  if (jsonOutputEarly) {
    fflush(stdout);
    savedStdout = dup(fileno(stdout));
    freopen("/dev/null", "w", stdout);
  }

  fprintf(stderr, "test_main started\n");
  @autoreleasepool {
    // Ensure config defaults behave in non-interactive test mode.
    setenv("PDS_RUNNING_TESTS", "1", 1);
    if (getenv("PDS_USE_KEYCHAIN") == NULL) {
      setenv("PDS_USE_KEYCHAIN", "0", 1);
    }
    if (getenv("PDS_USE_SECURE_ENCLAVE") == NULL) {
      setenv("PDS_USE_SECURE_ENCLAVE", "0", 1);
    }
    if (getenv("PDS_USE_BIOMETRIC_PROTECTION") == NULL) {
      setenv("PDS_USE_BIOMETRIC_PROTECTION", "0", 1);
    }
    // Set master secret for PLC rotation key operations in tests
    if (getenv("PDS_MASTER_SECRET") == NULL) {
      setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    }
    // Skip PLC server registration in tests - use sans-IO DID generation
    if (getenv("PDS_PLC_URL") == NULL) {
      setenv("PDS_PLC_URL", "skip", 1);
    }
    // Isolate PLC rotation keys from the user's real key store.
    // Without this, sharedManager reads from the machine's default path and
    // fails to decrypt an existing key encrypted with a different secret.
    if (getenv("PDS_PLC_KEYS_DIR") == NULL) {
      NSString *tempKeysDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"garazyk-test-plc-keys"];
      [[NSFileManager defaultManager] removeItemAtPath:tempKeysDir error:NULL];
      [[NSFileManager defaultManager] createDirectoryAtPath:tempKeysDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
      setenv("PDS_PLC_KEYS_DIR", tempKeysDir.UTF8String, 1);
    }
    if (getenv("PDS_DATA_DIR") == NULL) {
      NSString *tempDataDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"garazyk-test-data"];
      [[NSFileManager defaultManager] removeItemAtPath:tempDataDir error:NULL];
      [[NSFileManager defaultManager] createDirectoryAtPath:tempDataDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
      setenv("PDS_DATA_DIR", tempDataDir.UTF8String, 1);
    }

    // Disable rate limiting for tests
    RateLimiterSetDisabledGlobally(YES);
    [RateLimiter sharedLimiter].enabled = NO;

    // Disable biometric protection for tests
    [ATProtoServiceConfiguration sharedConfiguration].useBiometricProtection = NO;
    // Disable keychain usage for tests (use in-memory/ephemeral keys)
    [ATProtoServiceConfiguration sharedConfiguration].useKeychain = NO;

    // Ensure listeners bind to loopback by default in tests to avoid macOS
    // Local Network permission prompts.
    if (getenv("PDS_LISTEN_HOST") == NULL) {
      setenv("PDS_LISTEN_HOST", "127.0.0.1", 1);
    }

    // Avoid CFNetwork trying to create a default on-disk cache under
    // ~/Library/Caches/AllTests.
    NSString *cacheDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"objpds-alltests-urlcache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURLCache *urlCache =
        [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                      diskCapacity:4 * 1024 * 1024
                                          diskPath:cacheDir];
    [NSURLCache setSharedURLCache:urlCache];

    if ([[[NSProcessInfo processInfo] environment][@"PDS_USE_NEW_REPOS"]
            isEqualToString:@"1"]) {
      [ATProtoServiceConfiguration sharedConfiguration].useNewRepositoryImplementation =
          YES;
      fprintf(stderr, "TESTING: Enabled new repository implementation\n");
    }

    NSArray *testClasses = @[
      @"PDSAccountServiceTests",
      @"MSTAtomicReferenceTests",
      @"MSTInteropTests",
      @"CARInteropTests",
      @"RepoCommitTests",
      @"ATProtoNetworkTransportTests",
      @"PLCOperationTests",
      @"PLCStoreTests",
      @"PLCReplicaStoreTests",
      @"PLCAuditorTests",
      @"PLCServerTests",
      @"PLCReplicaServerTests",
      @"OAuthPKCETests",
      @"OAuthConformanceTests",
      @"OAuthPublicClientTests",
      @"ATProtoOAuthClientMetadataTests",
      @"OAuthDPoPTests",
      @"JWTTests",
      @"OAuth2Tests",
      @"RefreshSecurityTests",
      @"SubscribeReposHandlerTests",
      @"GetServiceAuthMethodTests",
      @"XrpcHandlerTests",
      @"XrpcMethodRegistryTests",
      @"XrpcProxyTests",
      @"AdminAuthSyncTests",
      @"AdminAuthModerationTests",
      @"AdminAuthXrpcTests",
      @"AccountLifecycleXrpcTests",
      @"SyncEndpointXrpcTests",
      @"ModerationIdentityXrpcTests",
      @"LexiconResolveXrpcTests",
      @"RepoAuthRepoTests",
      @"RepoAuthServerTests",
      @"RepoAuthIdentityTests",
      @"RepoAuthNotificationTests",
      @"RepoAuthAppBskyTests",
      @"RepoAuthTempTests",
      @"PDSCLITests",
      @"PDSCLIServiceStubTests",
      @"ActorStoreTests",
      @"DatabasePoolTests",
      @"DatabaseMigrationTests",
      @"PDSMigrationManagerTests",
      @"PDSDatabaseLRUTests",
      @"PDSDatabaseAccountsTests",
      @"PDSDatabaseReposTests",
      @"PDSDatabaseBlocksTests",
      @"PDSDatabaseBlobsTests",
      @"PDSDatabaseRecordsTests",
      @"PDSDatabaseTransactionsTests",
      @"ATProtoDatabaseUtilitiesTests",
      @"ATProtoDatabaseQueryRunnerTests",
      @"PDSControllerTests",
      @"PDSPLCIntegrationTests",
      @"PDSAdminServiceTests",
      @"PDSAdminControllerTests",
      @"PDSBlobAuditManagerTests",
      @"PDSAdminAuthTests",
      @"GZAuthzManagerTests",
      @"AdminMiddlewareTests",
      @"ServiceDatabasesTests",
      @"RateLimiterTests",
      @"DIDResolverTests",
      @"ATProtoDIDDocumentFieldsSpaceTests",
      @"DIDValidationTests",
      @"HandleResolverTests",
      @"ATProtoHandleValidatorTests",
      @"IdentifierTests",
      @"TOTPTests",
      @"CryptoTests",
      @"PDSSpaceLtHashTests",
      @"PDSSpaceURIAndScopeTests",
      @"PDSSpaceStoreTests",
      @"PDSSpaceJWTTests",
      @"PDSSpaceCommitTests",
      @"AuthCryptoBase64URLTests",
      @"AuthCryptoECDSATests",
      @"AuthCryptoJWKTests",
      @"AuthCryptoDPoPTests",
      @"Base32UtilsTests",
      @"Secp256k1Tests",
      @"PDSNonceManagerTests",
      @"YubiKeyOATHTests",
      @"WebAuthnVerifierTests",
      @"WebAuthnDomainTests",
      @"PDSOpenSSLKeyManagerTests",
      @"OAuth2HandlerTests",
      @"OAuth2PreservationTests",
      @"OAuth2ATProtoClientTests",
      @"OAuth2ClientMetadataValidationTests",
      @"OAuth2OPTIONSHandlerTests",
      @"LexiconValidationTests",
      @"RecordPathValidationTests",
      @"ATProtoDateTimeTests",
      @"NSDateFormatterATProtoTests",
      @"XrpcInputValidationTests",
      @"GZInputValidatorTests",
      @"XrpcErrorResponseTests",
      @"BlobXrpcTests",
      @"BlobStorageTests",
      @"CloudStorageBlobProviderTests",
      @"CBORSecurityTests",
      @"JWTSecurityTests",
      @"HandleResolverSecurityTests",
      @"HandleResolverSSRFTests",
      @"WebSocketUpgradeHandlerTests",
      @"SSLPinningTests",
      @"HttpRouterTests",
      @"HttpRouteTrieTests",
      @"HttpRequestParsingTests",
      @"HttpBufferPoolTests",
      @"HttpChunkedBodyParserTests",
      @"HttpStreamingBodyTests",
      @"FirehoseTests",
      @"RelayClientTests",
      @"RelayConfigurationTests",
      @"RelayMetricsTests",
      @"RelayEventValidatorTests",
      @"RelayUpstreamManagerTests",
      @"RelayEventFilterTests",
      @"RelayEventBufferTests",
      @"RelayRepoStateManagerTests",
      @"RelayIntegrationTests",
      @"SessionStoreTests",
      @"AppDelegateTests",
      @"HttpServerTests",
      @"ATProtoHttpServerBuilderTests",
      @"WebSocketServerTests",
      @"MSTPersistenceTests",
      @"MSTRebalancingTests",
      @"MSTUTF8Tests",
      @"HttpResponseTests",
      @"ATProtoServiceConfigurationTests",
      @"PDSPhoneVerificationProviderTests",
      @"EventFormatterTests",
      @"PDSBlobServiceTests",
      @"PDSRecordServiceTests",
      @"PDSRecordTombstoneTests",
      @"PDSRepositoryServiceTests",
      @"PDSRelayServiceTests",
      @"ActorServiceTests",
      @"SearchIndexServiceTests",
      @"FeedServiceTests",
      @"GroupServiceTests",
      @"AgeAssuranceServiceTests",
      @"FeedSkeletonTests",
      @"NotificationServiceTests",
      @"RecordLifecycleHandlerTests",
      @"PDSCLIAccountCommandTests",
      @"PDSCLIRepoCommandTests",
      @"PDSCLIInviteCommandTests",
      @"PDSCLIDaemonCommandTests",
      @"PDSCLICommandEdgeCaseTests",
      @"PDSCLIServeCommandTests",
      @"PDSHealthCheckTests",
      @"HealthEndpointIntegrationTests",
      @"GZMetricsTests",
      @"OAuthServerMetadataTests",
      @"OAuthSessionTests",
      @"NodeInfoTests",
      @"ActorStoreCharacterizationTests",
      @"XrpcMethodRegistryCharacterizationTests",
      @"MSTCharacterizationTests",
      @"SessionCharacterizationTests",
      @"KeyManagerCharacterizationTests",
      @"KeyManagerSecurityTests",
      @"ATProtoErrorTests",
      @"ProtocolCompileTests",
      @"ATProtoServiceContainerTests",
      @"ATProtoDataPathsTests",
      @"ATProtoDIDDocumentFieldsTests",
      @"PDSAccountManagerTests",
      @"Base58Tests",
      @"PLCDIDKeyTests",
      @"PLCCacheDirectoryTests",
      @"WebSocketFrameParsingTests",
      @"WebSocketConnectionTests",
      @"AdminModerationAuthTests",
      @"OAuthIntegrationTests",
      @"CommitChainTests",
      @"FirehoseIntegrationTests",
      @"E2EDockerTests",
      @"PDSReplayCacheTests",
      @"StarterPackMembershipTests",
      @"PDSEmailHTTPClientTests",
      @"PDSKeychainSecretsProviderTests",
      @"PDSEnvironmentSecretsProviderTests",
      @"PDSSMTPEmailProviderTests",
      @"PDSMockEmailProviderTests",
      @"PDSResendEmailProviderTests",
      @"ProductionSecurityTests",
      @"FirehoseConformanceTests",
      @"FirehoseProtocolSessionTests",
      @"ServiceDatabasesPruningTests",
      @"CoverageGapTests",
      @"DIDPLCResolverTests",
      @"PLCRotationKeyManagerTests",
      @"ATProtoNetworkTransportLinuxTests",
      @"XRPCErrorTests",
      @"XrpcErrorHelperTests",
      @"RateLimitingTests",
      @"GZXrpcRouteSupportTests",
      @"GZCommandLineOptionsTests",
      @"GZConfigurationParsingTests",
      @"RepoDescribeRepoTests",
      @"SSRFValidatorTests",
      @"HttpParsingTests",
      @"HttpRetryPolicyTests",
      @"WebSocketFrameCharacterizationTests",
      @"WebSocketStateCharacterizationTests",
      @"WebSocketCodecTests",
      @"WebSocketCodecFragmentationTests",
      @"WebSocketHeartbeatPolicyTests",
      @"HttpConnectionCharacterizationTests",
      @"Http1PipelinePolicyTests",
      @"Http1ParserTests",
      @"HttpProtocolSessionTests",
      @"XrpcAppBskyAgeAssuranceTests",
      @"XrpcChatBskyActorTests",
      @"XrpcChatBskyConvoTests",
      @"LexiconValidatorInteropTests",
      @"AtprotoInteropFixturesTests",
      @"SyntaxInteropTests",
      @"MSTInteropTests",
      @"CARInteropTests",
      @"AppViewDatabaseTests",
      @"AppViewIngestEngineTests",
      @"AppViewBackfillTests",
      @"AppViewBackfillWorkerTests",
      @"MikrusSourceSpecTests",
      @"MikrusDatabaseTests",
      @"MikrusXrpcRoutePackTests",
      @"MikrusRuntimeTests",
      @"IPLDBlockIntegrityTests",
      @"SecItemPersistenceTests",
      @"Arc4randomTests",
      @"CFReleaseTests",
      @"PlatformGuardTests",
      @"PDSWebSocketTransportTests",
      @"PDSWebSocketServerTests",
      @"HttpProtocolDriverTests",
      @"HttpResponseSenderTests",
      @"HttpConnectionIOCoordinatorTests",
      @"XrpcAppBskyActorTests",
      @"XrpcAppBskyFeedTests",
      @"XrpcAppBskyFeedPackTests",
      @"XrpcAppBskyGraphTests",
      @"XrpcAppBskyNotificationTests",
      @"XrpcAppBskyNotificationPackTests",
      @"ATProtoVideoXrpcPackTests",
      @"PDSVideoJobsTests",
      @"ATProtoVideoTranscoderTests",
      @"ATProtoVideoTranscoderIntegrationTests",
      @"ATProtoVideoThumbnailGeneratorTests",
      @"ATProtoVideoThumbnailGeneratorIntegrationTests",
      @"ATProtoVideoWorkerTests",
      @"ATProtoVideoWorkerIntegrationTests",
      @"ATProtoVideoHLSGeneratorTests",
      @"AppViewVideoUriBuilderTests",
      @"XrpcAppBskyBookmarksTests",
      @"XrpcAppBskyContactTests",
      @"XrpcAppBskyDraftsTests",
      @"XrpcAppBskyUnspeccedTests",
      @"CIDTests",
      @"TIDTests",
      @"CBORSerializationTests",
      @"ATProtoValidatorTests",
      @"ATProtoBase32Tests",
      @"ATProtoCoreTests",
      @"ATProtoDagCBORTests",
      @"AppViewRelevanceSetTests",
      @"DeploymentReadinessTests",
      @"EmailIntegrationTests",
      @"FederationClientTests",
      @"FollowersCountIntegrationTests",
      @"MSTDiffTests",
      @"MSTPreorderTests",
      @"MSTPreorderFixtureTests",
      @"STARPreorderTests",
      @"MimeTypeValidatorTests",
      @"MultiTenantDatabaseTests",
      @"OAuth2EndpointTests",
      @"OAuth2IntrospectionTests",
      @"PDSApplicationTests",
      @"PDSCLIHealthCommandTests",
      @"PDSCLINukeCommandTests",
      @"PDSDatabaseIntegrationTests",
      @"PDSHttpPDSAdminRoutePackTests",
      @"ATProtoHttpXrpcRoutePackTests",
      @"XrpcRoutePackTests",
      @"XrpcSpacePackTests",
      @"XrpcSpaceRecoveryTestPackTests",
      @"GZLoggerPerformanceTests",
      @"RelayXrpcRoutePackTests",
      @"RelayAPIHandlerTests",
      @"RelayDownstreamHandlerTests",
      @"SecurityHardeningTests",
      @"NetworkSecurityHardeningTests",
      @"XrpcAppBskyGraphHelpersTests",
      @"XrpcChatBskyGroupTests",
      @"XrpcIntegrationTests",
      @"XrpcToolsOzoneTests",
      @"UIAuthManagerTests",
      @"UIBackendClientTests",
      @"UIServerRuntimeTests",
      @"GarazykUICommandTests",
      @"UILabAuthTests",
      @"UILabIntegrationTests",
      @"PDSRegistrationGateTests",
      @"GZProviderRegistryTests",
      @"PDSTwilioPhoneVerificationProviderTests",
      @"PDSVonagePhoneVerificationProviderTests",
      @"PDSPlivoPhoneVerificationProviderTests",
      @"PDSTelegramGatewayPhoneVerificationProviderTests",
      @"GermRecordTests",
      @"GermMailboxServiceTests",
      @"ChatConfigurationTests",
      @"ChatServiceTests",
      @"ModerationServiceTests",
      @"GermIdentityServiceTests",
      @"ATProtoCIDTests",
      @"ATProtoDagCBOREdgeCaseTests",
      @"ATProtoTIDTests",
      @"OAuthMetadataComplianceTests",
      @"OAuthMetadataConsistencyTests",
      @"OAuthOriginResolutionTests",
      @"OAuthOriginTests",
      @"PLCServerHeaderTests",
      @"Phase2SecurityIntegrationTests",
      @"XrpcIdentityResolutionTests",
      @"ThreadgateServiceTests",
      @"ThreadgateMigrationTests",
      @"XRPCContractAuditTests",
      @"ChatGroupLifecycleTests",
      @"ATProtoMediaCoreTests",
      @"JelczCLITests",
      @"JelczDatabaseTests",
      @"ATProtoMediaServiceRuntimeTests",
      @"BeskidConfigurationTests",
      @"BeskidDatabaseTests",
      @"BeskidXrpcRoutePackTests",
      // ── New tests (testing gaps) ──
      @"PDSDatabaseWebAuthnTests",
      @"PDSDatabaseModerationTests",
      @"PDSDatabaseAdminConfigTests",
      @"PDSDatabaseAdminAuditTests",
      @"PDSDatabaseOAuthClientsTests",
      @"PDSDatabaseVideoJobsTests",
      @"PDSDatabaseReportsTests",
      @"PDSSystemDiagnosticsHandlerTests",
      @"PDSSequencerHealthHandlerTests",
      @"PDSBlobAuditHandlerTests",
      @"PDSBlobAuditOperationTests",
      @"PDSSequencerAnalyticsCollectorTests",
      @"AppViewIndexerTests",
      @"AppViewHookTests",
      @"PDSSQLiteRepositoryTests",
      @"OAuthProviderTests",
      @"OAuthClientAuthPolicyTests",
      @"PDSSecondFactorServiceTests",
      @"PDSAppleKeyManagerTests",
      @"ATProtoVideoProcessorTests",
      @"AVFoundationTranscoderTests",
      @"FFmpegTranscoderTests",
      @"JelczConfigurationTests",
      @"VideoRemoteBlobUploaderTests",
      @"VideoLocalBlobUploaderTests",
      @"VideoJWTAuthProviderTests",
      @"VideoPDSAuthProviderTests",
      @"ATProtoVideoWorkerDefaultsTests",
      @"ATProtoVideoTranscoderUnitTests",
      @"ATProtoVideoWorkerConstantsTests",
      @"ATProtoVideoXrpcPackValidationTests",
      @"VideoHLSResultTests",
      @"PDSCLIDispatcherTests",
      @"PDSCLIAdminCommandTests",
      @"PDSCLIOAuthCommandTests",
      @"PDSCLIRegisterAllTests"
    ];

    SimpleTestObserver *observer = [[SimpleTestObserver alloc] init];

    XCTestObservationCenter *center =
        [XCTestObservationCenter sharedTestObservationCenter];
    [center addTestObserver:observer];

    // Parse command line arguments
    NSMutableArray<NSString *> *filterPatterns = [NSMutableArray array];
    NSMutableArray<NSString *> *excludePatterns = [NSMutableArray array];
    NSMutableArray<NSString *> *includeCategories = [NSMutableArray array];
    NSMutableArray<NSString *> *excludeCategories = [NSMutableArray array];
    BOOL listMode = NO;
    BOOL listVerbose = NO;
    BOOL jsonOutput = NO;
    BOOL shuffleMode = NO;
    NSUInteger shuffleSeed = 0;
    NSTimeInterval perTestTimeout = 0;
    PDSGatedMode gatedMode = PDSGatedModeSkip;
    NSString *legacyFilter = nil;

    for (int i = 1; i < argc; i++) {
      NSString *arg = [NSString stringWithUTF8String:argv[i]];

      // Legacy XCTest filter
      if ([arg isEqualToString:@"-XCTest"] && i + 1 < argc) {
        legacyFilter = [NSString stringWithUTF8String:argv[i + 1]];
        i++;
        continue;
      }

      // --filter / -f
      if (([arg isEqualToString:@"--filter"] || [arg isEqualToString:@"-f"]) && i + 1 < argc) {
        [filterPatterns addObject:[NSString stringWithUTF8String:argv[i + 1]]];
        i++;
        continue;
      }

      // --exclude / -e
      if (([arg isEqualToString:@"--exclude"] || [arg isEqualToString:@"-e"]) && i + 1 < argc) {
        [excludePatterns addObject:[NSString stringWithUTF8String:argv[i + 1]]];
        i++;
        continue;
      }

      // --category / -c
      if (([arg isEqualToString:@"--category"] || [arg isEqualToString:@"-c"]) && i + 1 < argc) {
        NSString *cats = [NSString stringWithUTF8String:argv[i + 1]];
        for (NSString *cat in [cats componentsSeparatedByString:@","]) {
          NSString *trimmed = [cat stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if (trimmed.length > 0) [includeCategories addObject:trimmed];
        }
        i++;
        continue;
      }

      // --exclude-category
      if ([arg isEqualToString:@"--exclude-category"] && i + 1 < argc) {
        NSString *cats = [NSString stringWithUTF8String:argv[i + 1]];
        for (NSString *cat in [cats componentsSeparatedByString:@","]) {
          NSString *trimmed = [cat stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if (trimmed.length > 0) [excludeCategories addObject:trimmed];
        }
        i++;
        continue;
      }

      // --list / -l
      if ([arg isEqualToString:@"--list"] || [arg isEqualToString:@"-l"]) {
        listMode = YES;
        continue;
      }

      // --verbose / -v (enables method listing in --list mode)
      if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
        listVerbose = YES;
        continue;
      }

      // --json
      if ([arg isEqualToString:@"--json"]) {
        jsonOutput = YES;
        continue;
      }

      // --shuffle
      if ([arg isEqualToString:@"--shuffle"]) {
        shuffleMode = YES;
        if (shuffleSeed == 0) {
          shuffleSeed = (NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000);
        }
        continue;
      }

      // --seed
      if ([arg isEqualToString:@"--seed"] && i + 1 < argc) {
        shuffleSeed = (NSUInteger)[[NSString stringWithUTF8String:argv[i + 1]] integerValue];
        shuffleMode = YES;
        i++;
        continue;
      }

      // --timeout / -t
      if (([arg isEqualToString:@"--timeout"] || [arg isEqualToString:@"-t"]) && i + 1 < argc) {
        perTestTimeout = (NSTimeInterval)[[NSString stringWithUTF8String:argv[i + 1]] doubleValue];
        i++;
        continue;
      }

      // --gated [MODE] or --gated=MODE
      if ([arg isEqualToString:@"--gated"] && i + 1 < argc) {
        NSString *mode = [NSString stringWithUTF8String:argv[i + 1]];
        if ([mode isEqualToString:@"run"]) {
          gatedMode = PDSGatedModeRun;
        } else if ([mode isEqualToString:@"include"]) {
          gatedMode = PDSGatedModeMarkSkip;
        } else {
          gatedMode = PDSGatedModeSkip;
        }
        i++;
        continue;
      }
      if ([arg hasPrefix:@"--gated="]) {
        NSString *mode = [arg substringFromIndex:8];
        if ([mode isEqualToString:@"run"]) {
          gatedMode = PDSGatedModeRun;
        } else if ([mode isEqualToString:@"include"]) {
          gatedMode = PDSGatedModeMarkSkip;
        } else {
          gatedMode = PDSGatedModeSkip;
        }
        continue;
      }

      // --help
      if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        fprintf(stderr, "Usage: AllTests [options]\n");
        fprintf(stderr, "\n");
        fprintf(stderr, "Filtering:\n");
        fprintf(stderr, "  -f, --filter PATTERN     Include tests matching glob pattern\n");
        fprintf(stderr, "  -e, --exclude PATTERN    Exclude tests matching glob pattern\n");
        fprintf(stderr, "  -c, --category CAT       Include tests in category (comma-separated)\n");
        fprintf(stderr, "      --exclude-category   Exclude tests in category\n");
        fprintf(stderr, "  -XCTest FILTER           Legacy XCTest filter (ClassName[/method])\n");
        fprintf(stderr, "\n");
        fprintf(stderr, "Execution:\n");
        fprintf(stderr, "      --gated MODE         Gated test mode: skip (default), run, include\n");
        fprintf(stderr, "      --gated=MODE         Equivalent to --gated MODE\n");
        fprintf(stderr, "  -t, --timeout SECS       Per-test timeout in seconds (0 = none)\n");
        fprintf(stderr, "      --shuffle            Randomize test order\n");
        fprintf(stderr, "      --seed N             Set shuffle seed for reproducibility\n");
        fprintf(stderr, "\n");
        fprintf(stderr, "Output:\n");
        fprintf(stderr, "  -l, --list               List tests without running\n");
        fprintf(stderr, "  -v, --verbose            Verbose listing (show methods)\n");
        fprintf(stderr, "      --json               JSON output\n");
        fprintf(stderr, "  -h, --help               Show this help\n");
        return 0;
      }
    }

    // When JSON output is active, or PDS_TEST_QUIET is set, suppress the PDS logger.
    if (jsonOutput || PDSEnvEnabled("PDS_TEST_QUIET")) {
      [GZLogger sharedLogger].logLevel = GZLogLevelError;
    }

    // Merge legacy -XCTest filter into the new filter system
    if (legacyFilter) {
      // Legacy filter supports exact class names and Class/method syntax.
      // Add each token as a filter pattern.
      for (NSString *token in [legacyFilter componentsSeparatedByString:@","]) {
        NSString *trimmed = [token stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
          NSRange slash = [trimmed rangeOfString:@"/"];
          if (slash.location == NSNotFound) {
            [filterPatterns addObject:trimmed];
          } else {
            // Class/method — add as exact class name
            [filterPatterns addObject:[trimmed substringToIndex:slash.location]];
          }
        }
      }
    }

    NSDictionary<NSString *, id> *parsedFilter = PDSParseTestFilter(legacyFilter);

    if (PDSEnvEnabled("PDS_TEST_REGISTRATION_AUDIT")) {
      return PDSRunRegistrationAudit(testClasses) ? 0 : 2;
    }

    // ── Determine which classes to include ──────────────────────────────

    // If filter patterns contain glob characters, expand them against the
    // full class list.  Otherwise they are exact matches.
    BOOL hasFilterPatterns = filterPatterns.count > 0;
    BOOL hasExcludePatterns = excludePatterns.count > 0;
    BOOL hasIncludeCategories = includeCategories.count > 0;
    BOOL hasExcludeCategories = excludeCategories.count > 0;

    // Helper: does a class pass the filter/include criteria?
    BOOL (^classPassesFilter)(NSString *) = ^BOOL(NSString *className) {
      // Legacy exact-match filter (from -XCTest)
      if (parsedFilter && !PDSFilterIncludesClass(parsedFilter, className)) {
        return NO;
      }
      // New glob filter
      if (hasFilterPatterns && !PDSAnyPatternMatches(filterPatterns, className)) {
        return NO;
      }
      // Category include
      if (hasIncludeCategories) {
        NSString *cat = PDSCategoryForClass(className);
        BOOL found = NO;
        for (NSString *inc in includeCategories) {
          if ([inc isEqualToString:cat] || [inc isEqualToString:@"*"]) {
            found = YES;
            break;
          }
        }
        if (!found) return NO;
      }
      // Category exclude
      if (hasExcludeCategories) {
        NSString *cat = PDSCategoryForClass(className);
        for (NSString *exc in excludeCategories) {
          if ([exc isEqualToString:cat]) return NO;
        }
      }
      // Exclude pattern
      if (hasExcludePatterns && PDSAnyPatternMatches(excludePatterns, className)) {
        return NO;
      }
      return YES;
    };

    // ── List mode ───────────────────────────────────────────────────────

    if (listMode) {
      NSUInteger classCount = 0;
      NSUInteger methodCount = 0;
      NSMutableArray<NSString *> *listedCategories = [NSMutableArray array];
      for (NSString *className in testClasses) {
        if (!classPassesFilter(className)) continue;
        NSString *cat = PDSCategoryForClass(className) ?: @"(unknown)";
        if (![listedCategories containsObject:cat]) {
          [listedCategories addObject:cat];
        }
        NSString *gateName = PDSGateNameForClass(className);
        NSString *gateTag = gateName ? [NSString stringWithFormat:@" [gated:%@]", gateName] : @"";
        if (listVerbose) {
          fprintf(stdout, "%s (%s)%s\n", className.UTF8String, cat.UTF8String, gateTag.UTF8String);
          Class testClass = NSClassFromString(className);
          if (testClass) {
            NSArray *methods = discoverTestMethodsForClass(testClass);
            for (NSString *method in methods) {
              fprintf(stdout, "  %s\n", method.UTF8String);
              methodCount++;
            }
          }
        } else {
          fprintf(stdout, "%s%s\n", className.UTF8String, gateTag.UTF8String);
        }
        classCount++;
      }
      fprintf(stderr, "\n%lu classes", (unsigned long)classCount);
      if (listVerbose) fprintf(stderr, ", %lu methods", (unsigned long)methodCount);
      fprintf(stderr, "\nCategories: %s\n", [listedCategories componentsJoinedByString:@", "].UTF8String);
      return 0;
    }

    // ── Build test suite ────────────────────────────────────────────────

    XCTestSuite *mainSuite = [XCTestSuite testSuiteWithName:@"All Tests"];
    NSMutableArray<NSString *> *skippedClasses = [NSMutableArray array];
    NSMutableArray<NSString *> *includedClasses = [NSMutableArray array];

    for (NSString *className in testClasses) {
      if (!classPassesFilter(className)) continue;

      NSString *skipReason = PDSSkipReasonForClass(className, gatedMode);
      if (skipReason) {
        [skippedClasses addObject:
            [NSString stringWithFormat:@"%@ (%@)", className, skipReason]];
        continue;
      }

      Class testClass = NSClassFromString(className);
      if (testClass) {
        NSArray *methodNames = discoverTestMethodsForClass(testClass);
        if (methodNames.count > 0) {
          XCTestSuite *classSuite = [XCTestSuite testSuiteWithName:className];
          NSUInteger addedMethodCount = 0;
          for (NSString *methodName in methodNames) {
            // Legacy method-level filter
            if (parsedFilter && !PDSFilterIncludesMethod(parsedFilter, className, methodName)) {
              continue;
            }
            SEL selector = NSSelectorFromString(methodName);
            XCTestCase *testCase =
                [[testClass alloc] initWithSelector:selector];
            [classSuite addTest:testCase];
            addedMethodCount++;
          }
          if (addedMethodCount > 0) {
            [mainSuite addTest:classSuite];
            [includedClasses addObject:className];
          } else if (parsedFilter || hasFilterPatterns) {
            NSLog(@"Warning: No selected test methods found for %@", className);
          }
        }
      } else {
        if (!parsedFilter && !hasFilterPatterns) {
          NSLog(@"Warning: Test class %@ not found", className);
        }
      }
    }

    // ── Shuffle ─────────────────────────────────────────────────────────

    if (shuffleMode) {
      // Shuffle the class suites within the main suite
      NSMutableArray *shuffled = [mainSuite.tests mutableCopy];
      // Simple Fisher-Yates shuffle with the seed
      NSUInteger seed = shuffleSeed;
      for (NSUInteger i = shuffled.count - 1; i > 0; i--) {
        seed = seed * 1103515245 + 12345;
        NSUInteger j = (seed / 65536) % (i + 1);
        [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
      }
      // Rebuild suite in shuffled order
      XCTestSuite *shuffledSuite = [XCTestSuite testSuiteWithName:mainSuite.name];
      for (XCTest *test in shuffled) {
        [shuffledSuite addTest:test];
      }
      mainSuite = shuffledSuite;
      fprintf(stderr, "Shuffle seed: %lu\n", (unsigned long)shuffleSeed);
    }

    // ── Run tests ───────────────────────────────────────────────────────

    NSLog(@"\n=== Starting Test Suite: %@ ===", mainSuite.name);
    NSLog(@"Test suites: %lu (skipped: %lu)",
          (unsigned long)mainSuite.tests.count,
          (unsigned long)skippedClasses.count);

    NSDate *suiteStart = [NSDate date];

    if (perTestTimeout > 0) {
      // Per-test timeout enforcement: run each test case individually with
      // a watchdog on a background queue.  If the test exceeds the limit,
      // the watchdog fires and we record a timeout failure.  The test still
      // runs to completion (we can't safely kill it), but the timeout is
      // recorded in the observer and the JSON output.
      dispatch_queue_t watchdogQueue = dispatch_queue_create(
          "com.garazyk.test-timeout", DISPATCH_QUEUE_SERIAL);
      NSUInteger timeoutCount = 0;

      for (XCTest *classTest in mainSuite.tests) {
        XCTestSuite *classSuite = (XCTestSuite *)classTest;
        XCTestSuite *timedClassSuite =
            [XCTestSuite testSuiteWithName:classSuite.name];
        for (XCTest *test in classSuite.tests) {
          if (![test isKindOfClass:[XCTestCase class]]) continue;
          XCTestCase *testCase = (XCTestCase *)test;

          __block volatile BOOL timedOut = NO;
          dispatch_block_t timeoutBlock = dispatch_block_create(0, ^{
            timedOut = YES;
          });
          dispatch_after(
              dispatch_time(DISPATCH_TIME_NOW,
                            (int64_t)(perTestTimeout * NSEC_PER_SEC)),
              watchdogQueue, timeoutBlock);

          // Run the test case within a suite so XCTestObservation
          // callbacks fire correctly.
          XCTestSuite *singleSuite =
              [XCTestSuite testSuiteWithName:@"_timeout_single"];
          [singleSuite addTest:testCase];
          [singleSuite performTest:nil];

          dispatch_block_cancel(timeoutBlock);

          if (timedOut) {
            timeoutCount++;
            NSString *cls = PDSClassNameFromTestCase(testCase);
            NSString *method = PDSMethodNameFromTestCase(testCase);
            NSString *msg = [NSString stringWithFormat:
                @"TIMEOUT: %@/%@ exceeded %.1fs limit",
                cls, method, perTestTimeout];
            observer.failureCount++;
            [observer.failedTests addObject:@{
              @"class" : cls,
              @"method" : method,
              @"file" : @"(timeout)",
              @"line" : @(0),
              @"description" : msg
            }];
            NSLog(@"%@", msg);
          }
        }
      }

      if (timeoutCount > 0) {
        NSLog(@"%lu tests exceeded the %.1fs timeout",
              (unsigned long)timeoutCount, perTestTimeout);
      }
    } else {
      [mainSuite performTest:nil];
    }

    NSTimeInterval suiteDuration = -[suiteStart timeIntervalSinceNow];

    // ── Output ──────────────────────────────────────────────────────────

    // Restore stdout if we redirected it for --json mode
    if (jsonOutput && savedStdout >= 0) {
      fflush(stdout);
      dup2(savedStdout, fileno(stdout));
      close(savedStdout);
      savedStdout = -1;
    }

    if (jsonOutput) {
      NSMutableDictionary *jsonResult = [NSMutableDictionary dictionary];
      jsonResult[@"total"] = @(observer.testCount);
      jsonResult[@"failed"] = @(observer.failureCount);
      jsonResult[@"duration_s"] = @(suiteDuration);
      jsonResult[@"shuffle_seed"] = @(shuffleSeed);

      NSMutableArray *tests = [NSMutableArray array];
      for (NSDictionary *timing in observer.methodTimings) {
        NSString *cls = timing[@"class"] ?: @"(unknown)";
        NSString *method = timing[@"method"] ?: @"(unknown)";
        NSTimeInterval dur = [timing[@"duration"] doubleValue];
        // Check if this test failed
        BOOL failed = NO;
        NSString *failureDesc = nil;
        for (NSDictionary *fail in observer.failedTests) {
          if ([fail[@"class"] isEqualToString:cls] &&
              [fail[@"method"] isEqualToString:method]) {
            failed = YES;
            failureDesc = fail[@"description"];
            break;
          }
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"class"] = cls;
        entry[@"method"] = method;
        entry[@"status"] = failed ? @"failed" : @"passed";
        entry[@"duration_s"] = @(dur);
        if (failed && failureDesc) {
          entry[@"failure"] = failureDesc;
        }
        [tests addObject:entry];
      }
      jsonResult[@"tests"] = tests;

      if (skippedClasses.count > 0) {
        jsonResult[@"skipped_classes"] = skippedClasses;
      }

      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonResult
                                                        options:NSJSONWritingPrettyPrinted
                                                          error:nil];
      if (jsonData) {
        fprintf(stdout, "%s\n", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding].UTF8String);
      }
    } else {
      PDSPrintTimingSummary(observer);
      PDSPrintFailureSummary(observer);

      NSLog(@"\n=== Test Suite Finished ===");
      NSLog(@"Tests run: %d", observer.testCount);
      NSLog(@"Failures: %d", observer.failureCount);
      NSLog(@"Duration: %.3fs", suiteDuration);
      if (shuffleMode) {
        NSLog(@"Shuffle seed: %lu", (unsigned long)shuffleSeed);
      }
      if (skippedClasses.count > 0) {
        NSLog(@"Skipped gated test classes: %lu", (unsigned long)skippedClasses.count);
        for (NSString *skipped in skippedClasses) {
          NSLog(@"  %@", skipped);
        }
      }
    }

    return observer.failureCount > 0 ? 1 : 0;
  }
}
