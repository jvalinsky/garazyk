// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file XCTest.h
 *
 * @brief XCTest compatibility layer for Linux/GNUstep.
 *
 * On macOS, this header is a passthrough to the native XCTest framework.
 * On Linux/GNUstep, it provides a complete XCTest-compatible testing
 * framework with assertion macros, test case lifecycle, suite management,
 * and observation support.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef PDS_XCTest_h
#define PDS_XCTest_h

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ── Forward declarations ──────────────────────────────────────────────

@class XCTestCase;
@class XCTestSuite;

// ── XCTest (abstract base) ────────────────────────────────────────────

/*!
 @class XCTest

 @abstract Abstract base class for all test objects.

 @discussion On macOS, XCTest is the native framework root class.
 On Linux, this provides the minimal interface needed by the test runner.
 */
@interface XCTest : NSObject

/*! Name of the test (class name or suite name). */
@property (nonatomic, readonly, copy) NSString *name;

/*! Number of tests contained (1 for test cases, count for suites). */
@property (nonatomic, readonly) NSUInteger testCaseCount;

/*! Run the test. Subclasses must override. */
- (void)performTest:(nullable id)handler;

@end

// ── XCTestCase ────────────────────────────────────────────────────────

/*!
 @class XCTestCase

 @abstract Base class for individual test cases on Linux.

 @discussion Provides setUp/tearDown lifecycle, test method invocation,
 and integration with the test runner's observation system.
 */
@interface XCTestCase : XCTest

/*! Selector for the test method to invoke. */
@property (nonatomic, readonly) SEL selector;

/*! Initialize with a specific test method selector. */
- (nullable instancetype)initWithSelector:(SEL)selector;

/*! Called before each test method. Override in subclasses. */
- (void)setUp;

/*! Called after each test method. Override in subclasses. */
- (void)tearDown;

/*! Invoke the test method with setUp/tearDown wrapping. */
- (void)invokeTest;

@end

// ── XCTestSuite ───────────────────────────────────────────────────────

/*!
 @class XCTestSuite

 @abstract Container for grouping test cases and other suites.

 @discussion Supports hierarchical test organization. The test runner
 builds a tree of XCTestSuite objects containing XCTestCase instances.
 */
@interface XCTestSuite : XCTest

/*! Create a named test suite. */
+ (instancetype)testSuiteWithName:(NSString *)name;

/*! Get the default test suite (all registered test classes). */
+ (id)defaultTestSuite;

/*! Add a test (XCTestCase or XCTestSuite) to this suite. */
- (void)addTest:(XCTest *)test;

/*! Array of contained tests. */
@property (nonatomic, readonly, copy) NSArray<XCTest *> *tests;

@end

// ── XCTestObservation protocol ────────────────────────────────────────

/*!
 @protocol XCTestObservation

 @abstract Protocol for observing test execution progress.

 @discussion Mirrors the macOS XCTestObservation protocol so the
 test runner can track starts, failures, and completions.
 */
@protocol XCTestObservation <NSObject>

@optional
- (void)testCaseWillStart:(XCTestCase *)testCase;
- (void)testCase:(XCTestCase *)testCase
    didFailWithDescription:(NSString *)description
                    inFile:(nullable NSString *)filePath
                    atLine:(NSUInteger)lineNumber;
- (void)testCaseDidFinish:(XCTestCase *)testCase;
- (void)testSuiteWillStart:(XCTestSuite *)testSuite;
- (void)testSuiteDidFinish:(XCTestSuite *)testSuite;

@end

// ── XCTestObservationCenter ───────────────────────────────────────────

/*!
 @class XCTestObservationCenter

 @abstract Central dispatcher for test observation callbacks.

 @discussion Test observers register here to receive lifecycle callbacks
 during test execution.
 */
@interface XCTestObservationCenter : NSObject

/*! Shared singleton observation center. */
+ (instancetype)sharedTestObservationCenter;

/*! Register an observer. */
- (void)addTestObserver:(id<XCTestObservation>)observer;

/*! Remove an observer. */
- (void)removeTestObserver:(id<XCTestObservation>)observer;

/*! Current observers (for internal dispatch). */
@property (nonatomic, readonly, copy) NSArray<id<XCTestObservation>> *observers;

@end

// ── XCTWaiter ─────────────────────────────────────────────────────────

/*!
 @class XCTWaiter

 @abstract Asynchronous test waiter (minimal implementation).

 @discussion Provides basic async test support for Linux.
 */
