// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Security/Space/PDSSpaceScope.h"
#import "Security/Space/PDSSpaceURI.h"

@interface PDSSpaceURIAndScopeTests : XCTestCase
@end

@implementation PDSSpaceURIAndScopeTests

- (void)testParsesAndCanonicalizesCompletePermissionedRecordURI {
  NSError *error = nil;
  PDSSpaceURI *URI = [PDSSpaceURI
      URIWithString:@"at://did:example:authority/space/com.example.group/team%2Fone/"
                    "did:example:author/com.example.note/record-1"
             error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(URI);
  XCTAssertTrue(URI.isRecordURI);
  XCTAssertEqualObjects(URI.spaceURI,
                        @"at://did:example:authority/space/com.example.group/team%2Fone");
  XCTAssertEqualObjects(URI.authorDID, @"did:example:author");
  XCTAssertEqualObjects(URI.collection, @"com.example.note");
  XCTAssertEqualObjects(URI.rkey, @"record-1");
}

- (void)testRejectsPartialOrQualifiedSpaceURIs {
  NSArray<NSString *> *invalid = @[
    @"at://did:example:authority/space/com.example.group",
    @"at://did:example:authority/space/com.example.group/key/did:example:author",
    @"at://did:example:authority/space/com.example.group/key?x=1",
    @"at://did:example:authority/space/com.example.group/key/author/com.example.note/record",
  ];
  for (NSString *value in invalid) {
    NSError *error = nil;
    XCTAssertNil([PDSSpaceURI URIWithString:value error:&error], @"%@", value);
    XCTAssertNotNil(error, @"%@", value);
  }
}

- (void)testReadSelfDoesNotGrantWholeSpaceRead {
  PDSSpaceScope *scope = [PDSSpaceScope
      scopeWithString:@"space:com.example.group?collection=com.example.note&action=read_self"
                error:nil];
  PDSSpaceURI *space = [self spaceURI];
  XCTAssertFalse([scope matchesSpace:space
                             action:PDSSpaceActionReadSelf
                         collection:@"com.example.note"]);
  scope = [scope scopeByResolvingSelfAuthorityForDID:@"did:example:authority"];

  XCTAssertFalse([scope matchesSpace:space action:PDSSpaceActionRead collection:nil]);
  XCTAssertTrue([scope matchesSpace:space
                             action:PDSSpaceActionReadSelf
                         collection:@"com.example.note"]);
  XCTAssertFalse([scope matchesSpace:space
                             action:PDSSpaceActionReadSelf
                         collection:@"com.example.other"]);
}

- (void)testDefaultActionsHaveNoWriteCollectionAndReadImpliesReadSelf {
  PDSSpaceScope *scope = [PDSSpaceScope scopeWithString:@"space:com.example.group" error:nil];
  PDSSpaceURI *space = [self spaceURI];
  scope = [scope scopeByResolvingSelfAuthorityForDID:@"did:example:authority"];

  XCTAssertTrue([scope matchesSpace:space action:PDSSpaceActionRead collection:nil]);
  XCTAssertTrue([scope matchesSpace:space
                             action:PDSSpaceActionReadSelf
                         collection:@"com.example.note"]);
  XCTAssertFalse([scope matchesSpace:space
                             action:PDSSpaceActionCreate
                         collection:@"com.example.note"]);
}

- (void)testScopeResolvesSelfAndEnforcesTupleCollectionAndManage {
  PDSSpaceScope *scope = [PDSSpaceScope
      scopeWithString:@"space:com.example.group?collection=com.example.note&action=create&manage=update"
                error:nil];
  PDSSpaceURI *space = [self spaceURI];
  XCTAssertFalse([scope matchesSpace:space action:PDSSpaceActionCreate collection:@"com.example.note"]);

  scope = [scope scopeByResolvingSelfAuthorityForDID:@"did:example:authority"];
  XCTAssertTrue([scope matchesSpace:space action:PDSSpaceActionCreate collection:@"com.example.note"]);
  XCTAssertFalse([scope matchesSpace:space action:PDSSpaceActionCreate collection:@"com.example.other"]);
  XCTAssertTrue([scope matchesSpace:space manageOperation:@"update"]);
  XCTAssertFalse([scope matchesSpace:space manageOperation:@"delete"]);
}

- (void)testRejectsUnknownDuplicateAndInvalidScopeParameters {
  NSArray<NSString *> *invalid = @[
    @"space:com.example.group?unknown=value",
    @"space:com.example.group?authority=*&authority=self",
    @"space:com.example.group?skey=",
    @"space:com.example.group?collection=short",
  ];
  for (NSString *value in invalid) {
    NSError *error = nil;
    XCTAssertNil([PDSSpaceScope scopeWithString:value error:&error], @"%@", value);
    XCTAssertNotNil(error, @"%@", value);
  }
}

- (PDSSpaceURI *)spaceURI {
  return [PDSSpaceURI
      URIWithString:@"at://did:example:authority/space/com.example.group/team%2Fone"
             error:nil];
}

@end
