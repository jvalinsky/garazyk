#import "CharacterizationTestBase.h"
#import "Auth/Session.h"

@interface SessionCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) Session *subject;

@end

@implementation SessionCharacterizationTests

- (void)setUp {
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[Session alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for Session
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_Class_sessionWithDID {
    /* Target Method:
     + (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [Session sessionWithDID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_Class_sessionWithDID_2 {
    /* Target Method:
     + (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [Session sessionWithDID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_initWithDID {
    /* Target Method:
     - (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithDID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_initWithDID_2 {
    /* Target Method:
     - (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope
                    minter:(nullable JWTMinter *)minter;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject initWithDID...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toTokenResponse {
    /* Target Method:
     - (NSDictionary *)toTokenResponse;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toTokenResponse...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_toBearerTokenResponse {
    /* Target Method:
     - (NSDictionary *)toBearerTokenResponse;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject toBearerTokenResponse...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

- (void)testCharacterization_refreshAccessToken {
    /* Target Method:
     - (NSString *)refreshAccessToken;
    */
    
    // 1. Arrange
    
    // 2. Act
    // [self.subject refreshAccessToken...];
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}

@end