@interface XCTWaiter : NSObject

/*! Wait for expectations with timeout. */
+ (NSTimeInterval)waitForExpectationsWithTimeout:(NSTimeInterval)timeout
                                          handler:(void (^ _Nullable)(NSError * _Nullable))handler;

@end

// ── Assertion macros ──────────────────────────────────────────────────
//
// On Linux, assertion failures throw NSInternalInconsistencyException
// instead of calling abort(). This allows the test runner to catch
// failures, record them, and continue to the next test.
//
// The exception's userInfo contains:
//   - "XCTestFailure" key: failure description string
//   - "XCTestFile" key: source file path (when available)
//   - "XCTestLine" key: source line number (when available)

/*! Internal: throw a test failure exception. */
#define _PDSXCTFail(description, ...) \
    do { \
        NSDictionary *_info = @{ \
            @"XCTestFailure": [NSString stringWithFormat:description, ##__VA_ARGS__] \
        }; \
        @throw [[NSException alloc] initWithName:@"XCTestAssertionFailure" \
                                           reason:[NSString stringWithFormat:description, ##__VA_ARGS__] \
                                         userInfo:_info]; \
    } while(0)

/*! Assert condition is true. */
#define XCTAssertTrue(condition) \
    do { if (!(condition)) { _PDSXCTFail(@"XCTAssertTrue failed: %s", #condition); } } while(0)

/*! Assert condition is false. */
#define XCTAssertFalse(condition) \
    do { if ((condition)) { _PDSXCTFail(@"XCTAssertFalse failed: %s", #condition); } } while(0)

/*! Assert values are equal (scalar). */
#define XCTAssertEqual(a, b) \
    do { if ((a) != (b)) { _PDSXCTFail(@"XCTAssertEqual failed: %@ != %@", @(a), @(b)); } } while(0)

/*! Assert objects are equal via isEqual:. */
#define XCTAssertEqualObjects(a, b) \
    do { if (![(a) isEqual:(b)]) { _PDSXCTFail(@"XCTAssertEqualObjects failed: %@ != %@", (a), (b)); } } while(0)

/*! Assert object is not nil. */
#define XCTAssertNotNil(obj) \
    do { if ((obj) == nil) { _PDSXCTFail(@"XCTAssertNotNil failed: %s is nil", #obj); } } while(0)

/*! Assert object is nil. */
#define XCTAssertNil(obj) \
    do { if ((obj) != nil) { _PDSXCTFail(@"XCTAssertNil failed: %s is not nil", #obj); } } while(0)

/*! Assert values are not equal (scalar). */
#define XCTAssertNotEqual(a, b) \
    do { if ((a) == (b)) { _PDSXCTFail(@"XCTAssertNotEqual failed: %@ == %@", @(a), @(b)); } } while(0)

/*! Assert first value is greater than second. */
#define XCTAssertGreaterThan(a, b) \
    do { if ((a) <= (b)) { _PDSXCTFail(@"XCTAssertGreaterThan failed: %@ <= %@", @(a), @(b)); } } while(0)

/*! Assert first value is less than second. */
#define XCTAssertLessThan(a, b) \
    do { if ((a) >= (b)) { _PDSXCTFail(@"XCTAssertLessThan failed: %@ >= %@", @(a), @(b)); } } while(0)

/*! Assert expression does not throw exception. */
#define XCTAssertNoThrow(expr) \
    do { @try { expr; } @catch (id e) { _PDSXCTFail(@"XCTAssertNoThrow failed: threw %@", e); } } while(0)

/*! Assert expression throws exception. */
#define XCTAssertThrows(expr) \
    do { @try { expr; _PDSXCTFail(@"XCTAssertThrows failed: did not throw"); } @catch (id e) { } } while(0)

/*! Unconditional test failure with message. */
#define XCTFail(...) _PDSXCTFail(__VA_ARGS__)

/*! Assert floating point values are equal within accuracy. */
#define XCTAssertEqualWithAccuracy(a, b, accuracy) \
    do { if (fabs((double)(a) - (double)(b)) > (accuracy)) { _PDSXCTFail(@"XCTAssertEqualWithAccuracy failed"); } } while(0)

/*! Assert condition is true (with custom message). */
#define XCTAssertTrueMsg(condition, ...) \
    do { if (!(condition)) { _PDSXCTFail(__VA_ARGS__); } } while(0)

NS_ASSUME_NONNULL_END

#endif /* !__APPLE__ */

#endif /* PDS_XCTest_h */
