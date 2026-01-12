#import "XCTest.h"
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
}

- (instancetype)initWithSelector:(SEL)selector {
    self = [super init];
    if (self) {
        _selector = selector;
        _name = NSStringFromSelector(selector);
    }
    return self;
}

- (void)setUp {}
- (void)tearDown {}

- (void)performTest:(id)run {
    [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCaseWillStart:self];
    
    @try {
        [self setUp];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:_selector];
#pragma clang diagnostic pop
    }
    @catch (NSException *exception) {
        [self recordFailureWithDescription:[NSString stringWithFormat:@"Uncaught exception: %@", exception]
                                    inFile:@"<unknown>"
                                    atLine:0
                                  expected:NO];
    }
    @finally {
        [self tearDown];
        [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCaseDidFinish:self];
    }
}

- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber expected:(BOOL)expected {
    [[XCTestObservationCenter sharedTestObservationCenter] notifyTestCase:self
                                                   didFailWithDescription:description
                                                                   inFile:filePath
                                                                   atLine:lineNumber];
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
