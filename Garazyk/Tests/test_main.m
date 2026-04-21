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
@end

#ifdef __APPLE__
@implementation SimpleTestObserver
- (instancetype)init {
  self = [super init];
  if (self) {
    _failureCount = 0;
    _testCount = 0;
    _unexpectedFailureCount = 0;
  }
  return self;
}

- (void)testCaseWillStart:(XCTestCase *)testCase {
  self.testCount++;
}

- (void)testCase:(XCTestCase *)testCase
    didFailWithDescription:(NSString *)description
                    inFile:(nullable NSString *)filePath
                    atLine:(NSUInteger)lineNumber {
  self.failureCount++;
  NSLog(@"FAIL: %@ at %@:%lu: %@", testCase.name, filePath, (unsigned long)lineNumber, description);
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
      @"MSTViewerHandlerTests",
      @"PDSAccountServiceTests",
      @"MSTInteropTests",
      @"CARInteropTests",
      @"RepoCommitTests",
      @"PDSNetworkTransportTests",
      @"PLCOperationTests",
      @"PLCStoreTests",
      @"PLCAuditorTests",
      @"PLCServerTests",
      @"OAuthPKCETests",
      @"OAuthConformanceTests",
      @"OAuthPublicClientTests",
      @"ATProtoOAuthClientMetadataTests",
      @"OAuthDPoPTests",
      @"JWTTests",
      @"OAuth2Tests",
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
      @"ExploreCacheTests",
      @"ExploreHandlerTests",
      @"AppDelegateTests",
      @"HttpServerTests",
      @"PDSHttpServerBuilderTests",
      @"PDSHttpAdminRoutePackTests",
      @"WebSocketServerTests",
      @"MSTPersistenceTests",
      @"MSTRebalancingTests",
      @"HttpResponseTests",
      @"PDSConfigurationTests",
      @"PDSPhoneVerificationProviderTests",
      @"EventFormatterTests",
      @"PDSBlobServiceTests",
      @"PDSRecordServiceTests",
      @"PDSRecordTombstoneTests",
      @"PDSRepositoryServiceTests",
      @"ActorServiceTests",
      @"FeedServiceTests",
      @"FeedSkeletonTests",
      @"NotificationServiceTests",
      @"PDSCLIAccountCommandTests",
      @"PDSCLIRepoCommandTests",
      @"PDSCLIInviteCommandTests",
      @"PDSCLIRelayCommandTests",
      @"PDSHealthCheckTests",
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
      @"OAuthDemoHandlerConfigurationTests",
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
      @"XrpcChatBskyConvoTests"
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

    XCTestSuite *mainSuite = [XCTestSuite testSuiteWithName:@"All Tests"];

    for (NSString *className in testClasses) {
      // Apply filter if present
      if (testFilter) {
        NSArray *filters = [testFilter componentsSeparatedByString:@","];
        if (![filters containsObject:className]) {
          continue;
        }
      }

      Class testClass = NSClassFromString(className);
      if (testClass) {
        NSArray *methodNames = discoverTestMethodsForClass(testClass);
        if (methodNames.count > 0) {
          XCTestSuite *classSuite = [XCTestSuite testSuiteWithName:className];
          for (NSString *methodName in methodNames) {
            SEL selector = NSSelectorFromString(methodName);
            XCTestCase *testCase =
                [[testClass alloc] initWithSelector:selector];
            [classSuite addTest:testCase];
          }
          [mainSuite addTest:classSuite];
        }
      } else {
        // Only warn if we are not filtering, or if this is the specific class
        // we asked for
        if (!testFilter || [className isEqualToString:testFilter]) {
          NSLog(@"Warning: Test class %@ not found", className);
        }
      }
    }

    NSLog(@"\n=== Starting Test Suite: %@ ===", mainSuite.name);
    NSLog(@"Test suites: %lu", (unsigned long)mainSuite.tests.count);

    [mainSuite performTest:nil];

    NSLog(@"\n=== Test Suite Finished ===");
    NSLog(@"Tests run: %d", observer.testCount);
    NSLog(@"Failures: %d\n", observer.failureCount);

    return observer.failureCount > 0 ? 1 : 0;
  }
}
