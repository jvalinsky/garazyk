#import <XCTest/XCTest.h>
#import "Core/ATProtoValidator.h"
#import "Core/TID.h"
#import "Core/CID.h"

@interface SyntaxInteropTests : XCTestCase
@end

@implementation SyntaxInteropTests

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
        if (!candidate || candidate.length == 0) continue;
        NSString *path = [candidate hasPrefix:@"/"] ? candidate : [cwd stringByAppendingPathComponent:candidate];
        if ([fm fileExistsAtPath:path]) return path;
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


- (void)testInteropDIDSyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/did_syntax_valid.txt"];
    for (NSString *did in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateDID:did error:&error];
        XCTAssertTrue(ok, @"Expected valid DID per fixtures: %@ (error=%@)", did, error);
    }
}

- (void)testInteropDIDSyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/did_syntax_invalid.txt"];
    for (NSString *did in invalid) {
        BOOL ok = [ATProtoValidator validateDID:did error:nil];
        XCTAssertFalse(ok, @"Expected invalid DID per fixtures: %@", did);
    }
}

- (void)testInteropNSIDSyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/nsid_syntax_valid.txt"];
    for (NSString *nsid in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateNSID:nsid error:&error];
        XCTAssertTrue(ok, @"Expected valid NSID per fixtures: %@ (error=%@)", nsid, error);
    }
}

- (void)testInteropNSIDSyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/nsid_syntax_invalid.txt"];
    for (NSString *nsid in invalid) {
        BOOL ok = [ATProtoValidator validateNSID:nsid error:nil];
        XCTAssertFalse(ok, @"Expected invalid NSID per fixtures: %@", nsid);
    }
}

/*
- (void)testInteropATURISyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/aturi_syntax_valid.txt"];
    for (NSString *aturi in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateATURI:aturi error:&error];
        XCTAssertTrue(ok, @"Expected valid AT-URI per fixtures: %@ (error=%@)", aturi, error);
    }
}

- (void)testInteropATURISyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/aturi_syntax_invalid.txt"];
    for (NSString *aturi in invalid) {
        BOOL ok = [ATProtoValidator validateATURI:aturi error:nil];
        XCTAssertFalse(ok, @"Expected invalid AT-URI per fixtures: %@", aturi);
    }
}
*/

- (void)testInteropCIDSyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/cid_syntax_valid.txt"];
    for (NSString *cidStr in valid) {
        CID *cid = [CID cidFromString:cidStr];
        XCTAssertNotNil(cid, @"Expected valid CID per fixtures: %@", cidStr);
        XCTAssertTrue([cid isKindOfClass:[CID class]], @"Parsed CID should be valid type");
    }
}

- (void)testInteropCIDSyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/cid_syntax_invalid.txt"];
    for (NSString *cidStr in invalid) {
        CID *cid = [CID cidFromString:cidStr];
        XCTAssertNil(cid, @"Expected invalid CID per fixtures: %@", cidStr);
    }
}

/*
- (void)testInteropRecordKeySyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/recordkey_syntax_valid.txt"];
    for (NSString *key in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateRecordKey:key error:&error];
        XCTAssertTrue(ok, @"Expected valid record key per fixtures: %@ (error=%@)", key, error);
    }
}

- (void)testInteropRecordKeySyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/recordkey_syntax_invalid.txt"];
    for (NSString *key in invalid) {
        BOOL ok = [ATProtoValidator validateRecordKey:key error:nil];
        XCTAssertFalse(ok, @"Expected invalid record key per fixtures: %@", key);
    }
}

- (void)testInteropDatetimeSyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/datetime_syntax_valid.txt"];
    for (NSString *datetime in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateDatetime:datetime error:&error];
        XCTAssertTrue(ok, @"Expected valid datetime per fixtures: %@ (error=%@)", datetime, error);
    }
}

- (void)testInteropDatetimeSyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/datetime_syntax_invalid.txt"];
    for (NSString *datetime in invalid) {
        BOOL ok = [ATProtoValidator validateDatetime:datetime error:nil];
        XCTAssertFalse(ok, @"Expected invalid datetime per fixtures: %@", datetime);
    }
}

- (void)testInteropLanguageSyntaxValid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *valid = [self nonCommentLinesFromFixture:@"syntax/language_syntax_valid.txt"];
    for (NSString *lang in valid) {
        NSError *error = nil;
        BOOL ok = [ATProtoValidator validateLanguageTag:lang error:&error];
        XCTAssertTrue(ok, @"Expected valid language tag per fixtures: %@ (error=%@)", lang, error);
    }
}

- (void)testInteropLanguageSyntaxInvalid {
    // XCTAssertEqual(actual, expected);
    NSArray<NSString *> *invalid = [self nonCommentLinesFromFixture:@"syntax/language_syntax_invalid.txt"];
    for (NSString *lang in invalid) {
        BOOL ok = [ATProtoValidator validateLanguageTag:lang error:nil];
        XCTAssertFalse(ok, @"Expected invalid language tag per fixtures: %@", lang);
    }
}
*/

@end
