#import <XCTest/XCTest.h>

#import "Auth/CryptoUtils.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCDIDKey.h"

@interface PLCAuditor (AtprotoInteropSignatureTesting)
- (BOOL)verifyP256Signature:(NSData *)rawSig hash:(NSData *)hash compressedPublicKey:(NSData *)pubKey;
@end

@interface AtprotoInteropFixturesTests : XCTestCase
@end

@implementation AtprotoInteropFixturesTests

- (nullable NSString *)interopFixturePath:(NSString *)relativePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath;
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle resourcePath];

    NSString *base = @"ATProtoPDS/Tests/fixtures/atproto-interop-tests";
    NSArray<NSString *> *candidates = @[
        [[base stringByAppendingPathComponent:relativePath] copy],
        [[@"Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [bundlePath stringByAppendingPathComponent:relativePath],
        [[@"../ATProtoPDS/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"../../ATProtoPDS/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"../../../ATProtoPDS/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
    ];

    for (NSString *candidate in candidates) {
        if (!candidate || candidate.length == 0) {
            continue;
        }

        NSString *path = [candidate hasPrefix:@"/"] ? candidate : [cwd stringByAppendingPathComponent:candidate];
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }

    return nil;
}

- (NSArray<NSString *> *)nonCommentLinesFromFixture:(NSString *)relativePath {
    NSString *path = [self interopFixturePath:relativePath];
    XCTAssertNotNil(path, @"Fixture not found: %@", relativePath);
    if (!path) return @[];

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(contents, @"Failed to read fixture %@: %@", relativePath, error);
    if (!contents) return @[];

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [contents enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        (void)stop;
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) return;
        if ([trimmed hasPrefix:@"#"]) return;
        [lines addObject:trimmed];
    }];
    return [lines copy];
}

static NSData *InteropBase64URLDecode(NSString *string) {
    if (!string || ![string isKindOfClass:[NSString class]]) {
        return nil;
    }
    if ([string hasSuffix:@"="]) {
        return nil;
    }
    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:(4 - remainder)]];
    }
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

- (void)testInteropHandleSyntaxFixtures {
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/handle_syntax_valid.txt"];
    for (NSString *handle in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateHandle:handle error:&error];
        XCTAssertTrue(ok, @"Expected valid handle per fixtures: %@ (error=%@)", handle, error);
    }

    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/handle_syntax_invalid.txt"];
    for (NSString *handle in invalid) {
        BOOL ok = [ATProtoValidator validateHandle:handle error:nil];
        XCTAssertFalse(ok, @"Expected invalid handle per fixtures: %@", handle);
    }
}

- (void)testInteropTIDSyntaxFixtures {
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/tid_syntax_valid.txt"];
    for (NSString *tidStr in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateTID:tidStr error:&error];
        XCTAssertTrue(ok, @"Expected valid TID per fixtures: %@ (error=%@)", tidStr, error);
        XCTAssertNotNil([TID tidFromString:tidStr], @"TID class should accept fixture-valid TID: %@", tidStr);
    }

    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/tid_syntax_invalid.txt"];
    for (NSString *tidStr in invalid) {
        BOOL ok = [ATProtoValidator validateTID:tidStr error:nil];
        XCTAssertFalse(ok, @"Expected invalid TID per fixtures: %@", tidStr);
        XCTAssertNil([TID tidFromString:tidStr], @"TID class should reject fixture-invalid TID: %@", tidStr);
    }
}

