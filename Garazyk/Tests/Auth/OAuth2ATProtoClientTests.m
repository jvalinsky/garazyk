// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"

/**
 * Bug Condition Exploration Test for ATProto OAuth Client Support
 * 
 * **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
 * 
 * This test explores the bug condition where ATProto clients (bsky.app, witchsky.app)
 * cannot authenticate because they are not pre-registered in the oauth_clients database.
 * 
 * **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists.
 * 
 * The test encodes the EXPECTED BEHAVIOR (authorization should succeed with client_metadata).
 * When run on UNFIXED code, it will fail with "unauthorized_client" error, proving the bug.
 * After the fix is implemented, this same test will pass, validating the fix.
 */
@interface OAuth2ATProtoClientTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, copy) NSString *databasePath;
@end

@implementation OAuth2ATProtoClientTests

- (void)setUp {
    [super setUp];
    
    NSString *filename = [NSString stringWithFormat:@"oauth2-atproto-client-tests-%@.sqlite", [[NSUUID UUID] UUIDString]];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSURL *databaseURL = [NSURL fileURLWithPath:self.databasePath];
    self.database = [PDSDatabase databaseAtURL:databaseURL];
    XCTAssertTrue([self.database openWithError:nil], @"Database should open");
    
    // NOTE: We intentionally DO NOT register bsky.app or witchsky.app in the database
    // This is the bug condition - ATProto clients should work without pre-registration
    
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

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    });
    return [formatter stringFromDate:date];
}

- (HttpResponse *)authorizeViaPARWithParameters:(NSDictionary *)authorizeParams
                                       clientID:(NSString *)clientID {
    NSError *error = nil;
    BOOL created = [self.database executeParameterizedUpdate:
                    @"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT PRIMARY KEY, client_id TEXT NOT NULL, params_json TEXT NOT NULL, expires_at TEXT NOT NULL, consumed_at TEXT)"
                                                         params:@[]
                                                          error:&error];
    XCTAssertTrue(created, @"Failed to create PAR table: %@", error);

    NSData *paramsData = [NSJSONSerialization dataWithJSONObject:authorizeParams options:0 error:&error];
    XCTAssertNotNil(paramsData, @"Failed to serialize authorize params: %@", error);

    NSString *requestURI = [NSString stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@", [[NSUUID UUID] UUIDString]];
    NSString *expiresAt = [self iso8601StringFromDate:[NSDate dateWithTimeIntervalSinceNow:600]];
    NSString *paramsJSON = [[NSString alloc] initWithData:paramsData encoding:NSUTF8StringEncoding];
    BOOL inserted = [self.database executeParameterizedUpdate:
                     @"INSERT INTO oauth_par_requests (request_uri, client_id, params_json, expires_at, consumed_at) VALUES (?, ?, ?, ?, NULL)"
                                                          params:@[requestURI, clientID ?: @"", paramsJSON ?: @"{}", expiresAt]
                                                           error:&error];
    XCTAssertTrue(inserted, @"Failed to insert PAR row: %@", error);

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/authorize"
                                                   queryString:@""
                                                   queryParams:@{
                                                       @"request_uri": requestURI,
                                                       @"client_id": clientID ?: @""
                                                   }
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.handler handleAuthorizeRequest:request response:response];
    return response;
}

/**
 * Test Case 1: bsky.app authorization with client_metadata
 * 
 * **Bug Condition**: client_id=https://bsky.app is NOT in database
 * **Expected Behavior**: Authorization succeeds using client_metadata
 * **Unfixed Behavior**: Returns "unauthorized_client" error
 */
- (void)testBskyAppAuthorizationWithClientMetadata {
    NSString *clientID = @"https://bsky.app";
    NSString *redirectURI = @"https://bsky.app/oauth/callback";
    
    // Construct client_metadata as JSON string (as it would be sent in query params)
    NSDictionary *clientMetadata = @{
        @"client_id": clientID,
        @"client_name": @"Bluesky",
        @"redirect_uris": @[redirectURI],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none"
    };
    NSData *metadataJSON = [NSJSONSerialization dataWithJSONObject:clientMetadata options:0 error:nil];
    NSString *metadataString = [[NSString alloc] initWithData:metadataJSON encoding:NSUTF8StringEncoding];
    
    // Create authorization request with client_metadata
    NSMutableDictionary *queryParams = [@{
        @"client_id": clientID,
        @"redirect_uri": redirectURI,
        @"response_type": @"code",
        @"state": @"test-state-bsky",
        @"code_challenge": @"test_challenge_bsky",
        @"code_challenge_method": @"S256",
        @"scope": @"atproto",
        @"client_metadata": metadataString
    } mutableCopy];
    
    HttpResponse *response = [self authorizeViaPARWithParameters:queryParams clientID:clientID];
    
    // EXPECTED BEHAVIOR: Authorization should succeed (serve consent page)
    // UNFIXED BEHAVIOR: Returns 400 with "unauthorized_client" error
    XCTAssertNotEqual(response.statusCode, 400, 
                     @"Authorization should NOT fail with 400 for bsky.app with valid client_metadata");
    XCTAssertNil(response.jsonBody[@"error"], 
                @"Should NOT return 'unauthorized_client' error for bsky.app with valid client_metadata");
    
    // Expected: Should serve consent page (200) or redirect (302)
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Should serve consent page (200) or redirect (302) for valid ATProto client");
}

