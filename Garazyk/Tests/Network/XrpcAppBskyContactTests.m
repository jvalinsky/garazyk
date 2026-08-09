// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyContactTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyContactTests

#pragma mark - startPhoneVerification Tests

- (void)testStartPhoneVerificationRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.startPhoneVerification"
                                                      body:@{@"phoneNumber": @"+1234567890"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testStartPhoneVerificationRequiresPhoneNumber {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.startPhoneVerification"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - verifyPhone Tests

- (void)testVerifyPhoneRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.verifyPhone"
                                                      body:@{@"phoneNumber": @"+1234567890", @"code": @"123456"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testVerifyPhoneRequiresFields {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.verifyPhone"
                                                      body:@{@"phoneNumber": @"+1234567890"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - importContacts Tests

- (void)testImportContactsRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.importContacts"
                                                      body:@{@"token": @"tok", @"contacts": @[]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testImportContactsRequiresFields {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.importContacts"
                                                      body:@{@"token": @"tok"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - getMatches Tests

- (void)testGetMatchesRequiresAuth {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.contact.getMatches"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetMatchesRejectsInvalidToken {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.contact.getMatches"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": @"Bearer invalid-token"}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - dismissMatch Tests

- (void)testDismissMatchRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.dismissMatch"
                                                      body:@{@"did": @"did:plc:other"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDismissMatchRequiresDid {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.dismissMatch"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - getSyncStatus Tests

- (void)testGetSyncStatusRequiresAuth {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.contact.getSyncStatus"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetSyncStatusRejectsInvalidToken {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.contact.getSyncStatus"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": @"Bearer invalid-token"}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - removeData Tests

- (void)testRemoveDataRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.removeData"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - sendNotification Tests

- (void)testSendNotificationRequiresFields {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.contact.sendNotification"
                                                      body:@{@"from": @"did:plc:test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

@end
