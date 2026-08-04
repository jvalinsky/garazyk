// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/XrpcLexiconResolver.h"
#import "XrpcLexiconResolver+Testing.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Core/DID.h"

@interface XrpcLexiconResolverTests : XCTestCase
@property (nonatomic, strong) ATProtoServiceConfiguration *config;
@end

@implementation XrpcLexiconResolverTests

- (void)setUp {
    [super setUp];
    self.config = [[ATProtoServiceConfiguration alloc] init];
    [self.config setValue:@"localhost" forKey:@"serverHost"];
    [self.config setValue:@"/tmp" forKey:@"dataDirectory"];
    [self.config setValue:@"" forKey:@"appViewURL"];
}

#pragma mark - authorityDomainForNSID:

- (void)testAuthorityDomainForNSID_ThreePart_ReturnsAuthority {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"com.example.record" error:&error];
    XCTAssertEqualObjects(domain, @"example.com");
    XCTAssertNil(error);
}

- (void)testAuthorityDomainForNSID_FourPart_ReturnsAuthority {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"io.example.sub.record" error:&error];
    XCTAssertEqualObjects(domain, @"sub.example.io");
    XCTAssertNil(error);
}

- (void)testAuthorityDomainForNSID_FivePart_ReturnsAuthority {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"org.deep.nested.name.type" error:&error];
    XCTAssertEqualObjects(domain, @"name.nested.deep.org");
    XCTAssertNil(error);
}

- (void)testAuthorityDomainForNSID_TwoPart_ReturnsNilError {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"tld.name" error:&error];
    XCTAssertNil(domain);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testAuthorityDomainForNSID_SingleSegment_ReturnsNilError {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"single" error:&error];
    XCTAssertNil(domain);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testAuthorityDomainForNSID_Nil_ReturnsNilError {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:(NSString *)nil error:&error];
    XCTAssertNil(domain);
    XCTAssertNotNil(error);
}

- (void)testAuthorityDomainForNSID_Empty_ReturnsNilError {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"" error:&error];
    XCTAssertNil(domain);
    XCTAssertNotNil(error);
}

- (void)testAuthorityDomainForNSID_NullErrorPointer_Safe {
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"single" error:NULL];
    XCTAssertNil(domain);
}

#pragma mark - pdsEndpointFromDidDocument:

