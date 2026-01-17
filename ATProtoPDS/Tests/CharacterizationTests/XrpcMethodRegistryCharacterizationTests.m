#import "CharacterizationTestBase.h"
#import "Network/XrpcMethodRegistry.h"

@interface XrpcMethodRegistryCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) XrpcMethodRegistry *subject;

@end

@implementation XrpcMethodRegistryCharacterizationTests

- (void)setUp {
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[XrpcMethodRegistry alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for XrpcMethodRegistry
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_Class_registerMethodsWithDispatcher {
    /* Target Method:
     + (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [XrpcMethodRegistry registerMethodsWithDispatcher...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_Class_publicKeyBytesFromMultibase {
    /* Target Method:
     + (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase error:(NSError **)error;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [XrpcMethodRegistry publicKeyBytesFromMultibase...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

@end
