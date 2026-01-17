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

@interface TestImplementation : NSObject <TestProtocol>
@end

@implementation TestImplementation
- (NSString *)testMethod { return @"success"; }
@end

@interface PDSServiceContainerTests : XCTestCase
@end

@implementation PDSServiceContainerTests

- (void)setUp {
    [super setUp];
    [[PDSServiceContainer sharedContainer] reset];
}

- (void)testRegisterInstance {
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

- (void)testReset {
    PDSServiceContainer *container = [PDSServiceContainer sharedContainer];
    [container registerInstance:[[TestImplementation alloc] init] forProtocol:@protocol(TestProtocol)];
    
    [container reset];
    
    XCTAssertNil([container resolveProtocol:@protocol(TestProtocol)]);
}

@end
