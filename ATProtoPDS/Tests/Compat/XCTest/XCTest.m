#import "XCTest.h"
#import <objc/runtime.h>
#import <objc/runtime.h>

@implementation XCTestObservationCenter {
    NSMutableArray<id<XCTestObservation>> *_observers;
}

+ (instancetype)sharedTestObservationCenter {
    static XCTestObservationCenter *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[XCTestObservationCenter alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _observers = [NSMutableArray array];
    }
    return self;
}

- (void)addTestObserver:(id<XCTestObservation>)observer {
    [_observers addObject:observer];
}

- (void)removeTestObserver:(id<XCTestObservation>)observer {
    [_observers removeObject:observer];
}

- (void)notifyTestCaseWillStart:(XCTestCase *)testCase {
    for (id<XCTestObservation> observer in _observers) {
        if ([observer respondsToSelector:@selector(testCaseWillStart:)]) {
            [observer testCaseWillStart:testCase];
        }
    }
}

- (void)notifyTestCaseDidFinish:(XCTestCase *)testCase {
    for (id<XCTestObservation> observer in _observers) {
        if ([observer respondsToSelector:@selector(testCaseDidFinish:)]) {
            [observer testCaseDidFinish:testCase];
        }
    }
}

- (void)notifyTestCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber {
    for (id<XCTestObservation> observer in _observers) {
        if ([observer respondsToSelector:@selector(testCase:didFailWithDescription:inFile:atLine:)]) {
            [observer testCase:testCase didFailWithDescription:description inFile:filePath atLine:lineNumber];
        }
    }
}

@end

@implementation XCTestCase {
    SEL _selector;
    NSUInteger _failureCount;
}

- (instancetype)initWithSelector:(SEL)selector {
    self = [super init];
    if (self) {
        _selector = selector;
        _name = NSStringFromSelector(selector);
        _failureCount = 0;
    }
    return self;
}

- (void)setUp {}
- (void)tearDown {}

- (void)performTest:(id)run {
    [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCaseWillStart:self];
    fprintf(stderr, "[XCTest] Test %s started\n", [self.name UTF8String]);
    @try {
        [self setUp];
        if ([self respondsToSelector:_selector]) {
            // Use IMP to avoid ARC warnings with performSelector
            IMP imp = [self methodForSelector:_selector];
            void (*func)(id, SEL) = (void *)imp;
            func(self, _selector);
        }
        [self tearDown];
    } @catch (NSException *exception) {
        NSString *description = [NSString stringWithFormat:@"Uncaught exception %@", [exception reason]];
        [self recordFailureWithDescription:description inFile:@"<unknown>" atLine:0 expected:NO];
    }
    [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCaseDidFinish:self];
}

- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber expected:(BOOL)expected {
    printf("Test %s failed: %s (%s:%lu)\n", [self.name UTF8String], [description UTF8String], [filePath UTF8String], (unsigned long)lineNumber);
    _failureCount++;
    [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCase:self didFailWithDescription:description inFile:filePath atLine:lineNumber];
}

static char const * const kXCTestExpectationsKey = "kXCTestExpectationsKey";

// Async Helper
- (XCTestExpectation *)expectationWithDescription:(NSString *)description {
    XCTestExpectation *exp = [[XCTestExpectation alloc] init];
    exp.description = description;
    
    // Store expectation
    NSMutableArray *exps = objc_getAssociatedObject(self, kXCTestExpectationsKey);
    if (!exps) {
        exps = [NSMutableArray array];
        objc_setAssociatedObject(self, kXCTestExpectationsKey, exps, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [exps addObject:exp];
    
    return exp;
}

- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(void (^)(NSError *))handler {
    NSMutableArray<XCTestExpectation *> *exps = objc_getAssociatedObject(self, kXCTestExpectationsKey);
    
    NSDate *startDate = [NSDate date];
    BOOL allFulfilled = NO;
    
    while ([[NSDate date] timeIntervalSinceDate:startDate] < timeout) {
        if (exps.count == 0) {
            allFulfilled = YES;
            break;
        }

        allFulfilled = YES;
        for (XCTestExpectation *exp in exps) {
            if (!exp.fulfilled) {
                allFulfilled = NO;
                break;
            }
        }
        
        if (allFulfilled) break;
        
        // Spin runloop briefly
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    
    if (!allFulfilled && exps.count > 0) {
        [self recordFailureWithDescription:@"Wait for expectations timed out" inFile:@"<unknown>" atLine:0 expected:YES];
    }
    
    // Clean up associated object to avoid leaked state between tests
    objc_setAssociatedObject(self, kXCTestExpectationsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation XCTestExpectation
- (void)fulfill {
    self.fulfilled = YES;
}
@end

@implementation XCTestSuite {
    NSMutableArray *_tests;
}

+ (instancetype)testSuiteWithName:(NSString *)name {
    XCTestSuite *suite = [[XCTestSuite alloc] init];
    suite->_name = [name copy];
    suite->_tests = [NSMutableArray array];
    return suite;
}

- (void)addTest:(XCTestCase *)test {
    [_tests addObject:test];
}

- (NSArray<XCTestCase *> *)tests {
    return [_tests copy];
}

- (void)performTest:(id)run {
    for (id test in _tests) {
        [test performTest:run];
    }
}

@end
