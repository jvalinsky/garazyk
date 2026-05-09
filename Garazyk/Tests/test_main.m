#import <Foundation/Foundation.h>
#include <stdlib.h>

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
#import "App/PDSConfiguration.h"
#import "Auth/OAuthConformanceTests.h"
#import "Auth/OAuthPublicClientTests.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import <objc/runtime.h>

@interface SimpleTestObserver : NSObject <XCTestObservation>
@property(nonatomic, assign) int failureCount;
@property(nonatomic, assign) int testCount;
@property(nonatomic, assign) int unexpectedFailureCount;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *testStartTimes;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *methodTimings;
@end

static NSString *PDSClassNameFromTestCase(XCTestCase *testCase) {
#ifdef __APPLE__
  NSString *name = testCase.name ?: @"";
#else
  NSString *name = @"";
#endif
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
#ifdef __APPLE__
  NSString *name = testCase.name ?: @"";
#else
  NSString *name = @"";
#endif
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
  }
  return self;
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

static NSSet<NSString *> *PDSIntegrationTestClasses(void) {
  static NSSet<NSString *> *classes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    classes = [NSSet setWithArray:@[
      @"PDSPLCIntegrationTests",
      @"PDSIntegrationTests",
      @"CommitChainTests",
      @"RelayIntegrationTests",
      @"OAuthIntegrationTests",
      @"EmailIntegrationTests",
      @"FirehoseIntegrationTests",
      @"FollowersCountIntegrationTests",
      @"MultiTenantDatabaseTests",
      @"PDSDatabaseIntegrationTests",
      @"XrpcIntegrationTests",
      @"E2EDockerTests",
      @"UILabIntegrationTests",
      @"ATProtoVideoTranscoderIntegrationTests",
      @"ATProtoVideoThumbnailGeneratorIntegrationTests",
      @"ATProtoVideoWorkerIntegrationTests",
      @"SSLPinningTests"
    ]];
  });
  return classes;
}

static NSSet<NSString *> *PDSSocketTestClasses(void) {
  static NSSet<NSString *> *classes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    classes = [NSSet setWithArray:@[
      @"HealthEndpointIntegrationTests",
      @"HttpServerTests",
      @"OAuth2EndpointTests",
      @"PDSApplicationTests",
      @"PDSHttpServerBuilderTests",
      @"PLCServerTests",
      @"PLCReplicaServerTests",
      @"PDSWebSocketServerTests",
      @"PDSWebSocketTransportTests",
      @"WebSocketServerTests"
    ]];
  });
  return classes;
}

