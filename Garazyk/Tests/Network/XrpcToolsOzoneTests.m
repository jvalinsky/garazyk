#import "AdminAuthXrpcTestBase.h"

@interface XrpcToolsOzoneTests : AdminAuthXrpcTestBase
@end

@implementation XrpcToolsOzoneTests

#pragma mark - Moderation Events Tests

- (void)testEmitModerationEventRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.moderation.emitEvent"
                                                      body:@{@"event": @{}}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testEmitModerationEventRequiresAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.moderation.emitEvent"
                                                      body:@{@"event": @{}}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testEmitModerationEventSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    NSDictionary *event = @{
        @"type": @"takedown",
        @"subject": @{@"did": self.userDid},
        @"reason": @"spam"
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.moderation.emitEvent"
                                                      body:@{@"event": event}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"event"]);
}

- (void)testQueryModerationStatusesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testQueryModerationStatusesSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                                             queryString:@"limit=10"
                                             queryParams:@{@"limit": @"10"}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"statuses"]);
}

- (void)testQueryModerationEventsSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.queryEvents"
                                             queryString:@"limit=10"
                                             queryParams:@{@"limit": @"10"}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"events"]);
}

- (void)testGetModerationEventRequiresId {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getEvent"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetModerationRecordRequireUri {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getRecord"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetModerationRecordSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/abc123", self.userDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getRecord"
                                             queryString:[NSString stringWithFormat:@"uri=%@", uri]
                                             queryParams:@{@"uri": uri}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"record"]);
}

- (void)testGetModerationRepoRequiresDid {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getRepo"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetModerationRepoSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getRepo"
                                             queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                             queryParams:@{@"did": self.userDid}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"repo"]);
}

- (void)testGetSubjectStatusSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.moderation.getSubjectStatus"
                                             queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                             queryParams:@{@"did": self.userDid}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"status"]);
}

- (void)testScheduleActionRequiresAction {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.moderation.scheduleAction"
                                                      body:@{}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testScheduleActionSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    NSDictionary *action = @{@"type": @"takedown", @"subject": self.userDid};
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.moderation.scheduleAction"
                                                      body:@{@"action": action}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

#pragma mark - Team Management Tests

- (void)testAddTeamMemberRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.team.addMember"
                                                      body:@{@"email": @"member@example.com", @"role": @"moderator"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAddTeamMemberSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.team.addMember"
                                                      body:@{@"email": @"member@example.com", @"role": @"moderator"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

- (void)testUpdateTeamMemberSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.team.updateMember"
                                                      body:@{@"email": @"member@example.com", @"role": @"admin"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testDeleteTeamMemberSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.team.deleteMember"
                                                      body:@{@"email": @"member@example.com"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testListTeamMembersSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.team.listMembers"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"members"]);
}

#pragma mark - Set Management Tests

- (void)testCreateSetRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.set.create"
                                                      body:@{@"name": @"blocklist"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateSetSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.set.create"
                                                      body:@{@"name": @"blocklist"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

- (void)testUpdateSetSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.set.update"
                                                      body:@{@"id": @"set123", @"name": @"updated-list"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testDeleteSetSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.set.delete"
                                                      body:@{@"id": @"set123"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testGetSetSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.set.get"
                                             queryString:@"id=set123"
                                             queryParams:@{@"id": @"set123"}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"set"]);
}

- (void)testListSetsSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.set.list"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"sets"]);
}

- (void)testAddSetValuesSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.set.addValues"
                                                      body:@{@"id": @"set123", @"values": @[@"did:plc:abc"]}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

#pragma mark - Communication Template Tests

- (void)testCreateCommunicationTemplateSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.communication.createTemplate"
                                                      body:@{
                                                          @"name": @"welcome",
                                                          @"contentMarkdown": @"Welcome to moderation"
                                                      }
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

- (void)testUpdateCommunicationTemplateSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.communication.updateTemplate"
                                                      body:@{
                                                          @"id": @"template123",
                                                          @"name": @"updated",
                                                          @"contentMarkdown": @"Updated content"
                                                      }
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testDeleteCommunicationTemplateSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.communication.deleteTemplate"
                                                      body:@{@"id": @"template123"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testListCommunicationTemplatesSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.communication.listTemplates"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"templates"]);
}

#pragma mark - Verification Tests

- (void)testGrantVerificationSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.verification.grantVerification"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"id"]);
}

- (void)testRevokeVerificationSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.verification.revokeVerification"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testListVerificationsSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.verification.listVerifications"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"verifications"]);
}

#pragma mark - Server Config Tests

- (void)testGetServerConfigSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/tools.ozone.server.getConfig"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"serverName"]);
}

- (void)testUpdateServerConfigSuccessfully {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/tools.ozone.server.updateConfig"
                                                      body:@{@"setting": @"value"}
                                                   headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

@end