- (void)testInteropSignatureFixtures {
    NSString *path = [self interopFixturePath:@"crypto/signature-fixtures.json"];
    XCTAssertNotNil(path);
    if (!path) return;

    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data);
    if (!data) return;

    NSError *jsonError = nil;
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    XCTAssertNotNil(fixtures, @"Failed to parse signature fixtures: %@", jsonError);
    if (![fixtures isKindOfClass:[NSArray class]]) return;

    PLCAuditor *p256Auditor = [[PLCAuditor alloc] initWithStore:(id)nil];

    for (NSDictionary *fixture in fixtures) {
        if (![fixture isKindOfClass:[NSDictionary class]]) continue;

        NSString *comment = fixture[@"comment"] ?: @"<no comment>";
        NSString *messageBase64 = fixture[@"messageBase64"];
        NSString *algorithm = fixture[@"algorithm"];
        NSString *publicKeyDid = fixture[@"publicKeyDid"];
        NSString *signatureBase64 = fixture[@"signatureBase64"];
        NSNumber *validSignature = fixture[@"validSignature"];

        XCTAssertNotNil(messageBase64, @"Missing messageBase64 in fixture: %@", comment);
        XCTAssertNotNil(algorithm, @"Missing algorithm in fixture: %@", comment);
        XCTAssertNotNil(publicKeyDid, @"Missing publicKeyDid in fixture: %@", comment);
        XCTAssertNotNil(signatureBase64, @"Missing signatureBase64 in fixture: %@", comment);
        XCTAssertNotNil(validSignature, @"Missing validSignature in fixture: %@", comment);
        if (!messageBase64 || !algorithm || !publicKeyDid || !signatureBase64 || !validSignature) continue;

        NSData *message = InteropBase64URLDecode(messageBase64);
        XCTAssertNotNil(message, @"Failed to decode messageBase64 in fixture: %@", comment);
        if (!message) continue;

        NSData *hash = [CryptoUtils sha256:message];
        XCTAssertEqual(hash.length, (NSUInteger)32);

        NSData *sig = [[NSData alloc] initWithBase64EncodedString:signatureBase64 options:0];
        if (!sig) {
            // Some fixtures might use base64url.
            sig = InteropBase64URLDecode(signatureBase64);
        }

        NSError *keyError = nil;
        PLCDIDKey *didKey = [PLCDIDKey parseFromString:publicKeyDid error:&keyError];
        XCTAssertNotNil(didKey, @"Failed to parse did:key in fixture: %@ (error=%@)", comment, keyError);
        if (!didKey) continue;

        BOOL verified = NO;
        if ([algorithm isEqualToString:@"ES256K"]) {
            verified = [[Secp256k1 shared] verifySignature:sig ?: [NSData data]
                                                  forHash:hash
                                            withPublicKey:didKey.publicKeyBytes
                                                    error:nil];
        } else if ([algorithm isEqualToString:@"ES256"]) {
            verified = [p256Auditor verifyP256Signature:sig ?: [NSData data]
                                                   hash:hash
                                     compressedPublicKey:didKey.publicKeyBytes];
        } else {
            XCTFail(@"Unsupported algorithm in fixture: %@ (%@)", algorithm, comment);
            continue;
        }

        XCTAssertEqual(verified, validSignature.boolValue, @"Signature fixture mismatch: %@", comment);
    }
}

- (void)testInteropDataModelFixtures {
    NSString *path = [self interopFixturePath:@"data-model/data-model-fixtures.json"];
    XCTAssertNotNil(path);
    if (!path) return;

    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data);
    if (!data) return;

    NSError *jsonError = nil;
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    XCTAssertNotNil(fixtures, @"Failed to parse data-model fixtures: %@", jsonError);
    if (![fixtures isKindOfClass:[NSArray class]]) return;

    for (NSDictionary *fixture in fixtures) {
        if (![fixture isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *json = fixture[@"json"];
        NSString *cborBase64 = fixture[@"cbor_base64"];
        NSString *expectedCID = fixture[@"cid"];
        XCTAssertNotNil(json);
        XCTAssertNotNil(cborBase64);
        XCTAssertNotNil(expectedCID);
        if (!json || !cborBase64 || !expectedCID) continue;

        NSData *expectedCBOR = [[NSData alloc] initWithBase64EncodedString:cborBase64 options:0];
        XCTAssertNotNil(expectedCBOR);
        if (!expectedCBOR) continue;

        NSError *encodeError = nil;
        NSData *actualCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:json error:&encodeError];
        XCTAssertNotNil(actualCBOR, @"Failed to encode fixture JSON to CBOR: %@", encodeError);
        if (!actualCBOR) continue;

        XCTAssertEqualObjects(actualCBOR, expectedCBOR, @"CBOR bytes mismatch for data-model fixture");

        CID *cid = [CID cidWithDigest:[CID sha256Digest:actualCBOR] codec:0x71];
        XCTAssertNotNil(cid);
        XCTAssertEqualObjects(cid.stringValue, expectedCID);
    }
}

@end
