// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"

@interface XrpcChatBskyActorTests : AdminAuthXrpcTestBase
@end

@implementation XrpcChatBskyActorTests

- (void)testDeleteAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.actor.deleteAccount"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteAccountSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.actor.deleteAccount"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testExportAccountDataSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.actor.exportAccountData"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"conversations"]);
}

#pragma mark - Chat Moderation

- (void)testGetActorMetadataSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.moderation.getActorMetadata"
                                              queryString:[NSString stringWithFormat:@"actor=%@", self.userDid]
                                              queryParams:@{@"actor": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.userDid);
}

- (void)testUpdateActorAccessSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.moderation.updateActorAccess"
                                                      body:@{
                                                          @"actor": self.userDid,
                                                          @"access": @{
                                                              @"muted": @YES,
                                                              @"blocked": @NO
                                                          }
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

@end
