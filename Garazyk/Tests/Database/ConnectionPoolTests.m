// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// ConnectionPoolTests.m
// Basic tests for ATProtoConnectionPool without XCTest framework

#import <Foundation/Foundation.h>
#import "Database/Pool/ATProtoConnectionPool.h"
#include <sqlite3.h>

@interface ConnectionPoolTest : NSObject
- (BOOL)runAllTests;
- (BOOL)testPoolCreation;
- (BOOL)testAcquireRelease;
- (BOOL)testMaxConnections;
- (BOOL)testConcurrentFileWritersWaitForTransaction;
- (void)logPass:(NSString *)testName;
- (void)logFail:(NSString *)testName message:(NSString *)message;
@end

@implementation ConnectionPoolTest {
    NSInteger passCount;
    NSInteger failCount;
}

- (instancetype)init {
    if ((self = [super init])) {
        passCount = 0;
        failCount = 0;
    }
    return self;
}

- (BOOL)runAllTests {
    NSLog(@"=== Connection Pool Tests ===\n");

    @autoreleasepool {
        if (![self testPoolCreation]) return NO;
    }

    @autoreleasepool {
        if (![self testAcquireRelease]) return NO;
    }

    @autoreleasepool {
        if (![self testMaxConnections]) return NO;
    }

    @autoreleasepool {
        if (![self testConcurrentFileWritersWaitForTransaction]) return NO;
    }

    NSLog(@"\n=== Test Results ===");
    NSLog(@"Passed: %ld", (long)passCount);
    NSLog(@"Failed: %ld", (long)failCount);
    NSLog(@"%@", failCount == 0 ? @"✓ ALL TESTS PASSED" : @"✗ SOME TESTS FAILED");

    return failCount == 0;
}

- (BOOL)testPoolCreation {
    NSString *testName = @"testPoolCreation";
    NSLog(@"\nRunning %@...", testName);

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_pool_1.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    ATProtoConnectionPool *pool = [[ATProtoConnectionPool alloc] initWithPath:tempPath
                                                       minConnections:2
                                                       maxConnections:5];

    if (!pool) {
        [self logFail:testName message:@"Failed to create pool"];
        return NO;
    }

    // Verify initial state
    if (pool.minConnections != 2) {
        [self logFail:testName message:@"Min connections should be 2"];
        return NO;
    }

    if (pool.maxConnections != 5) {
        [self logFail:testName message:@"Max connections should be 5"];
        return NO;
    }

    // Min connections created on init
    if ([pool totalConnections] < 2) {
        [self logFail:testName message:@"Should have created min connections"];
        return NO;
    }

    [pool closeAllConnections];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (BOOL)testAcquireRelease {
    NSString *testName = @"testAcquireRelease";
    NSLog(@"\nRunning %@...", testName);

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_pool_2.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    ATProtoConnectionPool *pool = [[ATProtoConnectionPool alloc] initWithPath:tempPath
                                                       minConnections:1
                                                       maxConnections:3];

    if (!pool) {
        [self logFail:testName message:@"Failed to create pool"];
        return NO;
    }

    // Acquire a connection
    sqlite3 *conn1 = [pool acquireConnectionWithTimeout:1.0];
    if (!conn1) {
        [self logFail:testName message:@"Failed to acquire connection"];
        [pool closeAllConnections];
        return NO;
    }

    NSUInteger activeAfterAcquire = [pool activeConnections];
    if (activeAfterAcquire != 1) {
        [self logFail:testName message:[NSString stringWithFormat:@"Should have 1 active, got %lu", (unsigned long)activeAfterAcquire]];
        [pool closeAllConnections];
        return NO;
    }

    // Release the connection
    [pool releaseConnection:conn1];

    NSUInteger activeAfterRelease = [pool activeConnections];
    if (activeAfterRelease != 0) {
        [self logFail:testName message:@"Should have 0 active after release"];
        [pool closeAllConnections];
        return NO;
    }

    [pool closeAllConnections];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (BOOL)testMaxConnections {
    NSString *testName = @"testMaxConnections";
    NSLog(@"\nRunning %@...", testName);

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_pool_3.db"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    ATProtoConnectionPool *pool = [[ATProtoConnectionPool alloc] initWithPath:tempPath
                                                       minConnections:1
                                                       maxConnections:2];

    if (!pool) {
        [self logFail:testName message:@"Failed to create pool"];
        return NO;
    }

    // Acquire max connections
    sqlite3 *conn1 = [pool acquireConnectionWithTimeout:1.0];
    sqlite3 *conn2 = [pool acquireConnectionWithTimeout:1.0];

    if (!conn1 || !conn2) {
        [self logFail:testName message:@"Failed to acquire 2 connections"];
        [pool closeAllConnections];
        return NO;
    }

    // Try to acquire third - should timeout
    NSDate *start = [NSDate date];
    sqlite3 *conn3 = [pool acquireConnectionWithTimeout:0.5];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];

    if (conn3 != NULL) {
        [self logFail:testName message:@"Should not acquire connection when pool exhausted"];
        [pool closeAllConnections];
        return NO;
    }

    if (elapsed < 0.4) {
        [self logFail:testName message:@"Should have waited for timeout"];
        [pool closeAllConnections];
        return NO;
    }

    // Release one, should be able to acquire again
    [pool releaseConnection:conn1];
    sqlite3 *conn4 = [pool acquireConnectionWithTimeout:1.0];

    if (!conn4) {
        [self logFail:testName message:@"Should acquire after release"];
        [pool closeAllConnections];
        return NO;
    }

    [pool releaseConnection:conn2];
    [pool releaseConnection:conn4];
    [pool closeAllConnections];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    [self logPass:testName];
    return YES;
}

