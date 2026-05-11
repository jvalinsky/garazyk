// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

    NSString *base = @"Garazyk/Tests/fixtures/atproto-interop-tests";
    NSArray<NSString *> *candidates = @[
        [[base stringByAppendingPathComponent:relativePath] copy],
        [[@"Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [bundlePath stringByAppendingPathComponent:relativePath],
        [[@"../Garazyk/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"../../Garazyk/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
        [[@"../../../Garazyk/Tests/fixtures/atproto-interop-tests" stringByAppendingPathComponent:relativePath] copy],
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
        if (line.length == 0) return;
        if ([line hasPrefix:@"#"]) return;
        
        // Don't trim - spaces might be part of the invalid test case
        [lines addObject:line];
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
    // XCTAssertEqual(actual, expected);
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
    // XCTAssertEqual(actual, expected);
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
    // XCTAssertEqual(actual, expected);
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

        NSData *expectedCBOR = InteropBase64URLDecode(cborBase64);
        XCTAssertNotNil(expectedCBOR, @"Failed to decode expected CBOR base64 in fixture: %@", fixture[@"name"]);
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

/**
 * Bug Condition Exploration Test for DAG-CBOR Canonical Encoding
 * 
 * **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**
 * 
 * This test MUST FAIL on unfixed code to confirm the bug exists.
 * The bug: ATProtoCBORSerialization sorts map keys by string value instead of
 * by CBOR-encoded byte representation (length-first, then lexicographic).
 * 
 * When this test FAILS, it proves the bug exists and provides counterexamples.
 * When this test PASSES (after the fix), it confirms correct canonical encoding.
 */
- (void)testDAGCBORCanonicalKeyOrdering {
    // Test case 1: Keys that sort differently under string vs CBOR-byte comparison
    // String sort: ["$type", "createdAt", "text"]
    // CBOR byte sort: ["text", "$type", "createdAt"] (4-byte, 5-byte, 9-byte keys)
    NSDictionary *record1 = @{
        @"text": @"hello world",
        @"$type": @"app.bsky.feed.post",
        @"createdAt": @"2024-01-01T00:00:00Z"
    };
    
    NSError *error1 = nil;
    NSData *cbor1 = [ATProtoCBORSerialization encodeDataWithJSONObject:record1 error:&error1];
    XCTAssertNotNil(cbor1, @"Failed to encode record1: %@", error1);
    
    // Manually verify key ordering by checking CBOR structure
    // In canonical DAG-CBOR, shorter keys must come before longer keys
    // We can verify this by checking that "text" (4 bytes encoded) comes before "$type" (5 bytes)
    // and "$type" comes before "createdAt" (9 bytes)
    
    // Test case 2: Simple case from design doc
    // String sort: ["aa", "z"]
    // CBOR byte sort: ["z", "aa"] (1-byte key before 2-byte key)
    NSDictionary *record2 = @{
        @"z": @(1),
        @"aa": @(2)
    };
    
    NSError *error2 = nil;
    NSData *cbor2 = [ATProtoCBORSerialization encodeDataWithJSONObject:record2 error:&error2];
    XCTAssertNotNil(cbor2, @"Failed to encode record2: %@", error2);
    
    // Expected CBOR for {"z": 1, "aa": 2} with canonical ordering:
    // Map with 2 entries: 0xA2
    // Key "z" (1 char): 0x61 0x7A
    // Value 1: 0x01
    // Key "aa" (2 chars): 0x62 0x61 0x61
    // Value 2: 0x02
    // Total: A2 61 7A 01 62 61 61 02
    NSData *expectedCBOR2 = [NSData dataWithBytes:(unsigned char[]){0xA2, 0x61, 0x7A, 0x01, 0x62, 0x61, 0x61, 0x02} length:8];
    
    XCTAssertEqualObjects(cbor2, expectedCBOR2, 
        @"CBOR encoding does not match canonical DAG-CBOR. "
        @"Expected keys sorted by byte length (z before aa), "
        @"but got incorrect ordering. "
        @"This confirms the bug: keys are sorted by string value instead of CBOR-encoded byte length.");
    
    // Test case 3: Use actual AT Protocol test fixtures
    // Re-run the data model fixtures test but with explicit failure documentation
    NSString *path = [self interopFixturePath:@"data-model/data-model-fixtures.json"];
    if (!path) {
        XCTFail(@"Could not find data-model fixtures");
        return;
    }
    
    NSData *fixtureData = [NSData dataWithContentsOfFile:path];
    if (!fixtureData) {
        XCTFail(@"Could not load data-model fixtures");
        return;
    }
    
    NSError *jsonError = nil;
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:&jsonError];
    XCTAssertNotNil(fixtures, @"Failed to parse fixtures: %@", jsonError);
    
    NSInteger failureCount = 0;
    NSMutableArray *failedFixtures = [NSMutableArray array];
    
    for (NSDictionary *fixture in fixtures) {
        if (![fixture isKindOfClass:[NSDictionary class]]) continue;
        
        NSDictionary *json = fixture[@"json"];
        NSString *cborBase64 = fixture[@"cbor_base64"];
        NSString *expectedCID = fixture[@"cid"];
        
        if (!json || !cborBase64 || !expectedCID) continue;
        
        NSData *expectedCBOR = [[NSData alloc] initWithBase64EncodedString:cborBase64 options:0];
        if (!expectedCBOR) continue;
        
        NSError *encodeError = nil;
        NSData *actualCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:json error:&encodeError];
        
        if (!actualCBOR) {
            [failedFixtures addObject:@{@"error": @"encoding failed", @"json": json}];
            failureCount++;
            continue;
        }
        
        // Check if CBOR bytes match
        if (![actualCBOR isEqualToData:expectedCBOR]) {
            CID *actualCID = [CID cidWithDigest:[CID sha256Digest:actualCBOR] codec:0x71];
            [failedFixtures addObject:@{
                @"expectedCID": expectedCID,
                @"actualCID": actualCID.stringValue ?: @"<nil>",
                @"cborMatch": @NO,
                @"json": json
            }];
            failureCount++;
        } else {
            // Even if CBOR matches, verify CID
            CID *actualCID = [CID cidWithDigest:[CID sha256Digest:actualCBOR] codec:0x71];
            if (![actualCID.stringValue isEqualToString:expectedCID]) {
                [failedFixtures addObject:@{
                    @"expectedCID": expectedCID,
                    @"actualCID": actualCID.stringValue ?: @"<nil>",
                    @"cborMatch": @YES,
                    @"cidMatch": @NO,
                    @"json": json
                }];
                failureCount++;
            }
        }
    }
    
    // Document the failures
    if (failureCount > 0) {
        NSLog(@"\n=== DAG-CBOR Canonical Encoding Bug Detected ===");
        NSLog(@"Failed %ld out of %lu test fixtures", (long)failureCount, (unsigned long)fixtures.count);
        NSLog(@"\nCounterexamples:");
        for (NSDictionary *failure in failedFixtures) {
            NSLog(@"  - Expected CID: %@", failure[@"expectedCID"] ?: @"N/A");
            NSLog(@"    Actual CID: %@", failure[@"actualCID"] ?: @"N/A");
            NSLog(@"    CBOR Match: %@", failure[@"cborMatch"] ?: @"N/A");
            NSLog(@"    JSON: %@", failure[@"json"]);
            NSLog(@"");
        }
        NSLog(@"=== End Bug Report ===\n");
    }
    
    XCTAssertEqual(failureCount, 0, 
        @"DAG-CBOR canonical encoding bug detected: %ld fixtures failed. "
        @"Keys are being sorted by string value instead of CBOR-encoded byte length. "
        @"See log output above for counterexamples.", (long)failureCount);
}

@end
