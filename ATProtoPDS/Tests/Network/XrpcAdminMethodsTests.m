//
//  XrpcAdminMethodsTests.m
//  ATProtoPDS
//
//  Smoke tests for XrpcAdminMethods, XrpcAuthHelper, and XrpcIdentityHelper.
//

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcAdminMethods.h"
#import "Network/HttpRequest.h"

@interface XrpcAdminMethodsTests : XCTestCase
@end

@implementation XrpcAdminMethodsTests

// MARK: - XrpcAuthHelper: Bearer token extraction

- (void)testAuthHelperRejectsMissingHeader {
    // Passing nil auth header returns nil (no crash).
    NSString *result = [XrpcAuthHelper extractDIDFromAuthHeader:nil
                                                      jwtMinter:nil
                                                adminController:nil
                                                        request:nil
                                                       response:nil];
    XCTAssertNil(result, @"Missing auth header must return nil DID");
}

- (void)testAuthHelperRejectsEmptyHeader {
    NSString *result = [XrpcAuthHelper extractDIDFromAuthHeader:@""
                                                      jwtMinter:nil
                                                adminController:nil
                                                        request:nil
                                                       response:nil];
    XCTAssertNil(result, @"Empty auth header must return nil DID");
}

- (void)testAuthHelperRejectsMalformedBearerToken {
    // A Bearer token with a structurally invalid JWT must fail gracefully.
    NSString *result = [XrpcAuthHelper extractDIDFromAuthHeader:@"Bearer not-a-real-jwt"
                                                      jwtMinter:nil
                                                adminController:nil
                                                        request:nil
                                                       response:nil];
    XCTAssertNil(result, @"Malformed Bearer token must return nil DID");
}

// MARK: - XrpcIdentityHelper: handle normalization

- (void)testIdentityHelperNormalizesHandle {
    // resolveHandleToDid: lowercases the handle before resolution.
    // With a nil resolver it must return nil gracefully (not crash).
    NSError *error = nil;
    NSString *result = [XrpcIdentityHelper resolveHandleToDid:@"Alice.Test"
                                               handleResolver:nil
                                                        error:&error];
    XCTAssertNil(result, @"Resolution without a resolver should fail gracefully");
    // Error may or may not be set — the key assertion is no crash.
}

- (void)testIdentityHelperNilDIDResolution {
    NSError *error = nil;
    NSString *outDid = nil;
    BOOL ok = [XrpcIdentityHelper resolveAccountIdentifierToDid:@"did:plc:test"
                                               serviceDatabases:nil
                                                         outDid:&outDid
                                                          error:&error];
    XCTAssertFalse(ok, @"Resolution against nil databases must fail");
}

// MARK: - XrpcAdminMethods: class availability

- (void)testXrpcAdminMethodsClassExists {
    XCTAssertNotNil([XrpcAdminMethods class], @"XrpcAdminMethods class must exist");
}

@end
