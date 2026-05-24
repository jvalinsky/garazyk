// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/DID.h"

@interface ATProtoDIDDocumentFieldsTests : XCTestCase
@end

@implementation ATProtoDIDDocumentFieldsTests

- (DIDDocument *)documentWithJSON:(NSDictionary *)json {
    NSError *error = nil;
    DIDDocument *document = [DIDDocument documentWithJSON:json error:&error];
    XCTAssertNotNil(document, @"DID document should parse: %@", error);
    return document;
}

- (void)testModernVerificationMethodPrefersAtprotoKey {
    DIDDocument *document = [self documentWithJSON:@{
        @"id": @"did:plc:alice",
        @"alsoKnownAs": @[@"at://Alice.Example/"],
        @"service": @[
            @{@"id": @"#pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://pds.example"}
        ],
        @"verificationMethod": @[
            @{@"id": @"did:plc:alice#other", @"publicKeyMultibase": @"zFallback"},
            @{@"id": @"did:plc:alice#atproto", @"publicKeyMultibase": @"zAtproto"}
        ]
    }];

    XCTAssertEqualObjects([ATProtoDIDDocumentFields normalizedHandleFromDocument:document], @"alice.example");
    XCTAssertEqualObjects([ATProtoDIDDocumentFields pdsEndpointFromDocument:document], @"https://pds.example");
    XCTAssertEqualObjects([ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:document], @"zAtproto");
}

- (void)testModernVerificationMethodFallsBackToFirstKey {
    DIDDocument *document = [self documentWithJSON:@{
        @"id": @"did:plc:alice",
        @"verificationMethod": @[
            @{@"id": @"did:plc:alice#other", @"publicKeyMultibase": @"zFallback"}
        ]
    }];

    XCTAssertEqualObjects([ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:document], @"zFallback");
}

- (void)testLegacyVerificationMethodsDictionarySupportsAtprotoString {
    DIDDocument *document = [self documentWithJSON:@{
        @"id": @"did:plc:alice",
        @"verificationMethods": @{@"atproto": @"did:key:zLegacy"}
    }];

    XCTAssertEqualObjects([ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:document], @"did:key:zLegacy");
}

- (void)testLegacyVerificationMethodsDictionarySupportsNestedPublicKey {
    DIDDocument *document = [self documentWithJSON:@{
        @"id": @"did:plc:alice",
        @"verificationMethods": @{@"did:plc:alice#atproto": @{@"publicKeyMultibase": @"zNested"}}
    }];

    XCTAssertEqualObjects([ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:document], @"zNested");
}

- (void)testBadShapesReturnNil {
    DIDDocument *document = [self documentWithJSON:@{
        @"id": @"did:plc:alice",
        @"alsoKnownAs": @[@42],
        @"service": @[@{@"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @42}],
        @"verificationMethod": @[@{@"id": @"did:plc:alice#atproto", @"publicKeyMultibase": @42}],
        @"verificationMethods": @[@"bad"]
    }];

    XCTAssertNil([ATProtoDIDDocumentFields normalizedHandleFromDocument:document]);
    XCTAssertNil([ATProtoDIDDocumentFields pdsEndpointFromDocument:document]);
    XCTAssertNil([ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:document]);
}

@end
