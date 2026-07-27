// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"

@interface ATProtoLexiconSchemaTests : XCTestCase
@end

@implementation ATProtoLexiconSchemaTests

#pragma mark - schemaFromJSONObject:error:

- (void)testSchemaFromJSON_NilInput_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:nil error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSON_MissingLexicon_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"id": @"app.bsky.feed.post"
    } error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSON_MissingId_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1
    } error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSON_WrongVersion_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @2,
        @"id": @"app.bsky.feed.post"
    } error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSON_MissingDefs_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post"
    } error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSON_MinimalValid_ReturnsSchema {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"description": @"A feed post",
        @"defs": @{
            @"main": @{@"type": @"record"}
        }
    } error:&error];
    XCTAssertNotNil(schema);
    XCTAssertNil(error);
    XCTAssertEqual(schema.lexicon, 1);
    XCTAssertEqualObjects(schema.nsid, @"app.bsky.feed.post");
    XCTAssertEqualObjects(schema.schemaDescription, @"A feed post");
    XCTAssertEqual(schema.defs.count, (NSUInteger)1);
}

- (void)testSchemaFromJSON_WithMultipleDefs_ReturnsSchema {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{
            @"main": @{@"type": @"record"},
            @"view": @{@"type": @"object", @"properties": @{
                @"uri": @{@"type": @"string"}
            }}
        }
    } error:&error];
    XCTAssertNotNil(schema);
    XCTAssertNil(error);
    XCTAssertEqual(schema.defs.count, (NSUInteger)2);
}

- (void)testSchemaFromJSON_MalformedDef_ReturnsNilError {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{
            @"main": @{@"type": @"nonexistent"}
        }
    } error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

#pragma mark - schemaFromJSONData:error:

- (void)testSchemaFromJSONData_InvalidJSON_ReturnsNilError {
    NSError *error = nil;
    NSData *data = [@"{invalid json}" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];
    XCTAssertNil(schema);
    XCTAssertNotNil(error);
}

- (void)testSchemaFromJSONData_ValidJSON_ReturnsSchema {
    NSDictionary *json = @{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];
    XCTAssertNotNil(schema);
    XCTAssertNil(error);
}

#pragma mark - mainDefinition

- (void)testMainDefinition_WithMain_ReturnsDef {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:&error];
    ATProtoLexiconDef *main = [schema mainDefinition];
    XCTAssertNotNil(main);
    XCTAssertEqual(main.type, ATProtoLexiconDefTypeRecord);
}

- (void)testMainDefinition_WithoutMain_ReturnsNil {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"view": @{@"type": @"object"}}
    } error:&error];
    ATProtoLexiconDef *main = [schema mainDefinition];
    XCTAssertNil(main);
}

#pragma mark - definitionForName:

- (void)testDefinitionForName_Existing_ReturnsDef {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{
            @"main": @{@"type": @"record"},
            @"view": @{@"type": @"object"}
        }
    } error:&error];
    ATProtoLexiconDef *view = [schema definitionForName:@"view"];
    XCTAssertNotNil(view);
    XCTAssertEqual(view.type, ATProtoLexiconDefTypeObject);
}

- (void)testDefinitionForName_NonExistent_ReturnsNil {
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:&error];
    ATProtoLexiconDef *def = [schema definitionForName:@"nonexistent"];
    XCTAssertNil(def);
}

@end