/**
 * Test Case 2: witchsky.app authorization with client_metadata
 * 
 * **Bug Condition**: client_id=https://witchsky.app is NOT in database
 * **Expected Behavior**: Authorization succeeds using client_metadata
 * **Unfixed Behavior**: Returns "unauthorized_client" error
 */
- (void)testWitchskyAppAuthorizationWithClientMetadata {
    NSString *clientID = @"https://witchsky.app";
    NSString *redirectURI = @"https://witchsky.app/oauth/callback";
    
    NSDictionary *clientMetadata = @{
        @"client_id": clientID,
        @"client_name": @"Witchsky",
        @"redirect_uris": @[redirectURI],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none"
    };
    NSData *metadataJSON = [NSJSONSerialization dataWithJSONObject:clientMetadata options:0 error:nil];
    NSString *metadataString = [[NSString alloc] initWithData:metadataJSON encoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *queryParams = [@{
        @"client_id": clientID,
        @"redirect_uri": redirectURI,
        @"response_type": @"code",
        @"state": @"test-state-witchsky",
        @"code_challenge": @"test_challenge_witchsky",
        @"code_challenge_method": @"S256",
        @"scope": @"atproto",
        @"client_metadata": metadataString
    } mutableCopy];
    
    HttpResponse *response = [self authorizeViaPARWithParameters:queryParams clientID:clientID];
    
    // EXPECTED BEHAVIOR: Authorization should succeed
    XCTAssertNotEqual(response.statusCode, 400,
                     @"Authorization should NOT fail with 400 for witchsky.app with valid client_metadata");
    XCTAssertNil(response.jsonBody[@"error"],
                @"Should NOT return 'unauthorized_client' error for witchsky.app with valid client_metadata");
    
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Should serve consent page (200) or redirect (302) for valid ATProto client");
}

/**
 * Test Case 3: Native app with IPv4 loopback redirect
 * 
 * **Bug Condition**: redirect_uri=http://127.0.0.1:8080/callback (HTTP loopback)
 * **Expected Behavior**: Loopback redirect allowed per RFC 8252
 * **Unfixed Behavior**: Returns "Invalid redirect_uri" error
 */
- (void)testNativeAppWithIPv4LoopbackRedirect {
    NSString *clientID = @"https://example.com/native-app";
    NSString *redirectURI = @"http://127.0.0.1:8080/callback";
    
    NSDictionary *clientMetadata = @{
        @"client_id": clientID,
        @"client_name": @"Native App",
        @"redirect_uris": @[redirectURI],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"native"
    };
    NSData *metadataJSON = [NSJSONSerialization dataWithJSONObject:clientMetadata options:0 error:nil];
    NSString *metadataString = [[NSString alloc] initWithData:metadataJSON encoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *queryParams = [@{
        @"client_id": clientID,
        @"redirect_uri": redirectURI,
        @"response_type": @"code",
        @"state": @"test-state-native",
        @"code_challenge": @"test_challenge_native",
        @"code_challenge_method": @"S256",
        @"scope": @"atproto",
        @"client_metadata": metadataString
    } mutableCopy];
    
    HttpResponse *response = [self authorizeViaPARWithParameters:queryParams clientID:clientID];
    
    // EXPECTED BEHAVIOR: Loopback redirect should be allowed
    XCTAssertNotEqual(response.statusCode, 400,
                     @"Authorization should NOT fail with 400 for loopback redirect");
    XCTAssertNil(response.jsonBody[@"error"],
                @"Should NOT return 'Invalid redirect_uri' error for loopback redirect per RFC 8252");
    
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Should serve consent page (200) or redirect (302) for valid loopback redirect");
}

/**
 * Test Case 4: Native app with IPv6 loopback redirect
 * 
 * **Bug Condition**: redirect_uri=http://[::1]:3000/callback (IPv6 loopback)
 * **Expected Behavior**: IPv6 loopback redirect allowed per RFC 8252
 * **Unfixed Behavior**: Returns "Invalid redirect_uri" error
 */
- (void)testNativeAppWithIPv6LoopbackRedirect {
    NSString *clientID = @"https://example.com/native-app-v6";
    NSString *redirectURI = @"http://[::1]:3000/callback";
    
    NSDictionary *clientMetadata = @{
        @"client_id": clientID,
        @"client_name": @"Native App IPv6",
        @"redirect_uris": @[redirectURI],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto",
        @"dpop_bound_access_tokens": @YES,
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"native"
    };
    NSData *metadataJSON = [NSJSONSerialization dataWithJSONObject:clientMetadata options:0 error:nil];
    NSString *metadataString = [[NSString alloc] initWithData:metadataJSON encoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *queryParams = [@{
        @"client_id": clientID,
        @"redirect_uri": redirectURI,
        @"response_type": @"code",
        @"state": @"test-state-native-v6",
        @"code_challenge": @"test_challenge_native_v6",
        @"code_challenge_method": @"S256",
        @"scope": @"atproto",
        @"client_metadata": metadataString
    } mutableCopy];
    
    HttpResponse *response = [self authorizeViaPARWithParameters:queryParams clientID:clientID];
    
    // EXPECTED BEHAVIOR: IPv6 loopback redirect should be allowed
    XCTAssertNotEqual(response.statusCode, 400,
                     @"Authorization should NOT fail with 400 for IPv6 loopback redirect");
    XCTAssertNil(response.jsonBody[@"error"],
                @"Should NOT return 'Invalid redirect_uri' error for IPv6 loopback redirect per RFC 8252");
    
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 302,
                 @"Should serve consent page (200) or redirect (302) for valid IPv6 loopback redirect");
}

@end
