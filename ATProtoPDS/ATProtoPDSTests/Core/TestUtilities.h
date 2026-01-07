#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "CID.h"
#import "TID.h"
#import "DID.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Assertion Macros

#define PDS_XCTAssertEqualObjects(a, b, ...) \
    XCTAssertEqualObjects(a, b, ##__VA_ARGS__)

#define PDS_XCTAssertNotNil(a, ...) \
    XCTAssertNotNil(a, ##__VA_ARGS__)

#define PDS_XCTAssertNil(a, ...) \
    XCTAssertNil(a, ##__VA_ARGS__)

#define PDS_XCTAssertTrue(a, ...) \
    XCTAssertTrue(a, ##__VA_ARGS__)

#define PDS_XCTAssertFalse(a, ...) \
    XCTAssertFalse(a, ##__VA_ARGS__)

#pragma mark - Test Fixtures

@interface TestFixture : NSObject

@property (nonatomic, strong, readonly) NSData *testData;
@property (nonatomic, copy, readonly) NSString *testDID;
@property (nonatomic, copy, readonly) NSString *testHandle;
@property (nonatomic, strong, readonly) CID *testCID;
@property (nonatomic, strong, readonly) TID *testTID;

+ (instancetype)sharedFixture;

- (NSData *)randomDataOfLength:(NSUInteger)length;
- (NSString *)randomStringOfLength:(NSUInteger)length;
- (CID *)generateRandomCID;
- (NSString *)generateRandomHandle;

@end

#pragma mark - Mock Server

@interface MockHTTPServer : NSObject

@property (nonatomic, assign, readonly) UInt16 port;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

+ (nullable instancetype)serverWithPort:(UInt16)port error:(NSError **)error;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (void)addRouteForMethod:(NSString *)method
                      path:(NSString *)path
                handler:(void (^)(NSDictionary *request, void (^response)(NSInteger status, NSDictionary *headers, NSData *body)))handler;

@end

#pragma mark - Test Database

@interface TestDatabase : NSObject

@property (nonatomic, strong, readonly) NSURL *databaseURL;
@property (nonatomic, strong, readonly) class PDSDatabase;

+ (nullable instancetype)inMemoryDatabaseWithError:(NSError **)error;
+ (nullable instancetype)temporaryDatabaseWithError:(NSError **)error;

- (BOOL)resetWithError:(NSError **)error;
- (void)close;

@end

#pragma mark - Concurrency Helpers

@interface ConcurrencyTestHelper : NSObject

+ (dispatch_queue_t)createTestQueue;
+ (void)waitForQueue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout;
+ (void)runSynchronousBlock:(void (^)(void))block timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
