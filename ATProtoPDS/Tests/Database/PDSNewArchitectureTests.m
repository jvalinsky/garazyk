#import <XCTest/XCTest.h>

@interface PDSNewArchitectureTests : XCTestCase

@end

@implementation PDSNewArchitectureTests

- (void)testActorStoreTests {
    [self invokeTest:[ActorStoreTests class] selector:@selector(testStoreInitialization)];
}

- (void)testDatabasePoolTests {
    [self invokeTest:[DatabasePoolTests class] selector:@selector(testPoolInitialization)];
}

- (void)testServiceDatabasesTests {
    [self invokeTest:[ServiceDatabasesTests class] selector:@selector(testServiceDatabasesInitialization)];
}

- (void)testPDSControllerTests {
    [self invokeTest:[PDSControllerTests class] selector:@selector(testControllerInitialization)];
}

- (void)invokeTest:(Class)testClass selector:(SEL)selector {
    XCTestCase *test = [[testClass alloc] init];
    [test setUp];
    [test performSelector:selector];
    [test tearDown];
}

@end
