#import <XCTest/XCTest.h>
#import "Auth/Base32Utils.h"
#import "Auth/TOTPGenerator.h"
#import "Auth/TOTPService.h"
#import "Auth/YubiKeyOATH.h"

@interface TOTPTests : XCTestCase
@end

@interface TOTPService (TestHooks)
- (nullable NSString *)generateSoftwareToken;
@end

@interface TOTPStubYubiManager : YubiKeyOATHManager
@property (nonatomic, copy) NSString *tokenToReturn;
@end

@implementation TOTPStubYubiManager
- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    (void)secret;
    (void)counter;
    if (self.tokenToReturn) {
        return self.tokenToReturn;
    }
    return [super generateTOTPForSecret:secret counter:counter error:error];
}
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
    
    [testCases enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *input = (NSString *)key;
        NSString *expected = (NSString *)obj;
        NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
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
    
    [testCases enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *input = (NSString *)key;
        NSString *expected = (NSString *)obj;
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

- (void)testGenerateSecretRoundTripLength {
    NSString *secret = [TOTPService generateSecret];
    XCTAssertNotNil(secret);
    NSData *decoded = [Base32Utils dataFromBase32String:secret];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.length, 20u);
}

- (void)testVerifyCodeRejectsInvalidSecretEncoding {
    XCTAssertFalse([TOTPService verifyCode:@"123456" secret:@"!invalid-base32!"]);
}

- (void)testGenerateQRCodeImage {
    NSData *qr = [TOTPService generateQRCodeImageForSecret:@"JBSWY3DPEHPK3PXP"
                                                accountName:@"alice@example.com"
                                                     issuer:@"GarazykPDS"];
    if (!qr || qr.length == 0) {
        XCTSkip(@"QR image generation backend not available in current test environment");
    }
#if defined(GNUSTEP)
    NSString *header = [[NSString alloc] initWithData:[qr subdataWithRange:NSMakeRange(0, MIN((NSUInteger)2, qr.length))]
                                             encoding:NSASCIIStringEncoding];
    XCTAssertEqualObjects(header, @"P4");
#else
    const uint8_t *bytes = qr.bytes;
    XCTAssertGreaterThanOrEqual(qr.length, (NSUInteger)4);
    XCTAssertEqual(bytes[0], (uint8_t)0x89);
    XCTAssertEqual(bytes[1], (uint8_t)'P');
    XCTAssertEqual(bytes[2], (uint8_t)'N');
    XCTAssertEqual(bytes[3], (uint8_t)'G');
#endif
}

- (void)testGenerateSoftwareTokenProducesSixDigits {
    NSData *secretData = [@"12345678901234567890" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secretData];
    NSString *token = [service generateSoftwareToken];
    XCTAssertNotNil(token);
    XCTAssertEqual(token.length, 6u);
}

- (void)testGenerateTOTPTokenUsesYubiManagerWhenAvailable {
    NSData *secretData = [@"12345678901234567890" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secretData];
    TOTPStubYubiManager *stub = [[TOTPStubYubiManager alloc] init];
    stub.tokenToReturn = @"123456";
    [service setValue:stub forKey:@"yubiKeyManager"];

    NSError *error = nil;
    NSString *token = [service generateTOTPToken:&error];
    XCTAssertEqualObjects(token, @"123456");
    XCTAssertNil(error);
}

- (void)testYubiKeyManagerSoftwareModeBehaviors {
    YubiKeyOATHManager *manager = [[YubiKeyOATHManager alloc] init];
    XCTAssertFalse(manager.isHardwareAvailable);
    XCTAssertEqual(manager.connectionState, YubiKeyConnectionStateDisconnected);

    [manager startScanning];
    XCTAssertEqual(manager.connectionState, YubiKeyConnectionStateDisconnected);
    [manager stopScanning];
    XCTAssertEqual(manager.connectionState, YubiKeyConnectionStateDisconnected);
    [manager refreshConnection];
    XCTAssertEqual(manager.connectionState, YubiKeyConnectionStateDisconnected);
}

- (void)testYubiKeyManagerNotImplementedOperationsSetErrors {
    YubiKeyOATHManager *manager = [[YubiKeyOATHManager alloc] init];
    NSError *error = nil;
    BOOL setResult = [manager setOATHSecret:[@"secret" dataUsingEncoding:NSUTF8StringEncoding]
                                       name:@"account"
                                      error:&error];
    XCTAssertFalse(setResult);
    XCTAssertEqualObjects(error.domain, YubiKeyOATHErrorDomain);
    XCTAssertEqual(error.code, YubiKeyOATHErrorNotImplemented);

    error = nil;
    BOOL deleteResult = [manager deleteCredentialWithName:@"account" error:&error];
    XCTAssertFalse(deleteResult);
    XCTAssertEqual(error.code, YubiKeyOATHErrorNotImplemented);

    error = nil;
    BOOL resetResult = [manager resetAllCredentialsWithError:&error];
    XCTAssertFalse(resetResult);
    XCTAssertEqual(error.code, YubiKeyOATHErrorNotImplemented);

    error = nil;
    NSArray *credentials = [manager listCredentialsWithError:&error];
    XCTAssertNotNil(credentials);
    XCTAssertEqual(credentials.count, 0u);
    XCTAssertNil(error);
}

@end
