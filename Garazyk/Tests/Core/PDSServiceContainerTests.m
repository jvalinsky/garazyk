// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSServiceContainerTests.m
 @abstract Unit tests for PDSServiceContainer.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Core/PDSServiceContainer.h"

@protocol TestProtocol <NSObject>
- (NSString *)testMethod;
@end

@protocol RecursiveProtocol <NSObject>
- (NSString *)recursiveMethod;
@end

@interface TestImplementation : NSObject <TestProtocol>
@end

@implementation TestImplementation
- (NSString *)testMethod { return @"success"; }
@end

@interface RecursiveImplementation : NSObject <RecursiveProtocol>
@end

@implementation RecursiveImplementation
- (NSString *)recursiveMethod {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    id<TestProtocol> test = [container resolveProtocol:@protocol(TestProtocol)];
    return [test testMethod];
}
@end

@interface PDSServiceContainerTests : XCTestCase
@end

@implementation PDSServiceContainerTests

- (void)setUp {
    [super setUp];
    [[PDSServiceContainer sharedContainer] reset];
}

- (void)testResolveProtocolReturnsRegisteredInstance {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    TestImplementation *impl = [[TestImplementation alloc] init];
    
    [container registerInstance:impl forProtocol:@protocol(TestProtocol)];
    
    id resolved = [container resolveProtocol:@protocol(TestProtocol)];
    XCTAssertEqual(resolved, impl);
}

- (void)testRegisterFactory {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    __block BOOL factoryCalled = NO;
    
    [container registerFactory:^id _Nonnull(PDSServiceContainer * _Nonnull c) {
        factoryCalled = YES;
        return [[TestImplementation alloc] init];
    } forProtocol:@protocol(TestProtocol)];
    
    XCTAssertFalse(factoryCalled, "Factory should not be called before resolution");
    
    id resolved = [container resolveProtocol:@protocol(TestProtocol)];
    XCTAssertTrue(factoryCalled, "Factory should be called on resolution");
    XCTAssertTrue([resolved conformsToProtocol:@protocol(TestProtocol)]);
    
    // Second resolution should return cached instance
    factoryCalled = NO;
    id resolved2 = [container resolveProtocol:@protocol(TestProtocol)];
    XCTAssertFalse(factoryCalled, "Factory should not be called again");
    XCTAssertEqual(resolved, resolved2);
}

- (void)testResolveProtocolReturnsNilAfterReset {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    [container registerInstance:[[TestImplementation alloc] init] forProtocol:@protocol(TestProtocol)];
    
    [container reset];
    
    XCTAssertNil([container resolveProtocol:@protocol(TestProtocol)]);
}

- (void)testRecursiveResolution {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    
    [container registerInstance:[[TestImplementation alloc] init] forProtocol:@protocol(TestProtocol)];
    
    [container registerFactory:^id _Nonnull(PDSServiceContainer * _Nonnull c) {
        return [[RecursiveImplementation alloc] init];
    } forProtocol:@protocol(RecursiveProtocol)];
    
    // This would deadlock if _lock was a serial queue instead of NSRecursiveLock
    id<RecursiveProtocol> resolved = [container resolveProtocol:@protocol(RecursiveProtocol)];
    XCTAssertNotNil(resolved);
    XCTAssertEqualObjects([resolved recursiveMethod], @"success");
}

@end
