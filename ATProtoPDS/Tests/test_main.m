#import <Foundation/Foundation.h>

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import <objc/runtime.h>
#import "Network/RateLimiter.h"
#import "Network/HttpResponse.h"
#import "App/PDSConfiguration.h"

@interface SimpleTestObserver : NSObject <XCTestObservation>
@property (nonatomic, assign) int failureCount;
@property (nonatomic, assign) int testCount;
@property (nonatomic, assign) int unexpectedFailureCount;
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

- (void)testCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(nullable NSString *)filePath atLine:(NSUInteger)lineNumber {
    self.failureCount++;
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

int main(int argc, char * argv[]) {
    fprintf(stderr, "test_main started\n");
    @autoreleasepool {
        // Disable rate limiting for tests
        RateLimiterSetDisabledGlobally(YES);
        [RateLimiter sharedLimiter].enabled = NO;

        if ([[[NSProcessInfo processInfo] environment][@"PDS_USE_NEW_REPOS"] isEqualToString:@"1"]) {
            [PDSConfiguration sharedConfiguration].useNewRepositoryImplementation = YES;
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
            @"OAuthDPoPTests",
            @"JWTTests",
            @"OAuth2Tests",
            @"SubscribeReposHandlerTests",
            @"GetServiceAuthMethodTests",
            @"XrpcHandlerTests",
            @"XrpcMethodRegistryTests",
            @"AdminAuthXrpcTests",
            @"RepoAuthXrpcTests",
            @"PDSCLITests",
            @"PDSCLIServiceStubTests",
            @"ActorStoreTests",
            @"DatabasePoolTests",
            @"PDSControllerTests",
            @"PDSIntegrationTests",
            @"PDSPLCIntegrationTests",
            @"AdminServiceTests",
            @"AdminMiddlewareTests",
            @"ServiceDatabasesTests",
            @"RateLimiterTests",
            @"DIDResolverTests",
            @"HandleResolverTests",
            @"ATProtoHandleValidatorTests",
            @"IdentifierTests",
            @"TOTPTests",
            @"CryptoTests",
            @"OAuth2HandlerTests",
            @"LexiconValidationTests",
            @"RecordPathValidationTests",
            @"XrpcInputValidationTests",
            @"XrpcErrorResponseTests",
            @"BlobXrpcTests",
            @"BlobPerformanceTests",
            @"CBORSecurityTests",
            @"JWTSecurityTests",
            @"HandleResolverSecurityTests",
            @"HandleResolverSSRFTests",
            @"WebSocketUpgradeHandlerTests",
            @"HttpRouterTests",
            @"HttpRouteTrieTests",
            @"HttpRequestParsingTests",
            @"HttpBufferPoolTests",
            @"HttpChunkedBodyParserTests",
            @"FirehoseTests",
            @"RelayClientTests",
            @"SessionStoreTests",
            @"ExploreCacheTests",
            @"ExploreHandlerTests",
            @"HttpServerTests",
            @"WebSocketServerTests",
            @"MSTPersistenceTests",
            @"HttpResponseTests",
            @"PDSConfigurationTests",
            @"EventFormatterTests",
            @"PDSBlobServiceTests",
            @"PDSRecordServiceTests",
            @"ActorServiceTests",
            @"FeedServiceTests",
            @"NotificationServiceTests",
            @"PDSCLIAccountCommandTests",
            @"PDSCLIInviteCommandTests",
            @"PDSHealthCheckTests",
            @"OAuthServerMetadataTests",
            @"OAuthSessionTests",
            @"NodeInfoTests",
            @"ATProtoCBORSerializationTests",
            @"ActorStoreCharacterizationTests",
            @"XrpcMethodRegistryCharacterizationTests",
            @"MSTCharacterizationTests",
            @"SessionCharacterizationTests",
            @"KeyManagerCharacterizationTests",
            @"ATProtoErrorTests",
            @"ProtocolCompileTests",
            @"PDSServiceContainerTests",
            @"PDSAccountManagerTests",
            @"Base58Tests",
            @"WebSocketFrameParsingTests",
            @"AdminModerationAuthTests",
            @"OAuthIntegrationTests"
        ];

        SimpleTestObserver *observer = [[SimpleTestObserver alloc] init];

#ifdef __APPLE__
        XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
        [center addTestObserver:observer];
#endif

        // Parse command line arguments for filtering
        NSString *testFilter = nil;
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"-XCTest"] && i + 1 < argc) {
                testFilter = [NSString stringWithUTF8String:argv[i+1]];
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
                        XCTestCase *testCase = [[testClass alloc] initWithSelector:selector];
                        [classSuite addTest:testCase];
                    }
                    [mainSuite addTest:classSuite];
                }
            } else {
                // Only warn if we are not filtering, or if this is the specific class we asked for
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
