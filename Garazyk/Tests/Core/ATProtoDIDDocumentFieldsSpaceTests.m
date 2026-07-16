// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/DID.h"

@interface ATProtoDIDDocumentFieldsSpaceTests : XCTestCase
@end

@implementation ATProtoDIDDocumentFieldsSpaceTests

- (void)testPrefersExactSpaceKeyAndHostService {
  DIDDocument *document = [self documentWithJSON:@{
    @"verificationMethod" : @[
      @{ @"id" : @"did:example:authority#atproto", @"publicKeyMultibase" : @"znormal" },
      @{ @"id" : @"did:example:authority#atproto_space", @"publicKeyMultibase" : @"zspace" },
      @{ @"id" : @"did:example:authority#atproto_space_untrusted", @"publicKeyMultibase" : @"zwrong" },
    ],
    @"service" : @[
      @{ @"id" : @"#atproto_pds", @"serviceEndpoint" : @"https://pds.example" },
      @{ @"id" : @"did:example:authority#atproto_space_host", @"serviceEndpoint" : @"https://spaces.example" },
    ],
  }];
  XCTAssertEqualObjects([ATProtoDIDDocumentFields spaceSigningKeyMultibaseFromDocument:document], @"zspace");
  XCTAssertEqualObjects([ATProtoDIDDocumentFields spaceHostEndpointFromDocument:document], @"https://spaces.example");
}

- (void)testUsesOnlyDocumentedFallbacksAndRejectsUnsafeEndpoints {
  DIDDocument *fallback = [self documentWithJSON:@{
    @"verificationMethods" : @{ @"atproto" : @"znormal" },
    @"service" : @[ @{ @"id" : @"#atproto_pds", @"serviceEndpoint" : @"http://localhost:3000" } ],
  }];
  XCTAssertEqualObjects([ATProtoDIDDocumentFields spaceSigningKeyMultibaseFromDocument:fallback], @"znormal");
  XCTAssertEqualObjects([ATProtoDIDDocumentFields spaceHostEndpointFromDocument:fallback], @"http://localhost:3000");

  DIDDocument *invalid = [self documentWithJSON:@{
    @"verificationMethod" : @[ @{ @"id" : @"#atproto_space_extra", @"publicKeyMultibase" : @"zwrong" } ],
    @"service" : @[ @{ @"id" : @"#atproto_space_host_extra", @"serviceEndpoint" : @"https://wrong.example" },
                       @{ @"id" : @"#atproto_pds", @"serviceEndpoint" : @"https://user@pds.example" } ],
  }];
  XCTAssertNil([ATProtoDIDDocumentFields spaceSigningKeyMultibaseFromDocument:invalid]);
  XCTAssertNil([ATProtoDIDDocumentFields spaceHostEndpointFromDocument:invalid]);
}

- (DIDDocument *)documentWithJSON:(NSDictionary *)additional {
  NSMutableDictionary *json = [@{ @"id" : @"did:example:authority" } mutableCopy];
  [json addEntriesFromDictionary:additional];
  NSError *error = nil;
  DIDDocument *document = [DIDDocument documentWithJSON:json error:&error];
  XCTAssertNil(error);
  return document;
}

@end
