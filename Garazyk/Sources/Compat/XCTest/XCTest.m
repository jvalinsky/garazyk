// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file XCTest.m
 *
 * @brief Linux/GNUstep implementation of XCTest framework classes.
 *
 * Provides XCTestCase, XCTestSuite, XCTestObservationCenter, and XCTWaiter
 * implementations that mirror the macOS XCTest API surface enough for
 * the Garazyk test runner (test_main.m) to work on Linux.
 *
 * Key design decisions:
 * - Assertion failures throw NSException named "XCTestAssertionFailure"
 *   instead of calling abort(), so the runner can catch and record failures.
 * - XCTestCase.performTest: calls observation callbacks (willStart,
 *   didFail, didFinish) so the observer tracks results correctly.
 * - XCTestSuite.performTest: iterates children and swallows assertion
 *   failures so the suite continues after a failing test.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifdef __APPLE__
// On macOS, this file should not be compiled (native XCTest is used).
// If it accidentally gets compiled, it will be empty.
#else

#import "XCTest.h"
#import <objc/runtime.h>

// ── Internal helper: dispatch observation callbacks ───────────────────

static void PDSNotifyObserversTestCaseWillStart(XCTestCase *testCase) {
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
    for (id<XCTestObservation> observer in center.observers) {
        if ([observer respondsToSelector:@selector(testCaseWillStart:)]) {
            [observer testCaseWillStart:testCase];
        }
    }
}

static void PDSNotifyObserversTestCaseDidFail(XCTestCase *testCase,
                                              NSString *description,
                                              NSString *filePath,
                                              NSUInteger lineNumber) {
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
    for (id<XCTestObservation> observer in center.observers) {
        if ([observer respondsToSelector:@selector(testCase:didFailWithDescription:inFile:atLine:)]) {
            [observer testCase:testCase
                didFailWithDescription:description
                               inFile:filePath
                               atLine:lineNumber];
        }
    }
}

static void PDSNotifyObserversTestCaseDidFinish(XCTestCase *testCase) {
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
    for (id<XCTestObservation> observer in center.observers) {
        if ([observer respondsToSelector:@selector(testCaseDidFinish:)]) {
            [observer testCaseDidFinish:testCase];
        }
    }
}

static void PDSNotifyObserversTestSuiteWillStart(XCTestSuite *testSuite) {
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
    for (id<XCTestObservation> observer in center.observers) {
        if ([observer respondsToSelector:@selector(testSuiteWillStart:)]) {
            [observer testSuiteWillStart:testSuite];
        }
    }
}

static void PDSNotifyObserversTestSuiteDidFinish(XCTestSuite *testSuite) {
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];
    for (id<XCTestObservation> observer in center.observers) {
        if ([observer respondsToSelector:@selector(testSuiteDidFinish:)]) {
            [observer testSuiteDidFinish:testSuite];
        }
    }
}

// ── XCTest ────────────────────────────────────────────────────────────

@implementation XCTest

- (NSString *)name {
    return @"<unknown>";
}

- (NSUInteger)testCaseCount {
    return 1;
}

- (void)performTest:(id)handler {
    // Subclasses override
}

@end

// ── XCTestCase ────────────────────────────────────────────────────────

@interface XCTestCase ()
- (void)runTeardownBlocks;
@property (nonatomic, readwrite) SEL selector;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<XCTestExpectation *> *pendingExpectations;
@property (nonatomic, strong) NSMutableArray *teardownBlocks;
@end

@implementation XCTestCase

@synthesize selector = _selector;
@synthesize name = _name;
@synthesize pendingExpectations = _pendingExpectations;
@synthesize teardownBlocks = _teardownBlocks;

- (nullable instancetype)initWithSelector:(SEL)selector {
    self = [super init];
    if (self) {
        _selector = selector;
        // Build name as "-[ClassName methodName]"
        NSString *className = NSStringFromClass([self class]);
        NSString *methodName = NSStringFromSelector(selector);
        self.name = [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
        _pendingExpectations = [NSMutableArray array];
        _teardownBlocks = [NSMutableArray array];
    }
    return self;
}

- (void)setUp {
    // Default no-op; subclasses override
    [self.pendingExpectations removeAllObjects];
    [self.teardownBlocks removeAllObjects];
}

- (void)addTeardownBlock:(void (^)(void))block {
    if (block) {
        [self.teardownBlocks addObject:[block copy]];
    }
}

- (void)tearDown {
    // Default no-op; subclasses override
    [self runTeardownBlocks];
    [self.pendingExpectations removeAllObjects];
}

- (void)runTeardownBlocks {
    NSArray *blocks = [self.teardownBlocks copy];
    [self.teardownBlocks removeAllObjects];
    for (void (^block)(void) in [blocks reverseObjectEnumerator]) {
        block();
    }
}

- (XCTestExpectation *)expectationWithDescription:(NSString *)description {
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:description ?: @""];
    [self.pendingExpectations addObject:expectation];
    return expectation;
}

