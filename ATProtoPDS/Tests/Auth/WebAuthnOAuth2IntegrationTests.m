#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/WebAuthnRegistrationHandler.h"
#import "Auth/WebAuthnVerifier.h"
#import "Auth/CryptoUtils.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface WebAuthnOAuth2IntegrationTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) OAuth2Server *oauthServer;
@property (nonatomic, strong) OAuth2Handler *oauthHandler;
@property (nonatomic, strong) WebAuthnRegistrationHandler *webauthnHandler;
@end

@implementation WebAuthnOAuth2IntegrationTests

- (void)setUp {
    [super setUp];
    
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    [self.db openWithError:nil];
    
    self.server = [HttpServer serverWithPort:0];
    
    self.oauthServer = [[OAuth2Server alloc] initWithDatabase:self.db];
    self.oauthServer.issuer = @"http://127.0.0.1:8443";
    
    self.oauthHandler = [[OAuth2Handler alloc] initWithDatabase:self.db];
    self.oauthHandler.oauthServer = self.oauthServer;
    [self.oauthHandler registerRoutesWithServer:self.server];
    
    self.webauthnHandler = [[WebAuthnRegistrationHandler alloc] initWithDatabase:self.db serverOrigin:@"http://127.0.0.1:8443"];
    [self.webauthnHandler registerRoutesWithServer:self.server];
    
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://127.0.0.1:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self.oauthHandler validateClient:testClient.clientID completion:^(NSDictionary *client, NSError *error) {
        if (!error) {
            [self.oauthHandler validateClient:testClient.clientID completion:^(NSDictionary *c, NSError *e) {}];
        }
    }];
}

- (void)tearDown {
    [super tearDown];
    [self.server stop];
    [self.db close];
}

#pragma mark - Helper Methods

