// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconConstraints.h"
#import "Lexicon/ATProtoLexiconDef.h"

@interface ATProtoLexiconConstraintsTests : XCTestCase
@end

@implementation ATProtoLexiconConstraintsTests

#pragma mark - StringConstraints

- (void)testStringConstraints_DefaultValues {
    ATProtoLexiconStringConstraints *c = [[ATProtoLexiconStringConstraints alloc] init];
    XCTAssertNil(c.format);
    XCTAssertNil(c.maxLength);
    XCTAssertNil(c.minLength);
    XCTAssertNil(c.maxGraphemes);
    XCTAssertNil(c.minGraphemes);
    XCTAssertNil(c.enumValues);
    XCTAssertNil(c.knownValues);
    XCTAssertNil(c.constValue);
    XCTAssertNil(c.defaultValue);
}

- (void)testStringConstraints_WithFormat {
    ATProtoLexiconStringConstraints *c = [[ATProtoLexiconStringConstraints alloc] init];
    c.format = @"did";
    c.maxLength = @100;
    c.minLength = @1;
    XCTAssertEqualObjects(c.format, @"did");
    XCTAssertEqualObjects(c.maxLength, @100);
    XCTAssertEqualObjects(c.minLength, @1);
}

- (void)testStringConstraints_WithEnum {
    ATProtoLexiconStringConstraints *c = [[ATProtoLexiconStringConstraints alloc] init];
    c.enumValues = @[@"a", @"b", @"c"];
    c.constValue = @"fixed";
    XCTAssertEqualObjects(c.enumValues, (@[@"a", @"b", @"c"]));
    XCTAssertEqualObjects(c.constValue, @"fixed");
}

#pragma mark - IntegerConstraints

- (void)testIntegerConstraints_DefaultValues {
    ATProtoLexiconIntegerConstraints *c = [[ATProtoLexiconIntegerConstraints alloc] init];
    XCTAssertNil(c.minimum);
    XCTAssertNil(c.maximum);
    XCTAssertNil(c.enumValues);
    XCTAssertNil(c.constValue);
    XCTAssertNil(c.defaultValue);
}

- (void)testIntegerConstraints_WithRange {
    ATProtoLexiconIntegerConstraints *c = [[ATProtoLexiconIntegerConstraints alloc] init];
    c.minimum = @0;
    c.maximum = @100;
    c.defaultValue = @50;
    XCTAssertEqualObjects(c.minimum, @0);
    XCTAssertEqualObjects(c.maximum, @100);
    XCTAssertEqualObjects(c.defaultValue, @50);
}

- (void)testIntegerConstraints_WithEnum {
    ATProtoLexiconIntegerConstraints *c = [[ATProtoLexiconIntegerConstraints alloc] init];
    c.enumValues = @[@1, @2, @3];
    c.constValue = @1;
    XCTAssertEqualObjects(c.enumValues, (@[@1, @2, @3]));
    XCTAssertEqualObjects(c.constValue, @1);
}

#pragma mark - BooleanConstraints

- (void)testBooleanConstraints_DefaultValues {
    ATProtoLexiconBooleanConstraints *c = [[ATProtoLexiconBooleanConstraints alloc] init];
    XCTAssertNil(c.constValue);
    XCTAssertNil(c.defaultValue);
}

- (void)testBooleanConstraints_WithValues {
    ATProtoLexiconBooleanConstraints *c = [[ATProtoLexiconBooleanConstraints alloc] init];
    c.constValue = @YES;
    c.defaultValue = @NO;
    XCTAssertEqualObjects(c.constValue, @YES);
    XCTAssertEqualObjects(c.defaultValue, @NO);
}

#pragma mark - BytesConstraints

- (void)testBytesConstraints_DefaultValues {
    ATProtoLexiconBytesConstraints *c = [[ATProtoLexiconBytesConstraints alloc] init];
    XCTAssertNil(c.minLength);
    XCTAssertNil(c.maxLength);
}

