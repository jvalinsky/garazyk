#import <XCTest/XCTest.h>
#import "Auth/Base32Utils.h"
#import "Auth/TOTPGenerator.h"
#import "Auth/TOTPService.h"
#import "Auth/YubiKeyOATH.h"

@interface TOTPTests : XCTestCase
@end

@implementation TOTPTests

- (void)testBase32Encoding {
    NSDictionary *testCases = @{
        @"": @"",
        @"f": @"MY======",
        @"fo": @"MZXQ====",
        @"foo": @"MZXW6===",
        @"foob": @"MZXW6YQ=",
        @"fooba": @"MZXW6YTB",
        @"foobar": @"MZXW6YTBOI======"
    };
    
    [testCases enumerateKeysAndObjectsUsingBlock:^(id input, id expected, BOOL *stop) {
        NSData *data = [(NSString *)input dataUsingEncoding:NSUTF8StringEncoding];
        NSString *result = [Base32Utils base32StringFromData:data];
        XCTAssertEqualObjects(result, expected, @"Base32 encoding failed for input: %@", input);
    }];
}

- (void)testBase32Decoding {
    NSDictionary *testCases = @{
        @"": @"",
        @"MY======": @"f",
        @"MZXQ====": @"fo",
        @"MZXW6===": @"foo",
        @"MZXW6YQ=": @"foob",
        @"MZXW6YTB": @"fooba",
        @"MZXW6YTBOI======": @"foobar"
    };
    
    [testCases enumerateKeysAndObjectsUsingBlock:^(id input, id expected, BOOL *stop) {
        NSData *resultData = [Base32Utils dataFromBase32String:input];
        NSString *result = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];
        XCTAssertEqualObjects(result, expected, @"Base32 decoding failed for input: %@", input);
    }];
}

- (void)testTOTPGeneration {
    NSData *secretData = [@"12345678901234567890" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPGenerator *gen = [[TOTPGenerator alloc] initWithSecret:secretData];
    
    NSString *code1 = [gen generateOTP];
    NSString *code2 = [gen generateOTP];
    XCTAssertEqualObjects(code1, code2, @"TOTP should be consistent for same time interval");
    XCTAssertEqual(code1.length, 6, @"TOTP should have default length of 6");
}

- (void)testTOTPServiceVerification {
    NSString *base32Secret = @"JBSWY3DPEHPK3PXP"; // "Hello!" in base32
    
    NSData *secretData = [Base32Utils dataFromBase32String:base32Secret];
    TOTPGenerator *gen = [[TOTPGenerator alloc] initWithSecret:secretData];
    NSString *code = [gen generateOTP];
    
    XCTAssertTrue([TOTPService verifyCode:code secret:base32Secret], @"TOTP should be valid for current interval");
    
    // Test window (prev interval)
    NSDate *prevDate = [NSDate dateWithTimeIntervalSinceNow:-30];
    NSString *prevCode = [gen generateOTPForDate:prevDate];
    XCTAssertTrue([TOTPService verifyCode:prevCode secret:base32Secret], @"TOTP should be valid for previous interval (within window)");
    
    // Test invalid
    XCTAssertFalse([TOTPService verifyCode:@"000000" secret:base32Secret], @"Random code should be invalid");
}

- (void)testYubiKeyOATHFallback {
    NSData *secretData = [@"12345678901234567890" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secretData];
    NSError *error = nil;

    NSString *token = [service generateTOTPToken:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    XCTAssertEqual(token.length, 6, @"TOTP token should be 6 digits");
}

@end
