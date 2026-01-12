#ifndef LinuxXCTestCompat_h
#define LinuxXCTestCompat_h

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCTestCase : NSObject
- (void)setUp;
- (void)tearDown;
@end

@interface XCTestSuite : XCTestCase
+ (id)defaultTestSuite;
- (void)addTest:(XCTestCase *)test;
@end

#define XCTAssertTrue(condition) do { if (!(condition)) { NSLog(@"XCTAssertTrue failed: %s", #condition); abort(); } } while(0)
#define XCTAssertFalse(condition) do { if (condition) { NSLog(@"XCTAssertFalse failed: %s", #condition); abort(); } } while(0)
#define XCTAssertEqual(a, b) do { if ((a) != (b)) { NSLog(@"XCTAssertEqual failed: %@ != %@", @(a), @(b)); abort(); } } while(0)
#define XCTAssertEqualObjects(a, b) do { if (![(a) isEqual:(b)]) { NSLog(@"XCTAssertEqualObjects failed: %@ != %@", a, b); abort(); } } while(0)
#define XCTAssertNotNil(obj) do { if ((obj) == nil) { NSLog(@"XCTAssertNotNil failed: %s is nil", #obj); abort(); } } while(0)
#define XCTAssertNil(obj) do { if ((obj) != nil) { NSLog(@"XCTAssertNil failed: %s is not nil", #obj); abort(); } } while(0)
#define XCTAssertNotEqual(a, b) do { if ((a) == (b)) { NSLog(@"XCTAssertNotEqual failed: %@ == %@", @(a), @(b)); abort(); } } while(0)
#define XCTAssertGreaterThan(a, b) do { if ((a) <= (b)) { NSLog(@"XCTAssertGreaterThan failed: %@ <= %@", @(a), @(b)); abort(); } } while(0)
#define XCTAssertLessThan(a, b) do { if ((a) >= (b)) { NSLog(@"XCTAssertLessThan failed: %@ >= %@", @(a), @(b)); abort(); } } while(0)
#define XCTAssertNoThrow(expr) do { @try { expr; } @catch (id e) { NSLog(@"XCTAssertNoThrow failed: threw %@", e); abort(); } } while(0)
#define XCTAssertThrows(expr) do { @try { expr; NSLog(@"XCTAssertThrows failed: did not throw"); abort(); } @catch (id e) { } } while(0)
#define XCTFail(...) do { NSLog(@"XCTFail: " __VA_ARGS__); abort(); } while(0)
#define XCTAssertEqualWithAccuracy(a, b, accuracy) do { if (fabs((a) - (b)) > (accuracy)) { NSLog(@"XCTAssertEqualWithAccuracy failed"); abort(); } } while(0)

@interface XCTWaiter : NSObject
+ (NSTimeInterval)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(void (^ _Nullable)(NSError * _Nullable))handler;
@end

NS_ASSUME_NONNULL_END

#endif

#endif /* LinuxXCTestCompat_h */
