#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>

// Simple test observer for tracking pass/fail
@interface TutorialTestObserver : NSObject <XCTestObservation>
@property (nonatomic, assign) int failureCount;
@property (nonatomic, assign) int testCount;
@end

@implementation TutorialTestObserver
- (instancetype)init {
    self = [super init];
    if (self) {
        _failureCount = 0;
        _testCount = 0;
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
    @autoreleasepool {
        NSArray *testClasses = @[
            @"TutorialBase64URLTests",
            @"TutorialECDSAUtilsTests",
            @"TutorialJWTTests",
            @"TutorialSQLiteHelperTests",
            @"TutorialCIDGeneratorTests",
            @"AccountServiceTests",
            @"RecordServiceTests",
            @"TutorialBlobStoreTests",
            @"TutorialIdentityServiceTests",
            @"TutorialModerationServiceTests",
        ];

        TutorialTestObserver *observer = [[TutorialTestObserver alloc] init];
        XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
        [center addTestObserver:observer];

        // Parse command line arguments for filtering
        NSString *testFilter = nil;
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"-XCTest"] && i + 1 < argc) {
                testFilter = [NSString stringWithUTF8String:argv[i + 1]];
                break;
            }
        }

        XCTestSuite *mainSuite = [XCTestSuite testSuiteWithName:@"Tutorial Tests"];

        for (NSString *className in testClasses) {
            if (testFilter) {
                NSArray *filters = [testFilter componentsSeparatedByString:@","];
                if (![filters containsObject:className]) continue;
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
                NSLog(@"Warning: Test class %@ not found", className);
            }
        }

        NSLog(@"\n=== Starting Tutorial Tests ===");
        NSLog(@"Test suites: %lu", (unsigned long)mainSuite.tests.count);

        [mainSuite performTest:nil];

        NSLog(@"\n=== Tutorial Tests Finished ===");
        NSLog(@"Tests run: %d", observer.testCount);
        NSLog(@"Failures: %d\n", observer.failureCount);

        return observer.failureCount > 0 ? 1 : 0;
    }
}
