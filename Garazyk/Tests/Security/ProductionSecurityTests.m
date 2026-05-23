// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/XrpcMethodRegistry.h"
#import "Security/GZAuthzManager.h"
#import "Admin/PDSAdminAuth.h"
#import "Identity/ATProtoHandleValidator.h"
#import "App/ATProtoServiceConfiguration.h"

@interface ProductionSecurityTests : XCTestCase
@end

@implementation ProductionSecurityTests

- (void)testAdminAuthHardening {
    // 1. Verify GZAuthzManager no longer allows handle/DID based admin
    GZAuthzManager *authz = [GZAuthzManager sharedManager];
    NSError *error = nil;
    
    // Valid looking admin handle/did but NO JWT logic here (GZAuthzManager was the old heuristic way)
    // We expect this to fail now.
    BOOL authorized = [authz isAuthorizedForAdminOperation:@"did:plc:admin" error:&error];
    XCTAssertFalse(authorized, @"GZAuthzManager must return NO for heuristic admin checks");
    XCTAssertNotNil(error);
}

- (void)testHandleReservation {
    NSError *error = nil;
    BOOL valid = [ATProtoHandleValidator validateHandle:@"admin.bsky.social" error:&error];
    XCTAssertFalse(valid, @"Handle starting with 'admin.' must be rejected");
    XCTAssertEqual(error.code, 1009);
    
    error = nil;
    valid = [ATProtoHandleValidator validateHandle:@"admin.test" error:&error];
    XCTAssertFalse(valid, @"Handle starting with 'admin.' must be rejected");

    error = nil;
    valid = [ATProtoHandleValidator validateHandle:@"bob.test" error:&error];
    XCTAssertTrue(valid, @"Regular handle should be accepted");
}

@end
