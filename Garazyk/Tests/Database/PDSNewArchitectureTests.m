// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

@interface PDSNewArchitectureTests : XCTestCase

@end

@implementation PDSNewArchitectureTests

- (void)testActorStoreTests {
    [self invokeTestClassNamed:@"ActorStoreTests" selector:@selector(testStoreInitialization)];
}

- (void)testDatabasePoolTests {
    [self invokeTestClassNamed:@"DatabasePoolTests" selector:@selector(testPoolInitialization)];
}

- (void)testServiceDatabasesTests {
    [self invokeTestClassNamed:@"ServiceDatabasesTests" selector:@selector(testServiceDatabasesInitialization)];
}

- (void)testPDSControllerTests {
    [self invokeTestClassNamed:@"PDSControllerTests" selector:@selector(testControllerInitialization)];
}

- (void)invokeTestClassNamed:(NSString *)className selector:(SEL)selector {
    Class testClass = NSClassFromString(className);
    XCTAssertNotNil(testClass, @"Expected test class %@ to exist", className);
    if (testClass == Nil) {
        return;
    }

    XCTestCase *test = [[testClass alloc] init];
    [test setUp];
    [test performSelector:selector];
    [test tearDown];
}

@end
