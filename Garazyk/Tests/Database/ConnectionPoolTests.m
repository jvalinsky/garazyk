// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// ConnectionPoolTests.m
// Basic tests for PDSConnectionPool without XCTest framework

#import <Foundation/Foundation.h>
#import "Database/Pool/PDSConnectionPool.h"
#include <sqlite3.h>

@interface ConnectionPoolTest : NSObject
- (BOOL)runAllTests;
- (BOOL)testPoolCreation;
- (BOOL)testAcquireRelease;
- (BOOL)testMaxConnections;
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

    PDSConnectionPool *pool = [[PDSConnectionPool alloc] initWithPath:tempPath
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

    PDSConnectionPool *pool = [[PDSConnectionPool alloc] initWithPath:tempPath
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

    PDSConnectionPool *pool = [[PDSConnectionPool alloc] initWithPath:tempPath
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
