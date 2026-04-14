/**
 * @file LinuxXCTestCompat.h
 *
 * @brief XCTest compatibility layer for Linux/GNUstep.
 *
 * Provides XCTest-compatible testing framework for Linux by implementing
 * XCTest classes and assertion macros. On macOS, imports native XCTest.
 *
 * Implementation details:
 * - Assertions call abort() on failure for test runner detection
 * - Basic setUp/tearDown lifecycle support
 * - Minimal test suite management
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef LinuxXCTestCompat_h
#define LinuxXCTestCompat_h

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class XCTestCase

 @abstract Base class for test cases (Linux implementation).

 @discussion Provides setUp/tearDown lifecycle hooks for test methods.
 */
@interface XCTestCase : NSObject

/*! Called before each test method. */
- (void)setUp;

/*! Called after each test method. */
- (void)tearDown;

@end

/*!
 @class XCTestSuite

 @abstract Test suite container (Linux implementation).

 @discussion Groups multiple test cases for execution.
 */
@interface XCTestSuite : XCTestCase

/*! Get default test suite. */
+ (id)defaultTestSuite;

/*! Add test case to suite. */
- (void)addTest:(XCTestCase *)test;

@end

/*! Assert condition is true. */
#define XCTAssertTrue(condition) do { if (!(condition)) { NSLog(@"XCTAssertTrue failed: %s", #condition); abort(); } } while(0)

/*! Assert condition is false. */
#define XCTAssertFalse(condition) do { if (condition) { NSLog(@"XCTAssertFalse failed: %s", #condition); abort(); } } while(0)

/*! Assert values are equal. */
#define XCTAssertEqual(a, b) do { if ((a) != (b)) { NSLog(@"XCTAssertEqual failed: %@ != %@", @(a), @(b)); abort(); } } while(0)

/*! Assert objects are equal via isEqual:. */
#define XCTAssertEqualObjects(a, b) do { if (![(a) isEqual:(b)]) { NSLog(@"XCTAssertEqualObjects failed: %@ != %@", a, b); abort(); } } while(0)

/*! Assert object is not nil. */
#define XCTAssertNotNil(obj) do { if ((obj) == nil) { NSLog(@"XCTAssertNotNil failed: %s is nil", #obj); abort(); } } while(0)

/*! Assert object is nil. */
#define XCTAssertNil(obj) do { if ((obj) != nil) { NSLog(@"XCTAssertNil failed: %s is not nil", #obj); abort(); } } while(0)

/*! Assert values are not equal. */
#define XCTAssertNotEqual(a, b) do { if ((a) == (b)) { NSLog(@"XCTAssertNotEqual failed: %@ == %@", @(a), @(b)); abort(); } } while(0)

/*! Assert first value is greater than second. */
#define XCTAssertGreaterThan(a, b) do { if ((a) <= (b)) { NSLog(@"XCTAssertGreaterThan failed: %@ <= %@", @(a), @(b)); abort(); } } while(0)

/*! Assert first value is less than second. */
#define XCTAssertLessThan(a, b) do { if ((a) >= (b)) { NSLog(@"XCTAssertLessThan failed: %@ >= %@", @(a), @(b)); abort(); } } while(0)

/*! Assert expression does not throw exception. */
#define XCTAssertNoThrow(expr) do { @try { expr; } @catch (id e) { NSLog(@"XCTAssertNoThrow failed: threw %@", e); abort(); } } while(0)

/*! Assert expression throws exception. */
#define XCTAssertThrows(expr) do { @try { expr; NSLog(@"XCTAssertThrows failed: did not throw"); abort(); } @catch (id e) { } } while(0)

/*! Unconditional test failure with message. */
#define XCTFail(...) do { NSLog(@"XCTFail: " __VA_ARGS__); abort(); } while(0)

/*! Assert floating point values are equal within accuracy. */
#define XCTAssertEqualWithAccuracy(a, b, accuracy) do { if (fabs((a) - (b)) > (accuracy)) { NSLog(@"XCTAssertEqualWithAccuracy failed"); abort(); } } while(0)

/*!
 @class XCTWaiter

 @abstract Asynchronous test waiter (minimal implementation).

 @discussion Provides basic async test support for Linux.
 */
@interface XCTWaiter : NSObject

/*! Wait for expectations with timeout. */
+ (NSTimeInterval)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(void (^ _Nullable)(NSError * _Nullable))handler;

@end

NS_ASSUME_NONNULL_END

#endif

#endif /* LinuxXCTestCompat_h */
