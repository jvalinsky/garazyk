// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Security/ATProtoPermissionScopeEvaluator.h"
#import "Security/ATProtoPermissionScope.h"
#import "Security/ATProtoPermissionSetResolver.h"

@interface ATProtoPermissionScopeEvaluatorTests : XCTestCase
@end

@implementation ATProtoPermissionScopeEvaluatorTests

#pragma mark - Scope Extraction

- (void)testExtractsRepoScopesFromScopeString {
  NSString *scopeString = @"repo:app.bsky.feed.post?action=create rpc:app.bsky.actor.getProfile";
  NSArray<ATProtoPermissionScope *> *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:scopeString];
  XCTAssertEqual(scopes.count, 2);
  BOOL hasRepo = NO, hasRPC = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceRepo) hasRepo = YES;
    if (scope.resourceType == ATProtoPermissionScopeResourceRPC) hasRPC = YES;
  }
  XCTAssertTrue(hasRepo);
  XCTAssertTrue(hasRPC);
}

- (void)testSkipsSpaceScopes {
  NSString *scopeString = @"space:com.example.group repo:app.bsky.feed.post";
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:scopeString];
  XCTAssertEqual(scopes.count, 1);
  XCTAssertEqual(((ATProtoPermissionScope *)scopes[0]).resourceType, ATProtoPermissionScopeResourceRepo);
}

- (void)testEmptyScopeStringReturnsEmpty {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@""];
  XCTAssertEqual(scopes.count, 0);
}

- (void)testNilScopeStringReturnsEmpty {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:nil];
  XCTAssertEqual(scopes.count, 0);
}

- (void)testIgnoresInvalidScopeStrings {
  NSString *scopeString = @"repo:com.example.valid totally-invalid-scope blob:image/png";
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:scopeString];
  XCTAssertEqual(scopes.count, 2);
}

#pragma mark - Permission-set expansion

- (void)testExpandsPermissionSetIntoConcreteRepoAndRPCScopes {
  NSDictionary *schema = @{
    @"defs" : @{ @"main" : @{
      @"type" : @"permission-set",
      @"permissions" : @[
        @{ @"type" : @"permission", @"resource" : @"repo",
           @"collection" : @[ @"com.example.calendar.event" ],
           @"action" : @[ @"create", @"delete" ] },
        @{ @"type" : @"permission", @"resource" : @"rpc",
           @"lxm" : @[ @"com.example.calendar.listEvents" ], @"inheritAud" : @YES },
      ]
    } }
  };
  NSError *error = nil;
  NSString *effective = [ATProtoPermissionSetResolver effectiveScopeForScope:@"atproto include:example.lexicon.perms?aud=did:web:api.example.com%23calendar"
                                                         permissionSetSchemas:@{ @"example.lexicon.perms" : schema }
                                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([effective containsString:@"repo?collection=com.example.calendar.event&action=create&action=delete"]);
  XCTAssertTrue([effective containsString:@"rpc?lxm=com.example.calendar.listEvents&aud=did:web:api.example.com%23calendar"]);
}

- (void)testRejectsPermissionSetWithUnsupportedResource {
  NSDictionary *schema = @{
    @"defs" : @{ @"main" : @{
      @"type" : @"permission-set",
      @"permissions" : @[ @{ @"type" : @"permission", @"resource" : @"blob", @"accept" : @[ @"image/png" ] } ]
    } }
  };
  XCTAssertNil([ATProtoPermissionSetResolver effectiveScopeForScope:@"atproto include:example.lexicon.perms"
                                               permissionSetSchemas:@{ @"example.lexicon.perms" : schema }
                                                              error:nil]);
}

#pragma mark - RPC Scope Evaluation

- (void)testRPCScopeAllowsMatchingMethod {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:app.bsky.actor.getProfile"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.actor.getProfile" audience:nil]);
}

- (void)testRPCScopeRejectsNonMatchingMethod {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:app.bsky.actor.getProfile"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.feed.getTimeline" audience:nil]);
}

- (void)testRPCScopeWithAudienceCheck {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:app.bsky.actor.getProfile?aud=did:web:api.example.com"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.actor.getProfile" audience:@"did:web:api.example.com"]);
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.actor.getProfile" audience:@"did:web:other.com"]);
}