- (void)testPdsEndpointFromDidDocument_Valid_ReturnsEndpoint {
    NSArray *services = @[
        @{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://pds.example.com"}
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertEqualObjects(endpoint, @"https://pds.example.com");
    XCTAssertNil(error);
}

- (void)testPdsEndpointFromDidDocument_FirstMatch_ReturnsFirstEndpoint {
    NSArray *services = @[
        @{@"id": @"#other", @"type": @"SomeOtherType", @"serviceEndpoint": @"https://other.example.com"},
        @{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://pds.example.com"},
        @{@"id": @"#second_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://second.example.com"},
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertEqualObjects(endpoint, @"https://pds.example.com");
    XCTAssertNil(error);
}

- (void)testPdsEndpointFromDidDocument_NonPdsServices_ReturnsNilError {
    NSArray *services = @[
        @{@"id": @"#atproto_labeler", @"type": @"AtprotoLabeler", @"serviceEndpoint": @"https://label.example.com"}
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 500);
}

- (void)testPdsEndpointFromDidDocument_NoServices_ReturnsNilError {
    DIDDocument *doc = [self documentWithServices:@[]];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
    XCTAssertNotNil(error);
}

- (void)testPdsEndpointFromDidDocument_EmptyServices_ReturnsNilError {
    // DID document with empty services array — no PDS endpoint to extract.
    DIDDocument *doc = [self documentWithServices:@[]];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
    XCTAssertNotNil(error);
}

- (void)testPdsEndpointFromDidDocument_MissingEndpointField_ReturnsNilError {
    NSArray *services = @[
        @{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer"}
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
}

- (void)testPdsEndpointFromDidDocument_EmptyEndpoint_ReturnsNilError {
    NSArray *services = @[
        @{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @""}
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
}

- (void)testPdsEndpointFromDidDocument_NullErrorPointer_Safe {
    NSArray *services = @[
        @{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://pds.example.com"}
    ];
    DIDDocument *doc = [self documentWithServices:services];
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:NULL];
    XCTAssertEqualObjects(endpoint, @"https://pds.example.com");
}

#pragma mark - buildResolveResponseWithSchema:

- (void)testBuildResolveResponse_ValidSchema_ReturnsResponse {
    NSDictionary *schema = @{@"id": @"com.example.record", @"type": @"record"};
    NSError *error = nil;
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:schema nsid:@"com.example.record" configuration:self.config error:&error];
    XCTAssertNotNil(response);
    XCTAssertNotNil(response[@"uri"]);
    XCTAssertTrue([response[@"uri"] hasPrefix:@"at://"]);
    XCTAssertNotNil(response[@"cid"]);
    XCTAssertEqualObjects(response[@"schema"], schema);
    XCTAssertEqualObjects(response[@"lexiconDoc"], schema);
    XCTAssertEqualObjects(response[@"proxied"], @NO);
    XCTAssertNil(error);
}

- (void)testBuildResolveResponse_AppBskyNSID_SetsProxiedTrue {
    [self.config setValue:@"https://appview.example.com" forKey:@"appViewURL"];
    NSDictionary *schema = @{@"id": @"app.bsky.feed.post", @"type": @"record"};
    NSError *error = nil;
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:schema nsid:@"app.bsky.feed.post" configuration:self.config error:&error];
    XCTAssertEqualObjects(response[@"proxied"], @YES);
}

- (void)testBuildResolveResponse_NilSchema_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:nil nsid:@"com.example.record" configuration:self.config error:&error];
    XCTAssertNil(response);
    XCTAssertNotNil(error);
}

- (void)testBuildResolveResponse_NonDictionarySchema_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:(NSDictionary *)@[] nsid:@"com.example.record" configuration:self.config error:&error];
    XCTAssertNil(response);
    XCTAssertNotNil(error);
}

#pragma mark - lexiconRecordURLForEndpoint:

- (void)testLexiconRecordURL_ValidEndpoint_ReturnsURL {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNotNil(url);
    XCTAssertNil(error);
    NSString *urlStr = url.absoluteString;
    XCTAssertTrue([urlStr containsString:@"repo=did:plc:abc"] || [urlStr containsString:@"repo=did%3Aplc%3Aabc"]);
    XCTAssertTrue([urlStr containsString:@"collection=com.atproto.lexicon.schema"]);
    XCTAssertTrue([urlStr containsString:@"rkey=com.example.record"]);
    XCTAssertTrue([urlStr containsString:@"/xrpc/com.atproto.repo.getRecord"]);
}

- (void)testLexiconRecordURL_HttpScheme_ReturnsURL {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"http://internal:2582" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNotNil(url);
    XCTAssertNil(error);
}

- (void)testLexiconRecordURL_EndpointWithPath_AppendsXrpcSuffix {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com/base" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNotNil(url);
    NSString *urlStr = url.absoluteString;
    XCTAssertTrue([urlStr containsString:@"/base/xrpc/com.atproto.repo.getRecord"]);
}

- (void)testLexiconRecordURL_EndpointWithTrailingSlash_AppendsXrpcSuffix {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com/base/" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNotNil(url);
    NSString *urlStr = url.absoluteString;
    XCTAssertTrue([urlStr containsString:@"/base/xrpc/com.atproto.repo.getRecord"]);
}

- (void)testLexiconRecordURL_InvalidEndpoint_ReturnsNilError {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"not-a-url" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNil(url);
    XCTAssertNotNil(error);
}

- (void)testLexiconRecordURL_NilEndpoint_ThrowsException {
    // lexiconRecordURLForEndpoint: is annotated nonnull — passing nil is
    // undefined behavior. Verify the method rejects it gracefully.
#if defined(__APPLE__)
    BOOL raisedExpectedException = NO;
    @try {
        [XrpcLexiconResolver lexiconRecordURLForEndpoint:(NSString *)nil
                                                     did:@"did:plc:abc"
                                                    nsid:@"com.example.record"
                                                   error:nil];
    } @catch (NSException *exception) {
        raisedExpectedException = [exception isKindOfClass:[NSException class]] &&
            [exception.name isEqualToString:NSInvalidArgumentException];
    }
    XCTAssertTrue(raisedExpectedException);
#else
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:(NSString *)nil
                                                              did:@"did:plc:abc"
                                                             nsid:@"com.example.record"
                                                            error:&error];
    // GNUstep does not emit Apple's nonnull exception; the portable contract
    // is a nil URL plus an error for an invalid endpoint.
    XCTAssertNil(url);
    XCTAssertNotNil(error);
#endif
}

