#import <Foundation/Foundation.h>

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import <objc/runtime.h>
#import "Network/RateLimiter.h"
#import "Network/HttpResponse.h"

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
        [RateLimiter sharedLimiter].enabled = NO;

        NSArray *testClasses = @[
            @"MSTViewerHandlerTests",
            @"PDSAccountServiceTests",
            @"MSTInteropTests",
            @"CARInteropTests",
            @"RepoCommitTests",
            @"PDSNetworkTransportTests",
            @"OAuthPKCETests",
            @"OAuthDPoPTests",
            @"JWTTests",
            @"OAuth2Tests",
            @"SubscribeReposHandlerTests",
            @"GetServiceAuthMethodTests",
            @"XrpcHandlerTests",
            @"XrpcMethodRegistryTests",
            @"PDSCLITests",
            @"PDSCLIServiceStubTests",
            @"ActorStoreTests",
            @"DatabasePoolTests",
            @"PDSControllerTests",
            @"PDSIntegrationTests",
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
            @"CBORSecurityTests",
            @"JWTSecurityTests",
            @"HandleResolverSecurityTests",
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
            @"MSTViewerHandlerTests",
            @"PDSAccountServiceTests",
            @"HttpResponseTests",
            @"PDSConfigurationTests"
        ];

        SimpleTestObserver *observer = [[SimpleTestObserver alloc] init];

#ifdef __APPLE__
        XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
        [center addTestObserver:observer];
#endif

        XCTestSuite *mainSuite = [XCTestSuite testSuiteWithName:@"All Tests"];

        for (NSString *className in testClasses) {
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
                NSLog(@"Warning: Test class %@ not found", className);
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
