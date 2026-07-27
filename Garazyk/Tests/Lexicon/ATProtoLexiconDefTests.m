// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconDef.h"
#import "Lexicon/ATProtoLexiconConstraints.h"

@interface ATProtoLexiconDefTests : XCTestCase
@end

@implementation ATProtoLexiconDefTests

#pragma mark - typeFromString:

- (void)testTypeFromString_Record {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"record"], ATProtoLexiconDefTypeRecord);
}

- (void)testTypeFromString_Query {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"query"], ATProtoLexiconDefTypeQuery);
}

- (void)testTypeFromString_Procedure {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"procedure"], ATProtoLexiconDefTypeProcedure);
}

- (void)testTypeFromString_Subscription {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"subscription"], ATProtoLexiconDefTypeSubscription);
}

- (void)testTypeFromString_Object {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"object"], ATProtoLexiconDefTypeObject);
}

- (void)testTypeFromString_Array {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"array"], ATProtoLexiconDefTypeArray);
}

- (void)testTypeFromString_String {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"string"], ATProtoLexiconDefTypeString);
}

- (void)testTypeFromString_Integer {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"integer"], ATProtoLexiconDefTypeInteger);
}

- (void)testTypeFromString_Boolean {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"boolean"], ATProtoLexiconDefTypeBoolean);
}

- (void)testTypeFromString_Bytes {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"bytes"], ATProtoLexiconDefTypeBytes);
}

- (void)testTypeFromString_Blob {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"blob"], ATProtoLexiconDefTypeBlob);
}

- (void)testTypeFromString_Union {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"union"], ATProtoLexiconDefTypeUnion);
}

- (void)testTypeFromString_Ref {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"ref"], ATProtoLexiconDefTypeRef);
}

- (void)testTypeFromString_Token {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"token"], ATProtoLexiconDefTypeToken);
}

- (void)testTypeFromString_Unknown {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"unknown"], ATProtoLexiconDefTypeUnknown);
}

- (void)testTypeFromString_CIDLink {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"cid-link"], ATProtoLexiconDefTypeCIDLink);
}

- (void)testTypeFromString_PermissionSet {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"permission-set"], ATProtoLexiconDefTypePermissionSet);
}

- (void)testTypeFromString_Unrecognized {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"nonexistent"], (ATProtoLexiconDefType)-1);
}

- (void)testTypeFromString_CaseSensitive {
    // Type map is case-sensitive
    XCTAssertEqual([ATProtoLexiconDef typeFromString:@"String"], (ATProtoLexiconDefType)-1);
}

- (void)testTypeFromString_Nil {
    XCTAssertEqual([ATProtoLexiconDef typeFromString:nil], (ATProtoLexiconDefType)-1);
}

#pragma mark - stringFromType:

- (void)testStringFromType_Record {
    XCTAssertEqualObjects([ATProtoLexiconDef stringFromType:ATProtoLexiconDefTypeRecord], @"record");
}

- (void)testStringFromType_String {
    XCTAssertEqualObjects([ATProtoLexiconDef stringFromType:ATProtoLexiconDefTypeString], @"string");
}

- (void)testStringFromType_AllTypesReturnNonNil {
    for (NSInteger i = ATProtoLexiconDefTypeRecord; i <= ATProtoLexiconDefTypeParams; i++) {
        NSString *str = [ATProtoLexiconDef stringFromType:(ATProtoLexiconDefType)i];
        XCTAssertNotNil(str);
        XCTAssertTrue(str.length > 0);
    }
}

#pragma mark - defFromJSONObject:error:

- (void)testDefFromJSON_NilInput_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:nil error:&error];
    XCTAssertNil(def);
    XCTAssertNotNil(error);
}

- (void)testDefFromJSON_NonDictionaryInput_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:@[@"not", @"dict"] error:&error];
    XCTAssertNil(def);
    XCTAssertNotNil(error);
}

- (void)testDefFromJSON_MissingType_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:@{} error:&error];
    XCTAssertNil(def);
    XCTAssertNotNil(error);
}

- (void)testDefFromJSON_StringType_ReturnsDef {
    NSError *error = nil;
    NSDictionary *json = @{@"type": @"string", @"description": @"A test string"};
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeString);
    XCTAssertEqualObjects(def.lexiconDescription, @"A test string");
}

- (void)testDefFromJSON_IntegerType_ReturnsDefWithConstraints {
    NSError *error = nil;
    NSDictionary *json = @{@"type": @"integer", @"minimum": @0, @"maximum": @100};
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeInteger);
    XCTAssertTrue([def.constraints isKindOfClass:[ATProtoLexiconIntegerConstraints class]]);
    ATProtoLexiconIntegerConstraints *c = (ATProtoLexiconIntegerConstraints *)def.constraints;
    XCTAssertEqualObjects(c.minimum, @0);
    XCTAssertEqualObjects(c.maximum, @100);
}

