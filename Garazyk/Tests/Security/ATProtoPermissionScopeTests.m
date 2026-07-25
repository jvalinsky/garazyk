// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Security/ATProtoPermissionScope.h"

@interface ATProtoPermissionScopeTests : XCTestCase
@end

@implementation ATProtoPermissionScopeTests

#pragma mark - Repo scope

- (void)testRepoScopeSingleCollection {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo:app.bsky.feed.post" error:&error];
  XCTAssertNotNil(scope, @"parse error: %@", error);
  XCTAssertNil(error);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceRepo);
  XCTAssertEqualObjects(scope.collections, @[@"app.bsky.feed.post"]);
  XCTAssertNil(scope.actions, @"nil actions means all actions allowed");
  XCTAssertTrue([scope matchesCollection:@"app.bsky.feed.post" action:@"create"]);
  XCTAssertTrue([scope matchesCollection:@"app.bsky.feed.post" action:@"update"]);
  XCTAssertTrue([scope matchesCollection:@"app.bsky.feed.post" action:@"delete"]);
  XCTAssertFalse([scope matchesCollection:@"app.bsky.actor.profile" action:@"create"]);
}

- (void)testRepoScopeWildcard {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo:*" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqualObjects(scope.collections, @[@"*"]);
  XCTAssertTrue([scope matchesCollection:@"com.any.collection" action:@"create"]);
}

- (void)testRepoScopeExplicitActions {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo:app.bsky.feed.post?action=create&action=delete" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqualObjects(scope.actions, (@[@"create", @"delete"]));
  XCTAssertTrue([scope matchesCollection:@"app.bsky.feed.post" action:@"create"]);
  XCTAssertTrue([scope matchesCollection:@"app.bsky.feed.post" action:@"delete"]);
  XCTAssertFalse([scope matchesCollection:@"app.bsky.feed.post" action:@"update"]);
}

- (void)testRepoScopeMultipleCollectionsViaQuery {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo?collection=app.bsky.feed.post&collection=app.bsky.actor.profile" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqualObjects([NSSet setWithArray:scope.collections], [NSSet setWithArray:(@[@"app.bsky.actor.profile", @"app.bsky.feed.post"])]);
}

- (void)testRepoScopeRequiresCollection {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo:?action=create" error:&error];
  XCTAssertNil(scope);
  XCTAssertNotNil(error);
}

#pragma mark - RPC scope

- (void)testRPCScopeSpecificMethod {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"rpc:app.bsky.actor.getProfile?aud=did:web:api.example.com%23appview" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceRPC);
  XCTAssertEqualObjects(scope.lxm, @[@"app.bsky.actor.getProfile"]);
  XCTAssertEqualObjects(scope.aud, @"did:web:api.example.com#appview");
  XCTAssertTrue([scope matchesMethod:@"app.bsky.actor.getProfile" aud:@"did:web:api.example.com#appview"]);
  XCTAssertFalse([scope matchesMethod:@"app.bsky.actor.getProfile" aud:@"did:web:other.com#appview"]);
  XCTAssertFalse([scope matchesMethod:@"app.bsky.feed.getTimeline" aud:@"did:web:api.example.com#appview"]);
}

- (void)testRPCScopeWildcardLXMRequiresAud {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"rpc?lxm=*&aud=did:web:api.example.com%23appview" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqualObjects(scope.lxm, @[@"*"]);
  XCTAssertTrue([scope matchesMethod:@"any.method.here" aud:@"did:web:api.example.com#appview"]);
}

- (void)testRPCScopeWildcardBothRejected {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"rpc?lxm=*&aud=*" error:&error];
  XCTAssertNil(scope, @"Wildcard both lxm and aud should be rejected");
  XCTAssertNotNil(error);
}

#pragma mark - Blob scope

- (void)testBlobScopeSpecificType {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"blob:image/png" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceBlob);
  XCTAssertTrue([scope matchesBlobAccept:@"image/png"]);
  XCTAssertFalse([scope matchesBlobAccept:@"video/mp4"]);
}