- (void)testRPCScopeWildcardAllowsAnyMethod {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:*?aud=did:web:api.example.com"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"any.method.here" audience:@"did:web:api.example.com"]);
}

- (void)testNoRPCScopesFailOpen {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"repo:app.bsky.feed.post"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"any.method" audience:nil]);
}

- (void)testEmptyScopesFailOpen {
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:@[] forMethod:@"any.method" audience:nil]);
}

- (void)testRPCScopeRejectsServiceAuthWithoutMethod {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:app.bsky.actor.getProfile?aud=did:web:api.example.com%23appview"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:nil audience:@"did:web:api.example.com#appview"]);
}

#pragma mark - Repo Scope Evaluation

- (void)testRepoScopeAllowsMatchingCollectionAndAction {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"repo:app.bsky.feed.post?action=create"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"app.bsky.feed.post" action:@"create"]);
}

- (void)testRepoScopeRejectsNonMatchingAction {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"repo:app.bsky.feed.post?action=create"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"app.bsky.feed.post" action:@"delete"]);
}

- (void)testRepoScopeRejectsNonMatchingCollection {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"repo:app.bsky.feed.post"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"app.bsky.actor.profile" action:@"create"]);
}

- (void)testRepoScopeWildcardAllowsAnyCollection {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"repo:*"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"com.any.collection" action:@"create"]);
}

- (void)testNoRepoScopesFailOpen {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"rpc:app.bsky.actor.getProfile"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"any.collection" action:@"create"]);
}

#pragma mark - Blob Scope Evaluation

- (void)testBlobScopeAllowsMatchingType {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"blob:image/png"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateBlobScopes:scopes forMIME:@"image/png"]);
}

- (void)testBlobScopeRejectsNonMatchingType {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"blob:image/png"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateBlobScopes:scopes forMIME:@"video/mp4"]);
}

- (void)testBlobScopeWildcardAllowsAnyType {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"blob:*/*"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateBlobScopes:scopes forMIME:@"video/mp4"]);
}

#pragma mark - Account Scope Evaluation

- (void)testAccountScopeAllowsMatchingAttrAndAction {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"account:email?action=read"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateAccountScopes:scopes forAttribute:@"email" action:@"read"]);
}

- (void)testAccountScopeRejectsNonMatchingAction {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"account:email"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateAccountScopes:scopes forAttribute:@"email" action:@"manage"]);
}

- (void)testNoAccountScopesFailOpen {
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateAccountScopes:@[] forAttribute:@"email" action:@"read"]);
}

#pragma mark - Identity Scope Evaluation

- (void)testIdentityScopeAllowsMatchingAttr {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"identity:handle"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:scopes forAttribute:@"handle"]);
}

- (void)testIdentityScopeRejectsNonMatchingAttr {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"identity:handle"];
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:scopes forAttribute:@"did"]);
}

- (void)testIdentityScopeWildcardAllowsAnyAttr {
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:@"identity:*"];
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:scopes forAttribute:@"anything"]);
}

- (void)testNoIdentityScopesFailOpen {
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:@[] forAttribute:@"handle"]);
}

#pragma mark - Mixed Scope Sets

- (void)testMixedScopesEvaluateCorrectlyPerType {
  NSString *scopeString = @"repo:app.bsky.feed.post?action=create rpc:app.bsky.actor.getProfile blob:image/png identity:handle";
  NSArray *scopes = [ATProtoPermissionScopeEvaluator scopesFromScopeString:scopeString];
  XCTAssertEqual(scopes.count, 4);

  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"app.bsky.feed.post" action:@"create"]);
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRepoScopes:scopes forCollection:@"app.bsky.feed.post" action:@"delete"]);
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.actor.getProfile" audience:nil]);
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateRPCScopes:scopes forMethod:@"app.bsky.feed.getTimeline" audience:nil]);
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateBlobScopes:scopes forMIME:@"image/png"]);
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateBlobScopes:scopes forMIME:@"video/mp4"]);
  XCTAssertTrue([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:scopes forAttribute:@"handle"]);
  XCTAssertFalse([ATProtoPermissionScopeEvaluator evaluateIdentityScopes:scopes forAttribute:@"did"]);
}

@end
