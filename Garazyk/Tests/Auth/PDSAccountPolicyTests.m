// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/PDS/PDSAuth.h"

@interface PDSAccountPolicyTestAdmin : NSObject
@property (nonatomic, assign) BOOL takedownActive;
@property (nonatomic, assign) BOOL admin;
@end

@implementation PDSAccountPolicyTestAdmin

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    return self.takedownActive;
}

- (BOOL)isAdmin:(NSString *)did error:(NSError **)error {
    return self.admin;
}

@end

@interface PDSAccountPolicyTests : XCTestCase
@end

@implementation PDSAccountPolicyTests

- (void)testMissingAdminControllerFailsClosedWithError {
    PDSAccountPolicy *policy = [[PDSAccountPolicy alloc] initWithDatabase:nil
                                                            adminController:nil];
    NSError *error = nil;
    XCTAssertFalse([policy isAccountAllowed:@"did:plc:alice" error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"com.atproto.pds.auth");
}

- (void)testInjectedAdminControllerDeterminesAccountAndAdminStatus {
    PDSAccountPolicyTestAdmin *admin = [[PDSAccountPolicyTestAdmin alloc] init];
    PDSAccountPolicy *policy = [[PDSAccountPolicy alloc] initWithDatabase:nil
                                                            adminController:admin];
    NSError *error = nil;
    XCTAssertTrue([policy isAccountAllowed:@"did:plc:alice" error:&error]);
    XCTAssertNil(error);

    admin.takedownActive = YES;
    XCTAssertFalse([policy isAccountAllowed:@"did:plc:alice" error:&error]);

    admin.admin = YES;
    XCTAssertTrue([policy isAdmin:@"did:plc:alice" error:&error]);
}

@end
