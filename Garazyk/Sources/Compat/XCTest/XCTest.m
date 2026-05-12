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
@property (nonatomic, readwrite) SEL selector;
@property (nonatomic, readwrite, copy) NSString *name;
@end

@implementation XCTestCase

- (nullable instancetype)initWithSelector:(SEL)selector {
    self = [super init];
    if (self) {
        _selector = selector;
        // Build name as "-[ClassName methodName]"
        NSString *className = NSStringFromClass([self class]);
        NSString *methodName = NSStringFromSelector(selector);
        self.name = [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
    }
    return self;
}

- (void)setUp {
    // Default no-op; subclasses override
}

- (void)tearDown {
    // Default no-op; subclasses override
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
        NSString *description = exception.reason ?: @"unknown assertion failure";
        NSString *filePath = exception.userInfo[@"XCTestFile"] ?: @"(unknown)";
        NSUInteger line = [exception.userInfo[@"XCTestLine"] unsignedIntegerValue];
        PDSNotifyObserversTestCaseDidFail(self, description, filePath, line);
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

// ── XCTWaiter ─────────────────────────────────────────────────────────

@implementation XCTWaiter

+ (NSTimeInterval)waitForExpectationsWithTimeout:(NSTimeInterval)timeout
                                          handler:(void (^ _Nullable)(NSError * _Nullable))handler {
    // Minimal implementation: just sleep for the timeout.
    // Real expectation fulfillment is not implemented.
    [NSThread sleepForTimeInterval:timeout];
    if (handler) {
        handler(nil);
    }
    return timeout;
}

@end

#endif /* !__APPLE__ */
