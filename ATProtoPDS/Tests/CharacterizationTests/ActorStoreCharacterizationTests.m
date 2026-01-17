#import "CharacterizationTestBase.h"
#import "Database/PDSDatabase.h"

@interface ActorStoreCharacterizationTests : CharacterizationTestBase
@end

@implementation ActorStoreCharacterizationTests

- (void)testCharacterization_CreateAccount_NilAccount {
    // Goal: Characterize current behavior when passing nil
    NSError *error = nil;
    BOOL result = [self.testActorStore createAccount:nil error:&error];
    
    // RECORD: Current implementation fails gracefully? Or crashes?
    // Assuming for now it returns NO and sets valid error or param error
    // If it crashes, this test documents that fragile behavior (though we hope for NO)
    
    // Based on inspection, we likely expect:
    XCTAssertFalse(result, @"Should fail with nil account");
    XCTAssertNotNil(error, @"Should return an error");
}

- (void)testCharacterization_CreateAccount_ValidAccount {
    // Goal: Characterize success path
    NSString *did = @"did:plc:1234567890abcdef";
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = @"alice.test";
    account.email = @"alice@example.com";
    account.passwordHash = [@"hashed_password" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    BOOL result = [self.testActorStore createAccount:account error:&error];
    
    XCTAssertTrue(result, @"Should succeed with valid account");
    XCTAssertNil(error, @"Should not return error");
    
    // Characterize Side Effects: Database state
    PDSDatabaseAccount *fetched = [self.testActorStore getAccountForDid:did error:&error];
    XCTAssertNotNil(fetched, @"Should be able to retrieve account");
    XCTAssertEqualObjects(fetched.handle, @"alice.test", @"Handle should match");
}

@end
