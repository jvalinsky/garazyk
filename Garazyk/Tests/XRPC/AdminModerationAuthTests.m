#import <XCTest/XCTest.h>
#import "Network/AdminAuthXrpcTestBase.h"

@interface AdminModerationAuthTests : AdminAuthXrpcTestBase
@end

@implementation AdminModerationAuthTests

- (void)testModerateAccountReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"action": @"flag"
                                                      }
                                                   headers:nil];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testModerateAccountReturnsForbiddenForNonAdmin {
    NSDictionary *headers = @{@"authorization": [NSString stringWithFormat:@"Bearer %@", self.userJwt]};
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"action": @"flag"
                                                      }
                                                   headers:headers];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testModerateRecordReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"action": @"flag"
                                                      }
                                                   headers:nil];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testModerateRecordReturnsForbiddenForNonAdmin {
    NSDictionary *headers = @{@"authorization": [NSString stringWithFormat:@"Bearer %@", self.userJwt]};
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"action": @"flag"
                                                      }
                                                   headers:headers];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testGetSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:nil];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetSubjectStatusNonAdminForbidden {
    NSDictionary *headers = @{@"authorization": [NSString stringWithFormat:@"Bearer %@", self.userJwt]};
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:headers];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testUpdateSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                      body:@{
                                                          @"subject": @{@"did": self.userDid},
                                                          @"takedown": @{@"applied": @YES}
                                                      }
                                                   headers:nil];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateSubjectStatusNonAdminForbidden {
    NSDictionary *headers = @{@"authorization": [NSString stringWithFormat:@"Bearer %@", self.userJwt]};
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                      body:@{
                                                          @"subject": @{@"did": self.userDid},
                                                          @"takedown": @{@"applied": @YES}
                                                      }
                                                   headers:headers];
    XCTAssertEqual(response.statusCode, 403);
}

@end