- (void)testLexiconRecordURL_NilDid_ReturnsURL {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com" did:nil nsid:@"com.example.record" error:&error];
    // nil did is passed through — should produce a URL with nil repo param
    XCTAssertNotNil(url);
}

- (void)testLexiconRecordURL_NullErrorPointer_Safe {
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"not-a-url" did:@"did:plc:abc" nsid:@"com.example.record" error:NULL];
    XCTAssertNil(url);
}

#pragma mark - Additional expansion tests

- (void)testAuthorityDomainForNSID_DashInName_ReturnsAuthority {
    NSError *error = nil;
    NSString *domain = [XrpcLexiconResolver authorityDomainForNSID:@"com.my-service.record" error:&error];
    XCTAssertEqualObjects(domain, @"my-service.com");
    XCTAssertNil(error);
}

- (void)testPdsEndpointFromDidDocument_NonArrayServices_ReturnsNilError {
    // When service is a dictionary instead of an array (malformed document)
    DIDDocument *doc = [[DIDDocument alloc] init];
    [doc setValue:@{@"id": @"#atproto_pds", @"type": @"AtprotoPersonalDataServer", @"serviceEndpoint": @"https://pds.example.com"} forKey:@"service"];
    NSError *error = nil;
    NSString *endpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:doc error:&error];
    XCTAssertNil(endpoint);
    XCTAssertNotNil(error);
}

- (void)testBuildResolveResponse_EmptyNsid_ReturnsResponse {
    NSDictionary *schema = @{@"id": @"", @"type": @"record"};
    NSError *error = nil;
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:schema nsid:@"" configuration:self.config error:&error];
    XCTAssertNotNil(response);
    XCTAssertNil(error);
}

- (void)testBuildResolveResponse_NullErrorPointer_Safe {
    NSDictionary *schema = @{@"id": @"com.example.record", @"type": @"record"};
    NSDictionary *response = [XrpcLexiconResolver buildResolveResponseWithSchema:schema nsid:@"com.example.record" configuration:self.config error:NULL];
    XCTAssertNotNil(response);
}

- (void)testLexiconRecordURL_UnsupportedScheme_ReturnsNilError {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"ftp://pds.example.com" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNil(url);
    XCTAssertNotNil(error);
}

- (void)testLexiconRecordURL_EndpointWithOnlySlash_AppendsXrpc {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com/" did:@"did:plc:abc" nsid:@"com.example.record" error:&error];
    XCTAssertNotNil(url);
    NSString *urlStr = url.absoluteString;
    XCTAssertTrue([urlStr containsString:@"/xrpc/com.atproto.repo.getRecord"]);
}

- (void)testLexiconRecordURL_NilNsid_ReturnsURL {
    NSError *error = nil;
    NSURL *url = [XrpcLexiconResolver lexiconRecordURLForEndpoint:@"https://pds.example.com" did:@"did:plc:abc" nsid:nil error:&error];
    XCTAssertNotNil(url);
}

- (void)testLoadLexiconJSON_NotFound_ReturnsNilError {
    NSString *tempDir = NSTemporaryDirectory();
    NSError *error = nil;
    NSDictionary *schema = [XrpcLexiconResolver loadLexiconJSONForNSID:@"com.nonexistent.test"
                                                         dataDirectory:tempDir
                                                                 error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 404);
}

#pragma mark - Helpers

- (DIDDocument *)documentWithServices:(NSArray *)services {
    DIDDocument *doc = [[DIDDocument alloc] init];
    // DIDDocument expects service entries in a specific format
    // Use KVC to set the service property
    [doc setValue:services forKey:@"service"];
    return doc;
}

@end
