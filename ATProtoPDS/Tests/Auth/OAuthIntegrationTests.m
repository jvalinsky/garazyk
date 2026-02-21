#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/OAuth2.h"
#import "Auth/PKCEUtil.h"
#import "Auth/DPoPUtil.h"
#import "Database/PDSDatabase.h"
#import "Auth/Secp256k1.h"
#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Network/HttpResponse.h"

@interface OAuthRedirectDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^onRedirect)(NSURLRequest *request);
@property (nonatomic, copy) void (^onResponse)(NSHTTPURLResponse *response);
@property (nonatomic, copy) void (^onError)(NSError *error);
@end

@implementation OAuthRedirectDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    NSLog(@"[TEST DEL] Redirecting to: %@", request.URL);
    if (self.onRedirect) {
        self.onRedirect(request);
    }
    completionHandler(nil); // Stop redirection
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSLog(@"[TEST DEL] Received response: %ld", (long)((NSHTTPURLResponse *)response).statusCode);
    if (self.onResponse) {
        self.onResponse((NSHTTPURLResponse *)response);
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"[TEST DEL] Completed with error: %@", error);
        if (self.onError) {
            self.onError(error);
        }
    } else {
        NSLog(@"[TEST DEL] Completed successfully");
    }
}
@end

@interface OAuthIntegrationTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) OAuth2Server *oauthServer;
@property (nonatomic, strong) OAuth2Handler *oauthHandler;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) OAuthRedirectDelegate *redirectDelegate;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation OAuthIntegrationTests

- (void)setUp {
    [super setUp];
    
    // Setup Database in-memory or in a temp file
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    [self.db openWithError:nil];
    
    // Setup OAuth Server first (so it doesn't overwrite our manual seeding later)
    self.oauthServer = [[OAuth2Server alloc] initWithDatabase:self.db];
    self.oauthServer.issuer = @"http://127.0.0.1:8443";
    
    // Setup HTTP Server
    self.server = [HttpServer serverWithPort:0];
    self.oauthHandler = [[OAuth2Handler alloc] initWithDatabase:self.db];
    self.oauthHandler.oauthServer = self.oauthServer;
    [self.oauthHandler registerRoutesWithServer:self.server];
    
    // Manually seed test client (overwriting any seeded by OAuth2Handler)
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://127.0.0.1:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self.db createClient:testClient error:nil];
    
    // Create a test user
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test-user-did";
    account.handle = @"test-user.test";
    account.email = @"test@test.com";
    [self.db createAccount:account error:nil];
    
    // Setup Session
    self.redirectDelegate = [[OAuthRedirectDelegate alloc] init];
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] 
                                                 delegate:self.redirectDelegate 
                                            delegateQueue:nil];
    
	    // Add a simple health handler
	    [self.server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *res) {
	        res.statusCode = 200;
	        [res setBodyString:@"OK"];
	    }];
	    
	    NSError *startError = nil;
	    if (![self.server startWithError:&startError]) {
	        NSError *underlying = startError.userInfo[NSUnderlyingErrorKey];
	        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
	            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
	        }
	        XCTFail(@"Failed to start HttpServer: %@", startError);
	    }
}

- (void)tearDown {
    [self.server stop];
    [self.db close];
    self.server = nil;
    self.oauthServer = nil;
    self.db = nil;
    [super tearDown];
}

- (void)testConnectivity {
    NSUInteger port = self.server.port;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/health", (unsigned long)port]];
    
    __block BOOL finished = NO;
    __block NSInteger status = 0;
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[TEST CONN] Error: %@", error);
        } else {
            status = [(NSHTTPURLResponse *)response statusCode];
            NSLog(@"[TEST CONN] Status: %ld", (long)status);
        }
        finished = YES;
    }] resume];
    
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!finished && [timeoutDate timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    
    XCTAssertEqual(status, 200, @"Health check should return 200");
}

