#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/JWT.h"
#import "Auth/DPoPUtil.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

@interface OAuthConformanceTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, assign) SecKeyRef privateKey;
@property (nonatomic, assign) SecKeyRef publicKey;
@end

@implementation OAuthConformanceTests

- (void)setUp {
    [super setUp];
    
    // Setup in-memory DB
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@":memory:"]];
    [self.database openWithError:nil];
    
    // Setup Minter with static key for testing
    self.minter = [[JWTMinter alloc] init];
    
    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    self.handler.minter = self.minter;
    
    // Generate P-256 key pair for DPoP
    NSDictionary* attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeySizeInBits: @256
    };
    CFErrorRef error = NULL;
    self.privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
    if (self.privateKey) {
        self.publicKey = SecKeyCopyPublicKey(self.privateKey);
    }
    
    // Ensure the tables exist
    [self.database executeRawSQL:@"CREATE TABLE IF NOT EXISTS oauth_clients (client_id TEXT PRIMARY KEY, client_name TEXT, client_secret TEXT, redirect_uris TEXT, grant_types TEXT, response_types TEXT, scope TEXT, application_type TEXT)" error:nil];
    [self.database executeRawSQL:@"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT PRIMARY KEY, client_id TEXT NOT NULL, params_json TEXT NOT NULL, expires_at TEXT NOT NULL, consumed_at TEXT)" error:nil];
}

- (void)tearDown {
    if (self.privateKey) CFRelease(self.privateKey);
    if (self.publicKey) CFRelease(self.publicKey);
    [self.database close];
    [super tearDown];
}

- (void)testJWKSResponse {
    NSData *emptyBody = [NSData data];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/jwks"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:emptyBody
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // We need to invoke the handler logic. 
    // Since handleJWKS is private, we can't call it directly easily without exposing it.
    // However, we can register routes to a mock server or just use performSelector if we want unit test.
    // Or we can simple expose it in a category in the test file.
    
    // Better: integration test style, but we don't have full server running here easily.
    // Let's declare the private method here to access it.
    [self.handler performSelector:@selector(handleJWKS:response:) withObject:request withObject:response];
    
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.body);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(json[@"keys"]);
    XCTAssertTrue([json[@"keys"] isKindOfClass:[NSArray class]]);
    
    // Verify headers
    XCTAssertEqualObjects(response.headers[@"Access-Control-Allow-Origin"], @"*");
}

- (void)testPARResponse {
    // Skip if key generation failed
    if (!self.privateKey) {
        XCTSkip(@"Skipping PAR test: Security key generation unavailable");
        return;
    }
    
    // 1. Setup client
    [self.database createClient:@{@"client_id": @"test_client", @"client_secret": @"secret", @"redirect_uris": @[@"https://client.example.com/cb"]} error:nil];
    
    // 2. Generate DPoP proof for PAR endpoint
    NSError *dpopError = nil;
    DPoPToken *dpopToken = [DPoPUtil createDPoPForMethod:@"POST" uri:@"http://localhost/oauth/par" nonce:nil key:self.privateKey error:&dpopError];
    XCTAssertNotNil(dpopToken, @"DPoP token creation failed: %@", dpopError);
    
    // 3. Prepare PAR request
    NSString *codeVerifier = @"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    NSData *verifierData = [codeVerifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char challengeHash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, challengeHash);
    NSData *challengeData = [NSData dataWithBytes:challengeHash length:CC_SHA256_DIGEST_LENGTH];
    NSString *codeChallenge = [challengeData base64EncodedStringWithOptions:0];
    codeChallenge = [codeChallenge stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    codeChallenge = [codeChallenge stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    codeChallenge = [codeChallenge stringByReplacingOccurrencesOfString:@"=" withString:@""];

    NSDictionary *params = @{
        @"client_id": @"test_client",
        @"client_secret": @"secret",
        @"response_type": @"code",
        @"redirect_uri": @"https://client.example.com/cb",
        @"scope": @"atproto",
        @"state": @"xyz",
        @"code_challenge": codeChallenge,
        @"code_challenge_method": @"S256"
    };
    
    NSMutableString *body = [NSMutableString string];
    for (NSString *key in params) {
        if (body.length > 0) [body appendString:@"&"];
        [body appendFormat:@"%@=%@", key, params[key]];
    }
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/par"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{
        @"Content-Type": @"application/x-www-form-urlencoded",
        @"DPoP": dpopToken.jwt ?: @"",
        @"Host": @"localhost"
    }
                                                          body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Call handlePARRequest
    [self.handler performSelector:@selector(handlePARRequest:response:) withObject:request withObject:response];
    
    // Handle DPoP Nonce Challenge
    if (response.statusCode == 400 && [response.headers[@"DPoP-Nonce"] length] > 0) {
        NSString *nonce = response.headers[@"DPoP-Nonce"];
        dpopToken = [DPoPUtil createDPoPForMethod:@"POST" uri:@"http://localhost/oauth/par" nonce:nonce key:self.privateKey error:&dpopError];
        XCTAssertNotNil(dpopToken);
        
        request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                      methodString:@"POST"
                                              path:@"/oauth/par"
                                       queryString:@""
                                       queryParams:@{}
                                           version:@"HTTP/1.1"
                                           headers:@{
            @"Content-Type": @"application/x-www-form-urlencoded",
            @"DPoP": dpopToken.jwt ?: @"",
            @"Host": @"localhost"
        }
                                              body:bodyData
                                     remoteAddress:@"127.0.0.1"];
        response = [[HttpResponse alloc] init];
        [self.handler performSelector:@selector(handlePARRequest:response:) withObject:request withObject:response];
    }
    
    XCTAssertEqual(response.statusCode, 201, @"Expected 201, got %d. Body: %@", response.statusCode, [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding]);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(json[@"request_uri"]);
    XCTAssertTrue([json[@"request_uri"] hasPrefix:@"urn:ietf:params:oauth:request_uri:"]);
    XCTAssertNotNil(json[@"expires_in"]);
    XCTAssertEqual([json[@"expires_in"] integerValue], 600);
    XCTAssertTrue([response.headers[@"DPoP-Nonce"] length] > 0);
    XCTAssertEqualObjects(response.headers[@"Cache-Control"], @"no-store");
    XCTAssertEqualObjects(response.headers[@"Pragma"], @"no-cache");
    
    // Verify it's in DB
    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT * FROM oauth_par_requests WHERE request_uri = ?" params:@[json[@"request_uri"]] error:nil];
    XCTAssertEqual(rows.count, 1);
}

@end