- (NSDictionary *)createTestAccountWithDid:(NSString *)did handle:(NSString *)handle password:(NSString *)password {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.passwordHash = [password dataUsingEncoding:NSUTF8StringEncoding];
    account.passwordSalt = [NSData data];
    account.accessJwt = [@"jwt" dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [@"jwt" dataUsingEncoding:NSUTF8StringEncoding];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    account.tfaEnabled = NO;
    account.webauthnEnabled = NO;
    account.inviteEnabled = YES;
    
    NSError *error = nil;
    BOOL success = [self.db createAccount:account error:&error];
    XCTAssertTrue(success, @"Failed to create test account: %@", error);
    
    return @{@"did": did, @"handle": handle};
}

- (NSData *)base64URLDecode:(NSString *)string {
    NSString *base64 = string;
    base64 = [base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (base64.length % 4) {
        base64 = [base64 stringByAppendingString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

#pragma mark - Part 1: HTTP Endpoint Tests

- (void)testRegisterBeginReturnsChallenge {
    [self createTestAccountWithDid:@"did:TEST:testuser001" handle:@"testuser001" password:@"password"];
    
    HttpRequest *req = [HttpRequest request];
    [req setMethod:@"POST"];
    [req setPath:@"/auth/webauthn/register/begin"];
    [req setBody:[@"{\"did\":\"did:TEST:testuser001\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    
    HttpResponse *res = [HttpResponse response];
    
    [self.webauthnHandler handleRegisterBegin:req response:res];
    
    XCTAssertEqual(res.statusCode, 200);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:res.body options:0 error:nil];
    XCTAssertNotNil(body[@"challenge"]);
    XCTAssertNotNil(body[@"sessionId"]);
}

- (void)testRegisterBeginRequiresDid {
    HttpRequest *req = [HttpRequest request];
    [req setMethod:@"POST"];
    [req setPath:@"/auth/webauthn/register/begin"];
    [req setBody:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
    
    HttpResponse *res = [HttpResponse response];
    
    [self.webauthnHandler handleRegisterBegin:req response:res];
    
    XCTAssertEqual(res.statusCode, 400);
}

- (void)testRegisterBeginAccountNotFound {
    HttpRequest *req = [HttpRequest request];
    [req setMethod:@"POST"];
    [req setPath:@"/auth/webauthn/register/begin"];
    [req setBody:[@"{\"did\":\"did:TEST:nonexistent\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    
    HttpResponse *res = [HttpResponse response];
    
    [self.webauthnHandler handleRegisterBegin:req response:res];
    
    XCTAssertEqual(res.statusCode, 404);
}

- (void)testRegisterCompleteStoresCredential {
    [self createTestAccountWithDid:@"did:TEST:testuser002" handle:@"testuser002" password:@"password"];
    
    HttpRequest *beginReq = [HttpRequest request];
    [beginReq setMethod:@"POST"];
    [beginReq setPath:@"/auth/webauthn/register/begin"];
    [beginReq setBody:[@"{\"did\":\"did:TEST:testuser002\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    
    HttpResponse *beginRes = [HttpResponse response];
    [self.webauthnHandler handleRegisterBegin:beginReq response:beginRes];
    XCTAssertEqual(beginRes.statusCode, 200);
    
    NSMutableDictionary *beginBody = [NSJSONSerialization JSONObjectWithData:beginRes.body options:0 error:nil];
    NSString *sessionId = beginBody[@"sessionId"];
    
    NSMutableData *authData = [NSMutableData dataWithLength:37];
    uint8_t *bytes = authData.mutableBytes;
    memset(bytes, 0, 37);
    bytes[32] = 0x40;
    
    NSData *aaguid = [NSMutableData dataWithLength:16];
    NSData *credentialId = [@"testcred" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *fullAuthData = [NSMutableData dataWithData:authData];
    [fullAuthData appendData:aaguid];
    uint16_t credLen = CFSwapInt16HostToBig(4);
    [fullAuthData appendBytes:&credLen length:2];
    [fullAuthData appendData:credentialId];
    
    NSDictionary *attestation = @{
        @"clientDataJSON": [[NSJSONSerialization dataWithJSONObject:@{
            @"type": @"webauthn.create",
            @"challenge": beginBody[@"challenge"],
            @"origin": @"http://127.0.0.1:8443"
        } options:0 error:nil] base64EncodedStringWithOptions:0],
        @"attestationObject": [fullAuthData base64EncodedStringWithOptions:0]
    };
    
    NSDictionary *completeBody = @{
        @"sessionId": sessionId,
        @"credentialId": [credentialId base64EncodedStringWithOptions:0],
        @"attestation": attestation
    };
    
    HttpRequest *completeReq = [HttpRequest request];
    [completeReq setMethod:@"POST"];
    [completeReq setPath:@"/auth/webauthn/register/complete"];
    [completeReq setBody:[NSJSONSerialization dataWithJSONObject:completeBody options:0 error:nil]];
    
    HttpResponse *completeRes = [HttpResponse response];
    [self.webauthnHandler handleRegisterComplete:completeReq response:completeRes];
    
    XCTAssertEqual(completeRes.statusCode, 200);
    NSDictionary *resBody = [NSJSONSerialization JSONObjectWithData:completeRes.body options:0 error:nil];
    XCTAssertTrue([resBody[@"success"] boolValue]);
}

- (void)testAssertRejectsInvalidSessionId {
    HttpRequest *req = [HttpRequest request];
    [req setMethod:@"POST"];
    [req setPath:@"/auth/webauthn/assert"];
    [req setBody:[@"{\"sessionId\":\"invalid\",\"assertion\":{}}" dataUsingEncoding:NSUTF8StringEncoding]];
    
    HttpResponse *res = [HttpResponse response];
    [self.webauthnHandler handleAssert:req response:res];
    
    XCTAssertEqual(res.statusCode, 400);
}

#pragma mark - Part 2: OAuth2 Integration Tests

- (void)testWebauthnAuthorizationRequestGeneratesChallenge {
    OAuth2AuthorizationRequest *req = [[OAuth2AuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"http://127.0.0.1:3000/callback";
    req.responseType = @"code";
    req.webauthn = YES;
    
    [self.oauthServer handleAuthorizationRequest:req completion:^(NSURL *authorizationURL, NSString *authorizationCode, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(authorizationCode);
        
        NSDictionary *codeData = [self.oauthServer getAuthorizationCodeData:authorizationCode];
        XCTAssertNotNil(codeData[@"webauthn_challenge"]);
        XCTAssertEqual(((NSData *)codeData[@"webauthn_challenge"]).length, 32);
    }];
}

- (void)testWebauthnChallengeIsValidData {
    OAuth2AuthorizationRequest *req = [[OAuth2AuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"http://127.0.0.1:3000/callback";
    req.responseType = @"code";
    req.webauthn = YES;
    
    [self.oauthServer handleAuthorizationRequest:req completion:^(NSURL *authorizationURL, NSString *authorizationCode, NSError *error) {
        XCTAssertNil(error);
        
        NSDictionary *codeData = [self.oauthServer getAuthorizationCodeData:authorizationCode];
        NSData *challenge = codeData[@"webauthn_challenge"];
        
        XCTAssertNotNil(challenge);
        XCTAssertEqual(challenge.length, 32);
        XCTAssertTrue(challenge.length > 0);
    }];
}

- (void)testNonWebauthnAuthorizationRequestNoChallenge {
    OAuth2AuthorizationRequest *req = [[OAuth2AuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"http://127.0.0.1:3000/callback";
    req.responseType = @"code";
    req.webauthn = NO;
    
    [self.oauthServer handleAuthorizationRequest:req completion:^(NSURL *authorizationURL, NSString *authorizationCode, NSError *error) {
        XCTAssertNil(error);
        
        NSDictionary *codeData = [self.oauthServer getAuthorizationCodeData:authorizationCode];
        XCTAssertNil(codeData[@"webauthn_challenge"]);
    }];
}

@end

NS_ASSUME_NONNULL_END