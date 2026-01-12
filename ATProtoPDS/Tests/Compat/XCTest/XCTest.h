#ifndef XCTest_Compat_h
#define XCTest_Compat_h

#import <Foundation/Foundation.h>

// #warning "DEBUG: XCTest Shim Loaded"

NS_ASSUME_NONNULL_BEGIN

@class XCTestCase;
@class XCTestSuite;
@class XCTestRun;

// --- Classes ---

@interface XCTestExpectation : NSObject
@property (copy) NSString *description;
@property (nonatomic, assign) BOOL fulfilled;
- (void)fulfill;
@end

// --- Macros ---

#define XCTFail(...) \
    [self recordFailureWithDescription:[NSString stringWithFormat:@"" __VA_ARGS__] \
                                inFile:@(__FILE__) \
                                atLine:__LINE__ \
                              expected:NO]

#define XCTAssert(expression, ...) \
    if (!(expression)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertTrue(expression, ...) XCTAssert(expression, __VA_ARGS__)

#define XCTAssertFalse(expression, ...) \
    if ((expression)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertNil(expression, ...) \
    if ((expression) != nil) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertNotNil(expression, ...) \
    if ((expression) == nil) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertEqual(expression1, expression2, ...) \
    if ((expression1) != (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertEqualObjects(expression1, expression2, ...) \
    if (![expression1 isEqual:expression2] && ((id)expression1 != (id)expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertNotEqual(expression1, expression2, ...) \
    if ((expression1) == (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertNotEqualObjects(expression1, expression2, ...) \
    if ([expression1 isEqual:expression2] || (expression1 == expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertGreaterThan(expression1, expression2, ...) \
    if ((expression1) <= (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertLessThan(expression1, expression2, ...) \
    if ((expression1) >= (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertGreaterThanOrEqual(expression1, expression2, ...) \
    if ((expression1) < (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertLessThanOrEqual(expression1, expression2, ...) \
    if ((expression1) > (expression2)) { \
        XCTFail(__VA_ARGS__); \
    }

#define XCTAssertNoThrow(expression, ...) \
    @try { \
        (expression); \
    } \
    @catch (NSException *exception) { \
        XCTFail(__VA_ARGS__); \
    }

// --- Protocol ---

@protocol XCTestObservation <NSObject>
@optional
- (void)testCaseWillStart:(XCTestCase *)testCase;
- (void)testCaseDidFinish:(XCTestCase *)testCase;
- (void)testCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(nullable NSString *)filePath atLine:(NSUInteger)lineNumber;
@end

// --- Classes ---

@interface XCTestObservationCenter : NSObject
+ (instancetype)sharedTestObservationCenter;
- (void)addTestObserver:(id<XCTestObservation>)observer;
- (void)removeTestObserver:(id<XCTestObservation>)observer;
// Internal
- (void)notifyTestCaseWillStart:(XCTestCase *)testCase;
- (void)notifyTestCaseDidFinish:(XCTestCase *)testCase;
- (void)notifyTestCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber;
@end

@interface XCTestCase : NSObject
@property (readonly, copy) NSString *name;
- (instancetype)initWithSelector:(SEL)selector;
- (void)setUp;
- (void)tearDown;
- (void)performTest:(nullable id)run;
// Assertion support
- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber expected:(BOOL)expected;
// Async testing
- (XCTestExpectation *)expectationWithDescription:(NSString *)description;
- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(void (^ _Nullable)(NSError * _Nullable error))handler;
@end

@interface XCTestSuite : NSObject
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSArray<XCTestCase *> *tests;

+ (instancetype)testSuiteWithName:(NSString *)name;
- (void)addTest:(id)test; // Accepts XCTestCase or XCTestSuite
- (void)performTest:(nullable id)run;
@end

NS_ASSUME_NONNULL_END

#endif /* XCTest_Compat_h */