- (XCTestExpectation *)expectationForPredicate:(NSPredicate *)predicate
                         evaluatedWithObject:(id)object
                                       handler:(void (^)(XCTestExpectation *))handler {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Predicate expectation"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!expectation.isFulfilled && !expectation.isCancelled) {
            if ([predicate evaluateWithObject:object]) {
                [expectation fulfill];
                if (handler) {
                    handler(expectation);
                }
                return;
            }
            [NSThread sleepForTimeInterval:0.01];
        }
    });
    return expectation;
}

- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout
                               handler:(void (^ _Nullable)(NSError * _Nullable))handler {
    NSArray *expectations = [self.pendingExpectations copy];
    [XCTWaiter waitForExpectations:expectations timeout:timeout];
    if (handler) {
        handler(nil);
    }
    [self.pendingExpectations removeAllObjects];
}

- (void)waitForExpectations:(NSArray<XCTestExpectation *> *)expectations
                    timeout:(NSTimeInterval)timeout {
    [XCTWaiter waitForExpectations:expectations timeout:timeout];
}

- (void)invokeTest {
    @try {
        [self setUp];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:self.selector];
        #pragma clang diagnostic pop
    } @catch (NSException *exception) {
        // Re-throw so performTest: can catch and record it
        @throw exception;
    } @finally {
        // Run registered blocks independently of subclass tearDown super-calls,
        // matching native XCTest cleanup guarantees.
        [self runTeardownBlocks];
        [self tearDown];
    }
}

- (NSUInteger)testCaseCount {
    return 1;
}

- (void)performTest:(id)handler {
    PDSNotifyObserversTestCaseWillStart(self);
    @try {
        [self invokeTest];
    } @catch (NSException *exception) {
        if (![[exception name] isEqualToString:@"XCTestSkip"]) {
            NSString *description = exception.reason ?: @"unknown assertion failure";
            NSString *filePath = exception.userInfo[@"XCTestFile"] ?: @"(unknown)";
            NSUInteger line = [exception.userInfo[@"XCTestLine"] unsignedIntegerValue];
            PDSNotifyObserversTestCaseDidFail(self, description, filePath, line);
        }
    }
    PDSNotifyObserversTestCaseDidFinish(self);
}

@end

// ── XCTestSuite ───────────────────────────────────────────────────────

@interface XCTestSuite ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<XCTest *> *mutableTests;
@end

@implementation XCTestSuite

@synthesize name = _name;
@synthesize mutableTests = _mutableTests;

+ (instancetype)testSuiteWithName:(NSString *)name {
    XCTestSuite *suite = [[XCTestSuite alloc] init];
    suite.name = name;
    return suite;
}

+ (id)defaultTestSuite {
    XCTestSuite *suite = [XCTestSuite testSuiteWithName:@"Default"];
    // The test runner builds its own suite; this is a placeholder.
    return suite;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableTests = [NSMutableArray array];
    }
    return self;
}

- (void)addTest:(XCTest *)test {
    [self.mutableTests addObject:test];
}

- (NSArray<XCTest *> *)tests {
    return [self.mutableTests copy];
}

- (NSUInteger)testCaseCount {
    NSUInteger count = 0;
    for (XCTest *test in self.mutableTests) {
        count += [test testCaseCount];
    }
    return count;
}

- (void)performTest:(id)handler {
    PDSNotifyObserversTestSuiteWillStart(self);
    for (XCTest *test in self.mutableTests) {
        @try {
            [test performTest:handler];
        } @catch (NSException *exception) {
            if (![[exception name] isEqualToString:@"XCTestAssertionFailure"]) {
                // Unexpected exception — re-throw
                @throw exception;
            }
            // Assertion failure already recorded by the observer;
            // swallow it here so the suite continues.
        }
    }
    PDSNotifyObserversTestSuiteDidFinish(self);
}

@end

// ── XCTestObservationCenter ───────────────────────────────────────────

@interface XCTestObservationCenter ()
@property (nonatomic, strong) NSMutableArray<id<XCTestObservation>> *internalObservers;
@end

@implementation XCTestObservationCenter

