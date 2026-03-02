#import <XCTest/XCTest.h>
#import "Network/XrpcErrorHelper.h"

@interface XrpcErrorHelperTests : XCTestCase
@end

@implementation XrpcErrorHelperTests

- (NSDictionary *)jsonBodyFromResponse:(HttpResponse *)response {
    XCTAssertNotNil(response.body);
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
    return obj;
}

- (void)testAuthenticationErrorUsesDefaultMessageWhenNil {
    HttpResponse *response = [HttpResponse response];
    [XrpcErrorHelper setAuthenticationError:response message:nil];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(body[@"error"], @"AuthRequired");
    XCTAssertEqualObjects(body[@"message"], @"Authentication required");
}

- (void)testAuthorizationAndValidationUseProvidedMessages {
    HttpResponse *authz = [HttpResponse response];
    [XrpcErrorHelper setAuthorizationError:authz message:@"nope"];
    NSDictionary *authzBody = [self jsonBodyFromResponse:authz];
    XCTAssertEqual(authz.statusCode, HttpStatusForbidden);
    XCTAssertEqualObjects(authzBody[@"error"], @"Forbidden");
    XCTAssertEqualObjects(authzBody[@"message"], @"nope");

    HttpResponse *validation = [HttpResponse response];
    [XrpcErrorHelper setValidationError:validation message:@"bad input"];
    NSDictionary *validationBody = [self jsonBodyFromResponse:validation];
    XCTAssertEqual(validation.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(validationBody[@"error"], @"InvalidRequest");
    XCTAssertEqualObjects(validationBody[@"message"], @"bad input");
}

- (void)testNotFoundAndInternalServerErrorDefaults {
    HttpResponse *notFound = [HttpResponse response];
    [XrpcErrorHelper setNotFoundError:notFound message:nil];
    NSDictionary *notFoundBody = [self jsonBodyFromResponse:notFound];
    XCTAssertEqual(notFound.statusCode, HttpStatusNotFound);
    XCTAssertEqualObjects(notFoundBody[@"error"], @"NotFound");
    XCTAssertEqualObjects(notFoundBody[@"message"], @"Not found");

    HttpResponse *internal = [HttpResponse response];
    [XrpcErrorHelper setInternalServerError:internal message:nil];
    NSDictionary *internalBody = [self jsonBodyFromResponse:internal];
    XCTAssertEqual(internal.statusCode, HttpStatusInternalServerError);
    XCTAssertEqualObjects(internalBody[@"error"], @"InternalServerError");
    XCTAssertEqualObjects(internalBody[@"message"], @"Internal server error");
}

- (void)testMethodNotAllowedSetsAllowHeaderAndDefaultMessage {
    HttpResponse *response = [HttpResponse response];
    [XrpcErrorHelper setMethodNotAllowedError:response allowedMethod:@"POST" message:nil];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertEqual(response.statusCode, HttpStatusMethodNotAllowed);
    XCTAssertEqualObjects([response headerForKey:@"Allow"], @"POST");
    XCTAssertEqualObjects(body[@"error"], @"MethodNotAllowed");
    XCTAssertEqualObjects(body[@"message"], @"Expected POST");
}

- (void)testMethodNotAllowedSkipsAllowHeaderWhenEmptyAndUsesCustomMessage {
    HttpResponse *response = [HttpResponse response];
    [XrpcErrorHelper setMethodNotAllowedError:response allowedMethod:@"" message:@"custom"];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertNil([response headerForKey:@"Allow"]);
    XCTAssertEqualObjects(body[@"message"], @"custom");
}

- (void)testSetErrorAndConvenienceMethods {
    HttpResponse *custom = [HttpResponse response];
    [XrpcErrorHelper setError:custom statusCode:HttpStatusConflict errorCode:@"Conflict" message:@"already exists"];
    NSDictionary *customBody = [self jsonBodyFromResponse:custom];
    XCTAssertEqual(custom.statusCode, HttpStatusConflict);
    XCTAssertEqualObjects(customBody[@"error"], @"Conflict");
    XCTAssertEqualObjects(customBody[@"message"], @"already exists");

    HttpResponse *invalid = [HttpResponse response];
    [XrpcErrorHelper setInvalidRequestError:invalid message:@"bad"];
    NSDictionary *invalidBody = [self jsonBodyFromResponse:invalid];
    XCTAssertEqualObjects(invalidBody[@"error"], @"InvalidRequest");
    XCTAssertEqualObjects(invalidBody[@"message"], @"bad");

    HttpResponse *account = [HttpResponse response];
    [XrpcErrorHelper setAccountNotFoundError:account identifier:@"did:plc:abc"];
    NSDictionary *accountBody = [self jsonBodyFromResponse:account];
    XCTAssertEqualObjects(accountBody[@"error"], @"AccountNotFound");
    XCTAssertEqualObjects(accountBody[@"message"], @"Account not found: did:plc:abc");

    HttpResponse *lexicon = [HttpResponse response];
    [XrpcErrorHelper setLexiconNotFoundError:lexicon nsid:@"com.atproto.server.createSession"];
    NSDictionary *lexiconBody = [self jsonBodyFromResponse:lexicon];
    XCTAssertEqualObjects(lexiconBody[@"error"], @"LexiconNotFound");
    XCTAssertEqualObjects(lexiconBody[@"message"], @"Lexicon not found: com.atproto.server.createSession");
}

@end