static NSString *PDSSkipReasonForClass(NSString *className) {
  BOOL runIntegration = PDSEnvEnabled("PDS_RUN_INTEGRATION_TESTS");
  BOOL runSocket = runIntegration || PDSEnvEnabled("PDS_RUN_SOCKET_TESTS");

  if ([PDSSocketTestClasses() containsObject:className] && !runSocket) {
    return @"set PDS_RUN_SOCKET_TESTS=1";
  }
  if ([PDSIntegrationTestClasses() containsObject:className] &&
      !runIntegration) {
    return @"set PDS_RUN_INTEGRATION_TESTS=1";
  }
  return nil;
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

int main(int argc, char *argv[]) {
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

    // Disable rate limiting for tests
    RateLimiterSetDisabledGlobally(YES);
    [RateLimiter sharedLimiter].enabled = NO;

    // Disable biometric protection for tests
    [PDSConfiguration sharedConfiguration].useBiometricProtection = NO;
    // Disable keychain usage for tests (use in-memory/ephemeral keys)
    [PDSConfiguration sharedConfiguration].useKeychain = NO;

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
      [PDSConfiguration sharedConfiguration].useNewRepositoryImplementation =
          YES;
      fprintf(stderr, "TESTING: Enabled new repository implementation\n");
    }

    NSArray *testClasses = @[
      @"PDSAccountServiceTests",
      @"MSTInteropTests",
      @"CARInteropTests",
      @"RepoCommitTests",
      @"PDSNetworkTransportTests",
      @"PLCOperationTests",
      @"PLCStoreTests",
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
      @"PDSControllerTests",
      @"PDSPLCIntegrationTests",
      @"PDSAdminServiceTests",
      @"PDSAdminControllerTests",
      @"PDSBlobAuditManagerTests",
      @"PDSAdminAuthTests",
      @"PDSAuthzManagerTests",
      @"AdminMiddlewareTests",
      @"ServiceDatabasesTests",
      @"RateLimiterTests",
      @"DIDResolverTests",
      @"DIDValidationTests",
      @"HandleResolverTests",
      @"ATProtoHandleValidatorTests",
      @"IdentifierTests",
      @"TOTPTests",
      @"CryptoTests",
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
      @"PDSInputValidatorTests",
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
      @"PDSHttpServerBuilderTests",
      @"WebSocketServerTests",
      @"MSTPersistenceTests",
      @"MSTRebalancingTests",
      @"MSTUTF8Tests",
      @"HttpResponseTests",
      @"PDSConfigurationTests",
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
      @"AppViewServiceTests",
      @"PDSCLIAccountCommandTests",
      @"PDSCLIRepoCommandTests",
      @"PDSCLIInviteCommandTests",
      @"PDSCLIDaemonCommandTests",
      @"PDSCLICommandEdgeCaseTests",
      @"PDSCLIServeCommandTests",
      @"PDSCLIRelayCommandTests",
      @"PDSHealthCheckTests",
      @"HealthEndpointIntegrationTests",
      @"PDSMetricsTests",
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
      @"PDSServiceContainerTests",
      @"PDSDataPathsTests",
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
      @"PDSNetworkTransportLinuxTests",
      @"XRPCErrorTests",
      @"XrpcErrorHelperTests",
      @"RateLimitingTests",
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
      @"MimeTypeValidatorTests",
      @"MultiTenantDatabaseTests",
      @"OAuth2EndpointTests",
      @"OAuth2IntrospectionTests",
      @"PDSApplicationTests",
      @"PDSCLIHealthCommandTests",
      @"PDSCLINukeCommandTests",
      @"PDSDatabaseIntegrationTests",
      @"PDSHttpPDSAdminRoutePackTests",
      @"PDSLoggerPerformanceTests",
      @"RelayAPIHandlerTests",
      @"RelayDownstreamHandlerTests",
      @"SecurityHardeningTests",
      @"XrpcAppBskyGraphHelpersTests",
      @"XrpcChatBskyGroupTests",
      @"XrpcIntegrationTests",
      @"XrpcToolsOzoneTests",
      @"UIAuthManagerTests",
      @"UIBackendClientTests",
      @"UIServerRuntimeTests",
      @"UILabAuthTests",
      @"UILabIntegrationTests"
    ];

    SimpleTestObserver *observer = [[SimpleTestObserver alloc] init];

#ifdef __APPLE__
    XCTestObservationCenter *center =
        [XCTestObservationCenter sharedTestObservationCenter];
    [center addTestObserver:observer];
#endif

    // Parse command line arguments for filtering
    NSString *testFilter = nil;
    for (int i = 1; i < argc; i++) {
      NSString *arg = [NSString stringWithUTF8String:argv[i]];
      if ([arg isEqualToString:@"-XCTest"] && i + 1 < argc) {
        testFilter = [NSString stringWithUTF8String:argv[i + 1]];
        break;
      }
    }
    NSDictionary<NSString *, id> *parsedFilter = PDSParseTestFilter(testFilter);

    if (PDSEnvEnabled("PDS_TEST_REGISTRATION_AUDIT")) {
      return PDSRunRegistrationAudit(testClasses) ? 0 : 2;
    }

    XCTestSuite *mainSuite = [XCTestSuite testSuiteWithName:@"All Tests"];
    NSMutableArray<NSString *> *skippedClasses = [NSMutableArray array];

    for (NSString *className in testClasses) {
      // Apply filter if present
      if (!PDSFilterIncludesClass(parsedFilter, className)) {
        continue;
      }

      NSString *skipReason = PDSSkipReasonForClass(className);
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
            if (!PDSFilterIncludesMethod(parsedFilter, className, methodName)) {
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
          } else if (parsedFilter) {
            NSLog(@"Warning: No selected test methods found for %@", className);
          }
        }
      } else {
        // Only warn if we are not filtering, or if this is the specific class
        // we asked for
        if (!parsedFilter || PDSFilterIncludesClass(parsedFilter, className)) {
          NSLog(@"Warning: Test class %@ not found", className);
        }
      }
    }

    NSLog(@"\n=== Starting Test Suite: %@ ===", mainSuite.name);
    NSLog(@"Test suites: %lu", (unsigned long)mainSuite.tests.count);

    [mainSuite performTest:nil];
    PDSPrintTimingSummary(observer);

    NSLog(@"\n=== Test Suite Finished ===");
    NSLog(@"Tests run: %d", observer.testCount);
    NSLog(@"Failures: %d\n", observer.failureCount);
    if (skippedClasses.count > 0) {
      NSLog(@"Skipped gated test classes: %lu", (unsigned long)skippedClasses.count);
      for (NSString *skipped in skippedClasses) {
        NSLog(@"  %@", skipped);
      }
    }

    return observer.failureCount > 0 ? 1 : 0;
  }
}
