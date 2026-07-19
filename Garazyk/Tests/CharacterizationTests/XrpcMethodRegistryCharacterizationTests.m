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
#import "Auth/Secp256k1.h"
#import "Core/CID.h"
#import "App/PDSApplication.h"

@interface XrpcMethodRegistryCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) XrpcMethodRegistry *subject;

@end

static HttpResponse *XrpcCharacterizationDispatchRequest(XrpcDispatcher *dispatcher,
                                                          NSString *methodId) {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:[@"/xrpc/" stringByAppendingString:methodId]
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];
    [dispatcher handleRequest:request response:response];
    return response;
}

static void XrpcCharacterizationRegisterFirstFixturePack(XrpcDispatcher *dispatcher) {
    [dispatcher registerMethod:@"test.xrpc.fixture.crossPack"
                       handler:^(HttpRequest *request, HttpResponse *response) {
                         response.statusCode = HttpStatusOK;
                       }];
}

static void XrpcCharacterizationRegisterSecondFixturePack(XrpcDispatcher *dispatcher) {
    [dispatcher registerMethod:@"test.xrpc.fixture.crossPack"
                       handler:^(HttpRequest *request, HttpResponse *response) {
                         response.statusCode = HttpStatusNoContent;
                       }];
}

@implementation XrpcMethodRegistryCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [[XrpcMethodRegistry alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for XrpcMethodRegistry
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_Class_registerMethodsWithDispatcher {
    /* Target Method:
     + (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           application:(PDSApplication *)application;
    */
    
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.server.describeServer"
                                                   queryString:@""
                                                    queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:[NSData data]
                                                  remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];
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
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", keyError);

    uint8_t prefixBytes[] = {0xE7, 0x01};
    NSMutableData *multicodec = [NSMutableData dataWithBytes:prefixBytes length:sizeof(prefixBytes)];
    [multicodec appendData:keyPair.compressedPublicKey];

    NSString *multibase = [NSString stringWithFormat:@"z%@", [CID base58btcEncode:multicodec]];

    NSError *decodeError = nil;
    NSData *decoded = [XrpcIdentityHelper publicKeyBytesFromMultibase:multibase error:&decodeError];
    XCTAssertNotNil(decoded);
    XCTAssertNil(decodeError);
    XCTAssertEqualObjects(decoded, keyPair.compressedPublicKey);

    NSError *invalidError = nil;
    XCTAssertNil([XrpcIdentityHelper publicKeyBytesFromMultibase:@"xnot-supported" error:&invalidError]);
    XCTAssertNotNil(invalidError);
}

- (void)testCharacterization_DuplicateRegistrationWithinOnePackIsRejected {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    [dispatcher registerMethod:@"test.xrpc.fixture.samePack"
                       handler:^(HttpRequest *request, HttpResponse *response) {
                         response.statusCode = HttpStatusOK;
                       }];

    NSException *exception = nil;
    @try {
        [dispatcher registerMethod:@"test.xrpc.fixture.samePack"
                           handler:^(HttpRequest *request, HttpResponse *response) {
                             response.statusCode = HttpStatusNoContent;
                           }];
    } @catch (NSException *caught) {
        exception = caught;
    }

    XCTAssertNotNil(exception);
    XCTAssertEqualObjects(exception.name, NSInternalInconsistencyException);
}

- (void)testCharacterization_DuplicateRegistrationAcrossPacksIsRejected {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
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
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    XrpcRoutePackServiceBag *services =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];
    [XrpcAppBskyGraphPack registerWithDispatcher:dispatcher services:services];

    for (NSString *methodId in @[
             @"app.bsky.graph.getListMutes",
             @"app.bsky.graph.getListBlocks"
         ]) {
        HttpResponse *response = XrpcCharacterizationDispatchRequest(dispatcher, methodId);
        XCTAssertEqual(response.statusCode, HttpStatusUnauthorized,
                       @"%@ must remain a locally registered authenticated route", methodId);
    }
}

- (void)testCharacterization_RetainedLabelerRouteIsOwnedByAppBskyPack {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    XrpcRoutePackServiceBag *services =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];
    [XrpcAppBskyPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];

    HttpResponse *response =
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
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        PDSApplication *firstApplication = [[PDSApplication alloc] initWithDataDirectory:firstDataURL.path];
        PDSApplication *secondApplication = [[PDSApplication alloc] initWithDataDirectory:secondDataURL.path];

        [ATProtoHttpXrpcRoutePack registerRoutesWithServer:[HttpServer serverWithPort:0]
                                                dispatcher:dispatcher
                                               application:firstApplication
                                                controller:nil
                                     subscribeReposHandler:nil
                                            setCorsHeaders:^(HttpResponse *response, HttpRequest *request) {
                                            }];

        NSException *exception = nil;
        @try {
            [ATProtoHttpXrpcRoutePack registerRoutesWithServer:[HttpServer serverWithPort:0]
                                                    dispatcher:dispatcher
                                                   application:secondApplication
                                                    controller:nil
                                         subscribeReposHandler:nil
                                                setCorsHeaders:^(HttpResponse *response, HttpRequest *request) {
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