- (BOOL)testConcurrentFileWritersWaitForTransaction {
    NSString *testName = @"testConcurrentFileWritersWaitForTransaction";
    NSLog(@"\nRunning %@...", testName);

    NSString *filename = [NSString stringWithFormat:@"test_pool_%@.db", NSUUID.UUID.UUIDString];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    ATProtoConnectionPool *pool = [[ATProtoConnectionPool alloc] initWithPath:tempPath
                                                               minConnections:2
                                                               maxConnections:2];
    sqlite3 *conn1 = [pool acquireConnectionWithTimeout:1.0];
    sqlite3 *conn2 = [pool acquireConnectionWithTimeout:1.0];
    if (!conn1 || !conn2) {
        [self logFail:testName message:@"Failed to acquire two connections"];
        if (conn1) [pool releaseConnection:conn1];
        if (conn2) [pool releaseConnection:conn2];
        [pool closeAllConnections];
        return NO;
    }

    int createResult = sqlite3_exec(conn1,
                                    "CREATE TABLE concurrent_writes (value INTEGER)",
                                    NULL, NULL, NULL);
    int beginResult = sqlite3_exec(conn1, "BEGIN IMMEDIATE", NULL, NULL, NULL);
    int firstInsertResult = sqlite3_exec(conn1,
                                         "INSERT INTO concurrent_writes VALUES (1)",
                                         NULL, NULL, NULL);

    __block int secondInsertResult = SQLITE_ERROR;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        secondInsertResult = sqlite3_exec(conn2,
                                          "INSERT INTO concurrent_writes VALUES (2)",
                                          NULL, NULL, NULL);
        dispatch_semaphore_signal(finished);
    });

    [NSThread sleepForTimeInterval:0.1];
    int commitResult = sqlite3_exec(conn1, "COMMIT", NULL, NULL, NULL);
    long waitResult = dispatch_semaphore_wait(
        finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        // busy_timeout bounds this wait; keep conn2 alive until its write exits.
        dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    }

    [pool releaseConnection:conn1];
    [pool releaseConnection:conn2];
    [pool closeAllConnections];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[tempPath stringByAppendingString:@"-wal"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[tempPath stringByAppendingString:@"-shm"] error:nil];

    if (createResult != SQLITE_OK || beginResult != SQLITE_OK ||
        firstInsertResult != SQLITE_OK || commitResult != SQLITE_OK) {
        [self logFail:testName message:@"Failed to prepare the first write transaction"];
        return NO;
    }
    if (waitResult != 0) {
        [self logFail:testName message:@"Second writer did not finish after the first committed"];
        return NO;
    }
    if (secondInsertResult != SQLITE_OK) {
        [self logFail:testName
               message:[NSString stringWithFormat:@"Second writer returned SQLite code %d",
                                                   secondInsertResult]];
        return NO;
    }

    [self logPass:testName];
    return YES;
}

- (void)logPass:(NSString *)testName {
    passCount++;
    NSLog(@"  ✓ %@ passed", testName);
}

- (void)logFail:(NSString *)testName message:(NSString *)message {
    failCount++;
    NSLog(@"  ✗ %@ failed: %@", testName, message);
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ConnectionPoolTest *test = [[ConnectionPoolTest alloc] init];
        BOOL success = [test runAllTests];
        return success ? 0 : 1;
    }
}
