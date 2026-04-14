#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/Network/XRPCError.h"

@interface XRPCErrorTests : XCTestCase
@end

@implementation XRPCErrorTests

- (void)testErrorWithValidData {
    NSDictionary *dict = @{
        @"error": @"InvalidRequest",
        @"message": @"The request was invalid"
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    
    XRPCError *error = [XRPCError errorWithData:data statusCode:400];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.error, @"InvalidRequest");
    XCTAssertEqualObjects(error.message, @"The request was invalid");
    XCTAssertEqual(error.statusCode, 400);
}

- (void)testErrorWithMissingMessage {
    NSDictionary *dict = @{@"error": @"AuthRequired"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    
    XRPCError *error = [XRPCError errorWithData:data statusCode:401];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.error, @"AuthRequired");
    XCTAssertEqualObjects(error.message, @"An unknown error occurred");
    XCTAssertEqual(error.statusCode, 401);
}

- (void)testErrorWithMissingError {
    NSDictionary *dict = @{@"message": @"Something went wrong"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    
    XRPCError *error = [XRPCError errorWithData:data statusCode:500];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.error, @"UnknownError");
    XCTAssertEqualObjects(error.message, @"Something went wrong");
    XCTAssertEqual(error.statusCode, 500);
}

- (void)testErrorWithInvalidData {
    NSData *invalidData = [NSData dataWithBytes:"invalid json" length:12];
    
    XRPCError *error = [XRPCError errorWithData:invalidData statusCode:500];
    
    XCTAssertNil(error);
}

- (void)testErrorWithNonDictionaryJSON {
    NSArray *array = @[@"error", @"message"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:array options:0 error:nil];
    
    XRPCError *error = [XRPCError errorWithData:data statusCode:500];
    
    XCTAssertNil(error);
}

- (void)testErrorWithEmptyData {
    XRPCError *error = [XRPCError errorWithData:[NSData data] statusCode:500];
    
    XCTAssertNil(error);
}

- (void)testErrorWithDictionary {
    NSDictionary *dict = @{
        @"error": @"RateLimited",
        @"message": @"Too many requests"
    };
    
    XRPCError *error = [XRPCError errorWithDictionary:dict statusCode:429];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.error, @"RateLimited");
    XCTAssertEqualObjects(error.message, @"Too many requests");
    XCTAssertEqual(error.statusCode, 429);
}

- (void)testInitWithValues {
    XRPCError *error = [[XRPCError alloc] initWithError:@"TestError"
                                                 message:@"Test message"
                                              statusCode:418];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.error, @"TestError");
    XCTAssertEqualObjects(error.message, @"Test message");
    XCTAssertEqual(error.statusCode, 418);
}

- (void)testDescription {
    XRPCError *error = [[XRPCError alloc] initWithError:@"BadRequest"
                                                 message:@"Invalid parameters"
                                              statusCode:400];
    
    NSString *desc = error.description;
    
    XCTAssertTrue([desc containsString:@"XRPCError 400"]);
    XCTAssertTrue([desc containsString:@"BadRequest"]);
    XCTAssertTrue([desc containsString:@"Invalid parameters"]);
}

- (void)testToNSError {
    XRPCError *error = [[XRPCError alloc] initWithError:@"NotFound"
                                                 message:@"Resource not found"
                                              statusCode:404];
    
    NSError *nsError = [error toNSError];
    
    XCTAssertNotNil(nsError);
    XCTAssertEqualObjects(nsError.domain, XRPCErrorDomain);
    XCTAssertEqual(nsError.code, 404);
    XCTAssertEqualObjects(nsError.localizedDescription, @"Resource not found");
    XCTAssertNotNil(nsError.userInfo[@"XRPCErrorCode"]);
    XCTAssertEqualObjects(nsError.userInfo[@"XRPCErrorCode"], @"NotFound");
}

- (void)testErrorDomain {
    XCTAssertEqualObjects(XRPCErrorDomain, @"com.atproto.xrpc.error");
}

@end