- (void)testDefFromJSON_ObjectType_ReturnsDefWithProperties {
    NSError *error = nil;
    NSDictionary *json = @{
        @"type": @"object",
        @"properties": @{
            @"name": @{@"type": @"string"},
            @"age": @{@"type": @"integer"}
        },
        @"required": @[@"name"]
    };
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeObject);
    XCTAssertTrue([def.constraints isKindOfClass:[ATProtoLexiconObjectConstraints class]]);
    ATProtoLexiconObjectConstraints *c = (ATProtoLexiconObjectConstraints *)def.constraints;
    XCTAssertEqual(c.properties.count, (NSUInteger)2);
    XCTAssertEqualObjects(c.required, @[@"name"]);
}

- (void)testDefFromJSON_ArrayType_ReturnsDefWithItems {
    NSError *error = nil;
    NSDictionary *json = @{
        @"type": @"array",
        @"items": @{@"type": @"string"},
        @"minItems": @1,
        @"maxItems": @10
    };
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeArray);
    XCTAssertTrue([def.constraints isKindOfClass:[ATProtoLexiconArrayConstraints class]]);
    ATProtoLexiconArrayConstraints *c = (ATProtoLexiconArrayConstraints *)def.constraints;
    XCTAssertNotNil(c.items);
    XCTAssertEqual(c.items.type, ATProtoLexiconDefTypeString);
    XCTAssertEqualObjects(c.minLength, @1);
    XCTAssertEqualObjects(c.maxLength, @10);
}

- (void)testDefFromJSON_BlobType_ReturnsDefWithConstraints {
    NSError *error = nil;
    NSDictionary *json = @{
        @"type": @"blob",
        @"accept": @[@"image/*"],
        @"maxSize": @(1024 * 1024)
    };
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeBlob);
    ATProtoLexiconBlobConstraints *c = (ATProtoLexiconBlobConstraints *)def.constraints;
    XCTAssertEqualObjects(c.accept, @[@"image/*"]);
    XCTAssertEqualObjects(c.maxSize, @(1024 * 1024));
}

- (void)testDefFromJSON_UnionType_ReturnsDefWithRefs {
    NSError *error = nil;
    NSDictionary *json = @{
        @"type": @"union",
        @"refs": @[@"app.bsky.feed.defs#postView", @"app.bsky.feed.defs#replyView"],
        @"closed": @YES
    };
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeUnion);
    ATProtoLexiconUnionConstraints *c = (ATProtoLexiconUnionConstraints *)def.constraints;
    XCTAssertEqualObjects(c.refs, (@[@"app.bsky.feed.defs#postView", @"app.bsky.feed.defs#replyView"]));
    XCTAssertTrue(c.closed);
}

- (void)testDefFromJSON_RefType_ReturnsDefWithRef {
    NSError *error = nil;
    NSDictionary *json = @{@"type": @"ref", @"ref": @"app.bsky.feed.defs#postView"};
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeRef);
    ATProtoLexiconRefConstraints *c = (ATProtoLexiconRefConstraints *)def.constraints;
    XCTAssertEqualObjects(c.ref, @"app.bsky.feed.defs#postView");
}

- (void)testDefFromJSON_BooleanType_ReturnsDefWithConst {
    NSError *error = nil;
    NSDictionary *json = @{@"type": @"boolean", @"const": @YES};
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeBoolean);
    ATProtoLexiconBooleanConstraints *c = (ATProtoLexiconBooleanConstraints *)def.constraints;
    XCTAssertEqualObjects(c.constValue, @YES);
}

- (void)testDefFromJSON_StringWithEnum_ReturnsDefWithConstraints {
    NSError *error = nil;
    NSDictionary *json = @{
        @"type": @"string",
        @"enum": @[@"left", @"right"],
        @"maxLength": @100,
        @"minLength": @1
    };
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNotNil(def);
    XCTAssertNil(error);
    XCTAssertEqual(def.type, ATProtoLexiconDefTypeString);
    ATProtoLexiconStringConstraints *c = (ATProtoLexiconStringConstraints *)def.constraints;
    XCTAssertEqualObjects(c.enumValues, (@[@"left", @"right"]));
    XCTAssertEqualObjects(c.maxLength, @100);
    XCTAssertEqualObjects(c.minLength, @1);
}

- (void)testDefFromJSON_UnknownType_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *json = @{@"type": @"widget"};
    ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:json error:&error];
    XCTAssertNil(def);
    XCTAssertNotNil(error);
}

@end