- (void)testBlobScopeWildcard {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"blob:*/*" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertTrue([scope matchesBlobAccept:@"video/mp4"]);
  XCTAssertTrue([scope matchesBlobAccept:@"text/html"]);
}

- (void)testBlobScopePartialWildcard {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"blob?accept=video/*" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertTrue([scope matchesBlobAccept:@"video/mp4"]);
  XCTAssertTrue([scope matchesBlobAccept:@"video/webm"]);
  XCTAssertFalse([scope matchesBlobAccept:@"image/png"]);
}

#pragma mark - Account scope

- (void)testAccountScopeEmailRead {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"account:email" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceAccount);
  XCTAssertEqualObjects(scope.attr, @"email");
  XCTAssertEqualObjects(scope.accountAction, @"read");
  XCTAssertTrue([scope matchesAccountAttr:@"email" action:@"read"]);
  XCTAssertFalse([scope matchesAccountAttr:@"email" action:@"manage"]);
  XCTAssertFalse([scope matchesAccountAttr:@"repo" action:@"read"]);
}

- (void)testAccountScopeRepoManage {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"account:repo?action=manage" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqualObjects(scope.attr, @"repo");
  XCTAssertEqualObjects(scope.accountAction, @"manage");
  XCTAssertTrue([scope matchesAccountAttr:@"repo" action:@"manage"]);
  XCTAssertTrue([scope matchesAccountAttr:@"repo" action:@"read"], @"manage implies read");
}

#pragma mark - Identity scope

- (void)testIdentityScopeHandle {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"identity:handle" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceIdentity);
  XCTAssertEqualObjects(scope.identityAttr, @"handle");
  XCTAssertTrue([scope matchesIdentityAttr:@"handle"]);
  XCTAssertFalse([scope matchesIdentityAttr:@"did"]);
}

- (void)testIdentityScopeWildcard {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"identity:*" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertTrue([scope matchesIdentityAttr:@"handle"]);
  XCTAssertTrue([scope matchesIdentityAttr:@"did"]);
}

- (void)testIdentityScopeRejectsUnknownAttribute {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"identity:did" error:nil]);
}

- (void)testIncludeScopeRejectsWildcardAndDuplicateAudience {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"include:*" error:nil]);
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"include:app.example.permissions?aud=one&aud=two" error:nil]);
}

- (void)testAccountScopeRejectsDuplicateAction {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"account:email?action=read&action=manage" error:nil]);
}

#pragma mark - Include scope

- (void)testIncludeScope {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"include:com.example.authBasic?aud=did:web:api.example.com%23appview" error:&error];
  XCTAssertNotNil(scope);
  XCTAssertEqual(scope.resourceType, ATProtoPermissionScopeResourceInclude);
  XCTAssertEqualObjects(scope.permissionSetNSID, @"com.example.authBasic");
  XCTAssertEqualObjects(scope.aud, @"did:web:api.example.com#appview");
}

#pragma mark - Negative cases

- (void)testEmptyStringRejected {
  NSError *error = nil;
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"" error:&error]);
  XCTAssertNotNil(error);
}

- (void)testSpaceRejected {
  NSError *error = nil;
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"repo :foo" error:&error]);
}

- (void)testUnknownResourceRejected {
  NSError *error = nil;
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"unknown:foo" error:&error]);
  XCTAssertNotNil(error);
}

- (void)testInvalidCollectionNSIDRejected {
  NSError *error = nil;
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"repo:not a valid nsid" error:&error]);
}

- (void)testScopeResourceTypesAreCaseSensitive {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"Repo:app.bsky.feed.post" error:nil]);
}

- (void)testDuplicatePositionalParameterIsRejected {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"repo:app.bsky.feed.post?collection=app.bsky.actor.profile" error:nil]);
}

- (void)testUnsupportedParameterIsRejected {
  XCTAssertNil([ATProtoPermissionScope scopeWithString:@"repo:app.bsky.feed.post?unexpected=value" error:nil]);
}

- (void)testTypeStringRepresentation {
  NSError *error = nil;
  ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:@"repo:app.test.r" error:&error];
  XCTAssertEqualObjects(scope.resourceTypeString, @"repo");
}

@end