- (void)testFullOAuthFlow {
    // Phase 1: Client generates PKCE parameters
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
    
    // Phase 2: Seed authorization code directly since /oauth/authorize now serves
    // a consent page (200 HTML) and resolveIdentity requires DNS. We test the core
    // auth code + token exchange flow (PKCE + DPoP) without the consent UI.
    NSUInteger port = self.server.port;

    NSString *authCode = [[NSUUID UUID] UUIDString];
    NSDictionary *codeData = @{
        @"client_id": @"test-client",
        @"redirect_uri": @"http://127.0.0.1:3000/callback",
        @"scope": @"atproto:identify",
        @"state": @"test123",
        @"code_challenge": challenge,
        @"code_challenge_method": @"S256",
        @"login_hint": @"test-user.test",
        @"login_hint_did": @"did:plc:test-user-did",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };
    self.oauthServer.authorizationCodes[authCode] = codeData;

    XCTAssertNotNil(authCode, @"Should have authorization code");
    
    // Phase 3: Token Exchange with DPoP
    SecKeyRef privateKey;
    NSDictionary* attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeySizeInBits: @256,
        (id)kSecAttrIsPermanent: (__bridge id)kCFBooleanFalse
    };
    CFErrorRef keyError = NULL;
    privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &keyError);
    XCTAssertNotNil((__bridge id)privateKey, @"Failed to generate DPoP key: %@", keyError);
    
    NSString *tokenUri = [NSString stringWithFormat:@"http://127.0.0.1:%lu/oauth/token", (unsigned long)port];
    DPoPToken *dpopToken = [DPoPUtil createDPoPForMethod:@"POST" uri:tokenUri nonce:nil key:privateKey error:nil];
    XCTAssertNotNil(dpopToken, @"Failed to create DPoP token");
    
    NSString *body = [NSString stringWithFormat:@"grant_type=authorization_code&client_id=test-client&redirect_uri=http://127.0.0.1:3000/callback&code=%@&code_verifier=%@", authCode, verifier];

    // Step 1: Send initial token request without nonce to get DPoP-Nonce from server
    NSMutableURLRequest *nonceRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenUri]];
    nonceRequest.HTTPMethod = @"POST";
    [nonceRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [nonceRequest setValue:dpopToken.jwt forHTTPHeaderField:@"DPoP"];
    nonceRequest.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    __block BOOL nonceFinished = NO;
    __block NSString *dpopNonce = nil;

    [[self.session dataTaskWithRequest:nonceRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        dpopNonce = [httpResponse valueForHTTPHeaderField:@"DPoP-Nonce"];
        NSLog(@"[TEST] Nonce challenge response: status=%ld, nonce=%@", (long)httpResponse.statusCode, dpopNonce);
        nonceFinished = YES;
    }] resume];

    NSDate *nonceTimeout = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!nonceFinished && [nonceTimeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    XCTAssertNotNil(dpopNonce, @"Server should return DPoP-Nonce header");

    // Re-seed authorization code since the first attempt consumed it
    NSString *authCode2 = [[NSUUID UUID] UUIDString];
    NSDictionary *codeData2 = @{
        @"client_id": @"test-client",
        @"redirect_uri": @"http://127.0.0.1:3000/callback",
        @"scope": @"atproto:identify",
        @"state": @"test123",
        @"code_challenge": challenge,
        @"code_challenge_method": @"S256",
        @"login_hint": @"test-user.test",
        @"login_hint_did": @"did:plc:test-user-did",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };
    self.oauthServer.authorizationCodes[authCode2] = codeData2;

    // Step 2: Retry with nonce-bound DPoP proof
    DPoPToken *dpopToken2 = [DPoPUtil createDPoPForMethod:@"POST" uri:tokenUri nonce:dpopNonce key:privateKey error:nil];
    XCTAssertNotNil(dpopToken2, @"Failed to create DPoP token with nonce");

    NSString *body2 = [NSString stringWithFormat:@"grant_type=authorization_code&client_id=test-client&redirect_uri=http://127.0.0.1:3000/callback&code=%@&code_verifier=%@", authCode2, verifier];

    NSMutableURLRequest *tokenRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenUri]];
    tokenRequest.HTTPMethod = @"POST";
    [tokenRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [tokenRequest setValue:dpopToken2.jwt forHTTPHeaderField:@"DPoP"];
    tokenRequest.HTTPBody = [body2 dataUsingEncoding:NSUTF8StringEncoding];
    
    __block BOOL tokenFinished = NO;
    __block NSString *accessToken = nil;
    
    [[self.session dataTaskWithRequest:tokenRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should return 200 OK for token exchange");
        
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSLog(@"[TEST] Token response: %@", json);
            XCTAssertEqualObjects(json[@"token_type"], @"DPoP", @"Token type should be DPoP");
            accessToken = json[@"access_token"];
            XCTAssertNotNil(accessToken, @"Should have received access token");
        }
        tokenFinished = YES;
    }] resume];
    
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!tokenFinished && [timeoutDate timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    
    // Phase 4: Verify Token with DPoP binding
    // We can directly check if the session exists and has the correct thumbprint
    XCTAssertNotNil(accessToken);
    BOOL found = NO;
    for (Session *s in self.oauthServer.activeSessions.allValues) {
        if ([s.accessToken isEqualToString:accessToken]) {
            XCTAssertNotNil(s.dpopKeyThumbprint, @"Session should be bound to DPoP key");
            found = YES;
            break;
        }
    }
    XCTAssertTrue(found, @"Should have an active session for the issued token");
    
    if (privateKey) CFRelease(privateKey);
}

@end