+ (instancetype)sharedTestObservationCenter {
    static XCTestObservationCenter *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XCTestObservationCenter alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _internalObservers = [NSMutableArray array];
    }
    return self;
}

- (void)addTestObserver:(id<XCTestObservation>)observer {
    [self.internalObservers addObject:observer];
}

- (void)removeTestObserver:(id<XCTestObservation>)observer {
    [self.internalObservers removeObject:observer];
}

- (NSArray<id<XCTestObservation>> *)observers {
    return [self.internalObservers copy];
}

@end

// ── XCTestExpectation ─────────────────────────────────────────────────

@interface XCTestExpectation ()
@property (nonatomic, readwrite, copy) NSString *expectationDescription;
@property (atomic, assign, readwrite, getter=isFulfilled) BOOL fulfilled;
@property (atomic, assign) NSUInteger fulfillmentCount;
@end

@implementation XCTestExpectation

- (instancetype)initWithDescription:(NSString *)description {
    self = [super init];
    if (self) {
        _expectationDescription = [description copy] ?: @"";
        _expectedFulfillmentCount = 1;
        _fulfillmentCount = 0;
        _fulfilled = NO;
        _cancelled = NO;
        _inverted = NO;
    }
    return self;
}

- (void)fulfill {
    @synchronized (self) {
        if (self.fulfillmentCount < self.expectedFulfillmentCount) {
            self.fulfillmentCount += 1;
        }
        self.fulfilled = self.fulfillmentCount >= MAX(self.expectedFulfillmentCount, 1U);
    }
}

@end

// ── XCTWaiter ─────────────────────────────────────────────────────────

@implementation XCTWaiter

+ (BOOL)pds_allFulfilled:(NSArray<XCTestExpectation *> *)expectations {
    for (XCTestExpectation *expectation in expectations) {
        if (!expectation.isInverted && !expectation.isFulfilled) {
            return NO;
        }
    }
    return YES;
}

+ (void)waitForExpectations:(NSArray<XCTestExpectation *> *)expectations
                    timeout:(NSTimeInterval)timeout {
    if (expectations.count == 0) {
        return;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0)];
    while (YES) {
        NSMutableArray *outstanding = [NSMutableArray array];
        BOOL normalExpectationsReady = YES;
        BOOL invertedExpectationFailed = NO;
        for (XCTestExpectation *expectation in expectations) {
            if (expectation.isInverted) {
                if (expectation.isFulfilled) {
                    invertedExpectationFailed = YES;
                    [outstanding addObject:[NSString stringWithFormat:@"%@ (inverted expectation fulfilled)", expectation.expectationDescription ?: @"(unnamed)"]];
                }
            } else if (!expectation.isFulfilled) {
                normalExpectationsReady = NO;
                [outstanding addObject:expectation.expectationDescription ?: @"(unnamed)"];
            }
        }
        if (invertedExpectationFailed) {
            for (XCTestExpectation *expectation in expectations) {
                expectation.cancelled = YES;
            }
            _PDSXCTFail(@"Asynchronous wait failed: inverted expectation fulfilled: %@",
                        [outstanding componentsJoinedByString:@", "]);
            return;
        }
        if (normalExpectationsReady) {
            BOOL hasInvertedExpectation = NO;
            for (XCTestExpectation *expectation in expectations) {
                if (expectation.isInverted) {
                    hasInvertedExpectation = YES;
                    break;
                }
            }
            if (!hasInvertedExpectation) {
                for (XCTestExpectation *expectation in expectations) {
                    expectation.cancelled = YES;
                }
                return;
            }
            if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
                for (XCTestExpectation *expectation in expectations) {
                    expectation.cancelled = YES;
                }
                return;
            }
        }
        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            for (XCTestExpectation *expectation in expectations) {
                expectation.cancelled = YES;
            }
            _PDSXCTFail(@"Asynchronous wait failed: Exceeded timeout of %g seconds, with unmet expectations: %@",
                        timeout, [outstanding componentsJoinedByString:@", "]);
            return;
        }
        // Pump GCD / CFRunLoop sources so fulfill callbacks can land.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

+ (NSTimeInterval)waitForExpectationsWithTimeout:(NSTimeInterval)timeout
                                          handler:(void (^ _Nullable)(NSError * _Nullable))handler {
    // Legacy entry point used by a few call sites that do not pass an
    // expectation array. Sleeping the full timeout is wrong; with no
    // expectations there is nothing to wait for.
    NSDate *start = [NSDate date];
    if (handler) {
        handler(nil);
    }
    return [[NSDate date] timeIntervalSinceDate:start];
}

@end

#endif /* !__APPLE__ */
