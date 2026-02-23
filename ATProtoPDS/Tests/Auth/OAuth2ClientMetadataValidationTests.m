#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2Handler+Testing.h"
#import "Database/PDSDatabase.h"

/**
 * Unit tests for OAuth2Handler validateClientMetadata:error: method
 * 
 * **Validates: Requirements 2.2, 2.3**
 * 
 * These tests verify that the validateClientMetadata method correctly validates
 * ATProto client metadata according to the ATProto OAuth specification.
 */
@interface OAuth2ClientMetadataValidationTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, copy) NSString *databasePath;
@end

@implementation OAuth2ClientMetadataValidationTests

- (void)setUp {
    [super setUp];
    
    NSString *filename = [NSString stringWithFormat:@"oauth2-metadata-validation-tests-%@.sqlite", [[NSUUID UUID] UUIDString]];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSURL *databaseURL = [NSURL fileURLWithPath:self.databasePath];
    self.database = [PDSDatabase databaseAtURL:databaseURL];
    XCTAssertTrue([self.database openWithError:nil], @"Database should open");
    
    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.handler = nil;
    if (self.databasePath.length > 0) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:self.databasePath error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-wal"] error:nil];
        [fileManager removeItemAtPath:[self.databasePath stringByAppendingString:@"-shm"] error:nil];
        self.databasePath = nil;
    }
    [super tearDown];
}

/**
 * Test: Valid client metadata with all required fields
 */
- (void)testValidClientMetadataWithAllFields {
    NSDictionary *metadata = @{
        @"client_id": @"https://bsky.app",
        @"client_name": @"Bluesky",
        @"redirect_uris": @[@"https://bsky.app/oauth/callback"],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"scope": @"atproto"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNotNil(result, @"Should return normalized client dictionary");
    XCTAssertNil(error, @"Should not return error for valid metadata");
    XCTAssertEqualObjects(result[@"client_id"], @"https://bsky.app");
    XCTAssertEqualObjects(result[@"client_name"], @"Bluesky");
    XCTAssertEqualObjects(result[@"redirect_uris"], @[@"https://bsky.app/oauth/callback"]);
    XCTAssertEqualObjects(result[@"grant_types"], @"authorization_code refresh_token");
    XCTAssertEqualObjects(result[@"scope"], @"atproto");
}

/**
 * Test: Valid client metadata with minimal required fields
 */
- (void)testValidClientMetadataWithMinimalFields {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[@"https://example.com/callback"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNotNil(result, @"Should return normalized client dictionary");
    XCTAssertNil(error, @"Should not return error for valid minimal metadata");
    XCTAssertEqualObjects(result[@"client_id"], @"https://example.com");
    XCTAssertEqualObjects(result[@"client_name"], @"https://example.com", @"Should default client_name to client_id");
    XCTAssertEqualObjects(result[@"grant_types"], @"authorization_code refresh_token", @"Should default grant_types");
    XCTAssertEqualObjects(result[@"scope"], @"atproto", @"Should default scope to atproto");
}

/**
 * Test: Missing client_id
 */
- (void)testMissingClientID {
    NSDictionary *metadata = @{
        @"redirect_uris": @[@"https://example.com/callback"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for missing client_id");
    XCTAssertNotNil(error, @"Should return error for missing client_id");
    XCTAssertTrue([error.localizedDescription containsString:@"client_id"], @"Error should mention client_id");
}

/**
 * Test: client_id is not HTTPS URL
 */
- (void)testClientIDNotHTTPS {
    NSDictionary *metadata = @{
        @"client_id": @"http://example.com",
        @"redirect_uris": @[@"https://example.com/callback"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for non-HTTPS client_id");
    XCTAssertNotNil(error, @"Should return error for non-HTTPS client_id");
    XCTAssertTrue([error.localizedDescription containsString:@"HTTPS"], @"Error should mention HTTPS requirement");
}

/**
 * Test: client_id is invalid URL
 */
- (void)testClientIDInvalidURL {
    NSDictionary *metadata = @{
        @"client_id": @"not-a-url",
        @"redirect_uris": @[@"https://example.com/callback"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for invalid client_id URL");
    XCTAssertNotNil(error, @"Should return error for invalid client_id URL");
}

/**
 * Test: Missing redirect_uris
 */
- (void)testMissingRedirectURIs {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for missing redirect_uris");
    XCTAssertNotNil(error, @"Should return error for missing redirect_uris");
    XCTAssertTrue([error.localizedDescription containsString:@"redirect_uris"], @"Error should mention redirect_uris");
}

/**
 * Test: Empty redirect_uris array
 */
- (void)testEmptyRedirectURIsArray {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for empty redirect_uris array");
    XCTAssertNotNil(error, @"Should return error for empty redirect_uris array");
    XCTAssertTrue([error.localizedDescription containsString:@"at least one"], @"Error should mention array must contain at least one URI");
}

/**
 * Test: redirect_uris contains invalid URI
 */
- (void)testInvalidRedirectURI {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[@"not-a-valid-uri"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNil(result, @"Should return nil for invalid redirect_uri");
    XCTAssertNotNil(error, @"Should return error for invalid redirect_uri");
    XCTAssertTrue([error.localizedDescription containsString:@"Invalid redirect_uri"], @"Error should mention invalid redirect_uri");
}

/**
 * Test: Multiple valid redirect_uris
 */
- (void)testMultipleValidRedirectURIs {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[
            @"https://example.com/callback",
            @"https://example.com/oauth/callback",
            @"http://127.0.0.1:8080/callback"
        ]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNotNil(result, @"Should return normalized client dictionary");
    XCTAssertNil(error, @"Should not return error for multiple valid redirect_uris");
    NSArray *redirectURIs = result[@"redirect_uris"];
    XCTAssertEqual(redirectURIs.count, 3, @"Should preserve all redirect_uris");
}

/**
 * Test: grant_types as array
 */
- (void)testGrantTypesAsArray {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @[@"authorization_code", @"refresh_token"]
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNotNil(result, @"Should return normalized client dictionary");
    XCTAssertNil(error, @"Should not return error for grant_types array");
    XCTAssertEqualObjects(result[@"grant_types"], @"authorization_code refresh_token", @"Should convert array to space-separated string");
}

/**
 * Test: grant_types as string
 */
- (void)testGrantTypesAsString {
    NSDictionary *metadata = @{
        @"client_id": @"https://example.com",
        @"redirect_uris": @[@"https://example.com/callback"],
        @"grant_types": @"authorization_code refresh_token"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:metadata error:&error];
    
    XCTAssertNotNil(result, @"Should return normalized client dictionary");
    XCTAssertNil(error, @"Should not return error for grant_types string");
    XCTAssertEqualObjects(result[@"grant_types"], @"authorization_code refresh_token");
}

/**
 * Test: Null metadata
 */
- (void)testNullMetadata {
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:nil error:&error];
    
    XCTAssertNil(result, @"Should return nil for null metadata");
    XCTAssertNotNil(error, @"Should return error for null metadata");
}

/**
 * Test: Invalid metadata type (not a dictionary)
 */
- (void)testInvalidMetadataType {
    NSError *error = nil;
    NSDictionary *result = [self.handler validateClientMetadata:(NSDictionary *)@"not-a-dictionary" error:&error];
    
    XCTAssertNil(result, @"Should return nil for invalid metadata type");
    XCTAssertNotNil(error, @"Should return error for invalid metadata type");
}

@end
