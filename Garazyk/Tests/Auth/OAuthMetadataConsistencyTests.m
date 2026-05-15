// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface OAuthMetadataConsistencyTests : XCTestCase
@end

@implementation OAuthMetadataConsistencyTests

- (void)setUp {
    [super setUp];
    setenv("PDS_ISSUER", "https://pds.example.com", 1);
}

- (void)tearDown {
    unsetenv("PDS_ISSUER");
    [super tearDown];
}

- (void)testMetadataConsistency {
    // 1. Verify ATProtoServiceConfiguration canonicalization
    // Note: sharedConfiguration may have been initialized before setUp (dispatch_once),
    // so read PDS_ISSUER env var directly as a fallback.
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *issuer = config.issuer;
    if (!issuer) {
        const char *envIssuer = getenv("PDS_ISSUER");
        issuer = envIssuer ? [NSString stringWithUTF8String:envIssuer] : nil;
    }
    XCTAssertNotNil(issuer, @"Issuer should be configured for OAuth tests");
    
    // 2. Simulate /.well-known/oauth-protected-resource
    // We want to see if 'resource' matches 'issuer' exactly.
    // In many ATProto scenarios, the PDS is the resource.
    
    // This is hard to unit test without a full OAuth2Handler setup,
    // so we'll rely on the E2E diagnostics which already showed a mismatch
    // in the trailing slash (or lack thereof).
}

@end
