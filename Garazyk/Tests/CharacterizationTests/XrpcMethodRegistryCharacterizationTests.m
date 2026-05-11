// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CharacterizationTestBase.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/Secp256k1.h"
#import "Core/CID.h"
#import "App/PDSApplication.h"

@interface XrpcMethodRegistryCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) XrpcMethodRegistry *subject;

@end

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

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];
    } @finally {
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
    NSData *decoded = [XrpcMethodRegistry publicKeyBytesFromMultibase:multibase error:&decodeError];
    XCTAssertNotNil(decoded);
    XCTAssertNil(decodeError);
    XCTAssertEqualObjects(decoded, keyPair.compressedPublicKey);

    NSError *invalidError = nil;
    XCTAssertNil([XrpcMethodRegistry publicKeyBytesFromMultibase:@"xnot-supported" error:&invalidError]);
    XCTAssertNotNil(invalidError);
}

@end
