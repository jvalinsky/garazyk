// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CharacterizationTestBase.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyPack.h"
#import "Network/ATProtoHttpXrpcRoutePack.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Core/CID.h"
#import "App/PDSApplication.h"

@interface XrpcMethodRegistryCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) ATProtoXrpcMethodRegistry *subject;

@end

static ATProtoHttpResponse *XrpcCharacterizationDispatchRequest(ATProtoXrpcDispatcher *dispatcher,
                                                          NSString *methodId) {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:[@"/xrpc/" stringByAppendingString:methodId]
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [ATProtoHttpResponse response];
    [dispatcher handleRequest:request response:response];
    return response;
}

static void XrpcCharacterizationRegisterFirstFixturePack(ATProtoXrpcDispatcher *dispatcher) {
    [dispatcher registerMethod:@"test.xrpc.fixture.crossPack"
                       handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         response.statusCode = HttpStatusOK;
                       }];
}

static void XrpcCharacterizationRegisterSecondFixturePack(ATProtoXrpcDispatcher *dispatcher) {
    [dispatcher registerMethod:@"test.xrpc.fixture.crossPack"
                       handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         response.statusCode = HttpStatusNoContent;
                       }];
}

@implementation XrpcMethodRegistryCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [[ATProtoXrpcMethodRegistry alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for ATProtoXrpcMethodRegistry
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_Class_registerMethodsWithDispatcher {
    /* Target Method:
     + (void)registerMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                           application:(PDSApplication *)application;
    */
    
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        [ATProtoXrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }

    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.server.describeServer"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [ATProtoHttpResponse response];
    [dispatcher handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(((NSDictionary *)response.jsonBody)[@"did"]);
}

- (void)testCharacterization_Class_publicKeyBytesFromMultibase {
    /* Target Method:
     + (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase error:(NSError **)error;
    */
    
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [ATProtoSecp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", keyError);

    uint8_t prefixBytes[] = {0xE7, 0x01};
    NSMutableData *multicodec = [NSMutableData dataWithBytes:prefixBytes length:sizeof(prefixBytes)];
    [multicodec appendData:keyPair.compressedPublicKey];

    NSString *multibase = [NSString stringWithFormat:@"z%@", [ATProtoCID base58btcEncode:multicodec]];

    NSError *decodeError = nil;
    NSData *decoded = [ATProtoXrpcIdentityHelper publicKeyBytesFromMultibase:multibase error:&decodeError];
    XCTAssertNotNil(decoded);
    XCTAssertNil(decodeError);
    XCTAssertEqualObjects(decoded, keyPair.compressedPublicKey);

    NSError *invalidError = nil;
    XCTAssertNil([ATProtoXrpcIdentityHelper publicKeyBytesFromMultibase:@"xnot-supported" error:&invalidError]);
    XCTAssertNotNil(invalidError);
}

- (void)testCharacterization_DuplicateRegistrationWithinOnePackIsRejected {
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    [dispatcher registerMethod:@"test.xrpc.fixture.samePack"
                       handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         response.statusCode = HttpStatusOK;
                       }];

    NSException *exception = nil;
    @try {
        [dispatcher registerMethod:@"test.xrpc.fixture.samePack"
                           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                             response.statusCode = HttpStatusNoContent;
                           }];
    } @catch (NSException *caught) {
        exception = caught;
    }

    XCTAssertNotNil(exception);
    XCTAssertEqualObjects(exception.name, NSInternalInconsistencyException);
}

- (void)testCharacterization_DuplicateRegistrationAcrossPacksIsRejected {
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    XrpcCharacterizationRegisterFirstFixturePack(dispatcher);

    NSException *exception = nil;
    @try {
        XrpcCharacterizationRegisterSecondFixturePack(dispatcher);
    } @catch (NSException *caught) {
        exception = caught;
    }

    XCTAssertNotNil(exception);
    XCTAssertEqualObjects(exception.name, NSInternalInconsistencyException);
}

- (void)testCharacterization_RetainedGraphListRoutesRequireAuthentication {
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    ATProtoXrpcRoutePackServiceBag *services =
        [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];
    [ATProtoXrpcAppBskyGraphPack registerWithDispatcher:dispatcher services:services];

    for (NSString *methodId in @[
             @"app.bsky.graph.getListMutes",
             @"app.bsky.graph.getListBlocks"
         ]) {
        ATProtoHttpResponse *response = XrpcCharacterizationDispatchRequest(dispatcher, methodId);
        XCTAssertEqual(response.statusCode, HttpStatusUnauthorized,
                       @"%@ must remain a locally registered authenticated route", methodId);
    }
}

- (void)testCharacterization_MissingVideoStoreSkipsOnlyVideoRoutes {
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    ATProtoXrpcRoutePackServiceBag *services =
        [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];

    [ATProtoXrpcAppBskyPack registerAppViewMethodsWithDispatcher:dispatcher services:services];

    XCTAssertFalse([dispatcher hasRegisteredMethod:@"app.bsky.video.getJobStatus"]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:@"app.bsky.unspecced.getConfig"]);
}

- (void)testCharacterization_RetainedLabelerRouteIsOwnedByAppBskyPack {
    ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    ATProtoXrpcRoutePackServiceBag *services =
        [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];
    [ATProtoXrpcAppBskyPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];

    ATProtoHttpResponse *response =
        XrpcCharacterizationDispatchRequest(dispatcher, @"app.bsky.labeler.getServices");
    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testCharacterization_RepeatedRoutePackInitializationReplacesFullRegistry {
    NSURL *firstDataURL =
        [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSURL *secondDataURL =
        [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:firstDataURL
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:secondDataURL
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    @try {
        ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
        PDSApplication *firstApplication = [[PDSApplication alloc] initWithDataDirectory:firstDataURL.path];
        PDSApplication *secondApplication = [[PDSApplication alloc] initWithDataDirectory:secondDataURL.path];

        [ATProtoHttpXrpcRoutePack registerRoutesWithServer:[ATProtoHttpServer serverWithPort:0]
                                                dispatcher:dispatcher
                                               application:firstApplication
                                                controller:nil
                                     subscribeReposHandler:nil
                                            setCorsHeaders:^(ATProtoHttpResponse *response, ATProtoHttpRequest *request) {
                                            }];

        NSException *exception = nil;
        @try {
            [ATProtoHttpXrpcRoutePack registerRoutesWithServer:[ATProtoHttpServer serverWithPort:0]
                                                    dispatcher:dispatcher
                                                   application:secondApplication
                                                    controller:nil
                                         subscribeReposHandler:nil
                                                setCorsHeaders:^(ATProtoHttpResponse *response, ATProtoHttpRequest *request) {
                                                }];
        } @catch (NSException *caught) {
            exception = caught;
        }

        XCTAssertNil(exception);
        XCTAssertTrue([dispatcher hasRegisteredMethod:@"com.atproto.lexicon.resolveLexicon"]);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:firstDataURL error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:secondDataURL error:nil];
    }
}

@end