- (void)testBytesConstraints_WithRange {
    ATProtoLexiconBytesConstraints *c = [[ATProtoLexiconBytesConstraints alloc] init];
    c.minLength = @1;
    c.maxLength = @(1024 * 1024);
    XCTAssertEqualObjects(c.minLength, @1);
    XCTAssertEqualObjects(c.maxLength, @(1024 * 1024));
}

#pragma mark - ArrayConstraints

- (void)testArrayConstraints_DefaultValues {
    ATProtoLexiconArrayConstraints *c = [[ATProtoLexiconArrayConstraints alloc] init];
    XCTAssertNil(c.items);
    XCTAssertNil(c.minLength);
    XCTAssertNil(c.maxLength);
}

- (void)testArrayConstraints_WithItemsAndRange {
    ATProtoLexiconArrayConstraints *c = [[ATProtoLexiconArrayConstraints alloc] init];
    c.items = [[ATProtoLexiconDef alloc] init];
    c.minLength = @0;
    c.maxLength = @50;
    XCTAssertNotNil(c.items);
    XCTAssertEqualObjects(c.minLength, @0);
    XCTAssertEqualObjects(c.maxLength, @50);
}

#pragma mark - ObjectConstraints

- (void)testObjectConstraints_DefaultValues {
    ATProtoLexiconObjectConstraints *c = [[ATProtoLexiconObjectConstraints alloc] init];
    XCTAssertNil(c.properties);
    XCTAssertNil(c.required);
    XCTAssertNil(c.nullable);
}

- (void)testObjectConstraints_WithProperties {
    ATProtoLexiconObjectConstraints *c = [[ATProtoLexiconObjectConstraints alloc] init];
    c.properties = @{@"name": [[ATProtoLexiconDef alloc] init]};
    c.required = @[@"name"];
    c.nullable = @[@"description"];
    XCTAssertEqual(c.properties.count, (NSUInteger)1);
    XCTAssertEqualObjects(c.required, (@[@"name"]));
    XCTAssertEqualObjects(c.nullable, (@[@"description"]));
}

#pragma mark - BlobConstraints

- (void)testBlobConstraints_DefaultValues {
    ATProtoLexiconBlobConstraints *c = [[ATProtoLexiconBlobConstraints alloc] init];
    XCTAssertNil(c.accept);
    XCTAssertNil(c.maxSize);
}

- (void)testBlobConstraints_WithValues {
    ATProtoLexiconBlobConstraints *c = [[ATProtoLexiconBlobConstraints alloc] init];
    c.accept = @[@"image/*", @"video/*"];
    c.maxSize = @(10 * 1024 * 1024);
    XCTAssertEqualObjects(c.accept, (@[@"image/*", @"video/*"]));
    XCTAssertEqualObjects(c.maxSize, @(10 * 1024 * 1024));
}

#pragma mark - UnionConstraints

- (void)testUnionConstraints_DefaultValues {
    ATProtoLexiconUnionConstraints *c = [[ATProtoLexiconUnionConstraints alloc] init];
    XCTAssertNil(c.refs);
    XCTAssertFalse(c.closed);
}

- (void)testUnionConstraints_WithRefs {
    ATProtoLexiconUnionConstraints *c = [[ATProtoLexiconUnionConstraints alloc] init];
    c.refs = @[@"app.bsky.feed.defs#postView"];
    c.closed = YES;
    XCTAssertEqualObjects(c.refs, (@[@"app.bsky.feed.defs#postView"]));
    XCTAssertTrue(c.closed);
}

#pragma mark - RefConstraints

- (void)testRefConstraints_DefaultValues {
    ATProtoLexiconRefConstraints *c = [[ATProtoLexiconRefConstraints alloc] init];
    XCTAssertNil(c.ref);
}

- (void)testRefConstraints_WithRef {
    ATProtoLexiconRefConstraints *c = [[ATProtoLexiconRefConstraints alloc] init];
    c.ref = @"app.bsky.feed.defs#postView";
    XCTAssertEqualObjects(c.ref, @"app.bsky.feed.defs#postView");
}

@end
