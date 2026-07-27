// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "Lexicon/ATProtoLexiconError.h"

@interface ATProtoLexiconValidatorTests : XCTestCase
@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) ATProtoLexiconValidator *validator;
@end

@implementation ATProtoLexiconValidatorTests

- (void)setUp {
    [super setUp];
    self.registry = [[ATProtoLexiconRegistry alloc] init];

    // Register a test schema for app.bsky.feed.post
    NSError *error = nil;
    ATProtoLexiconSchema *postSchema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{
            @"main": @{
                @"type": @"record",
                @"key": @"tid",
                @"record": @{
                    @"type": @"object",
                    @"required": @[@"text", @"createdAt"],
                    @"nullable": @[@"embed"],
                    @"properties": @{
                        @"text": @{@"type": @"string", @"maxLength": @300, @"minLength": @1},
                        @"createdAt": @{@"type": @"string", @"format": @"datetime"},
                        @"embed": @{@"type": @"union", @"refs": @[@"app.bsky.feed.defs#embed"], @"closed": @YES},
                        @"langs": @{@"type": @"array", @"items": @{@"type": @"string", @"format": @"language"}, @"maxItems": @5},
                        @"replyCount": @{@"type": @"integer", @"minimum": @0},
                        @"labels": @{@"type": @"object", @"properties": @{
                            @"values": @{@"type": @"array", @"items": @{@"type": @"string"}}
                        }}
                    }
                }
            }
        }
    } error:&error];
    XCTAssertNotNil(postSchema);
    [self.registry registerSchema:postSchema];

    self.validator = [[ATProtoLexiconValidator alloc] initWithRegistry:self.registry];
}

- (void)tearDown {
    [self.registry clearCache];
    [super tearDown];
}

#pragma mark - validateRecord:collection:mode:error:

- (void)testValidate_ValidRecord_Passes {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello, world!",
        @"createdAt": @"2024-01-15T10:00:00Z"
    };

    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testValidate_ModeOff_AlwaysPasses {
    NSDictionary *record = @{@"$type": @"invalid"};
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.invalid"
                                           mode:ATProtoValidationModeOff
                                          error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testValidate_NonDictionaryRecord_ReturnsError {
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:(id)@"not a dict"
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_MissingDollarType_ReturnsError {
    NSDictionary *record = @{@"text": @"Hello"};
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorMissingTypeField);
}

- (void)testValidate_TypeMismatch_ReturnsError {
    NSDictionary *record = @{@"$type": @"app.bsky.feed.like", @"text": @"Hello"};
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorTypeMismatch);
}

- (void)testValidate_TypeWithHash_MatchesCollection {
    // $type = "app.bsky.feed.post#main" should match collection "app.bsky.feed.post"
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post#main",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testValidate_MissingRequiredField_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello"
        // missing createdAt
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorMissingRequiredField);
}

- (void)testValidate_StringExceedsMaxLength_ReturnsError {
    NSString *longText = [@"" stringByPaddingToLength:301 withString:@"a" startingAtIndex:0];
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": longText,
        @"createdAt": @"2024-01-15T10:00:00Z"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorConstraintViolation);
}

- (void)testValidate_StringBelowMinLength_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"",  // empty string violates minLength: 1
        @"createdAt": @"2024-01-15T10:00:00Z"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_IntegerBelowMinimum_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z",
        @"replyCount": @(-1)
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_InvalidDatetimeFormat_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"not-a-datetime"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_UnknownSchema_RequiredMode_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.unknown",
        @"text": @"Hello"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.unknown"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorSchemaNotFound);
}

- (void)testValidate_UnknownSchema_OptimisticMode_Passes {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.unknown",
        @"text": @"Hello"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.unknown"
                                           mode:ATProtoValidationModeOptimistic
                                          error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testValidate_ArrayExceedsMaxItems_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z",
        @"langs": @[@"en", @"fr", @"de", @"es", @"ja", @"zh"]  // 6 items exceeds maxItems:5
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_InvalidLanguageTag_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z",
        @"langs": @[@"invalid!!"]  // not a valid BCP-47 tag
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_BooleanNotBool_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z"
    };
    // Integer in place of a boolean property — should fail type check
    // The schema doesn't have a boolean property, so let's test with
    // a property that expects object but gets string instead
    NSDictionary *recordBad = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z",
        @"labels": @"not-an-object"  // labels expects object
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:recordBad
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_WithAdditionalProperties_Passes {
    // Unknown properties should be ignored (forward compatibility)
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello",
        @"createdAt": @"2024-01-15T10:00:00Z",
        @"futureField": @"some-value"  // not in schema
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertTrue(valid);
    XCTAssertNil(error);
}

- (void)testValidate_WithNullInNonNullableField_ReturnsError {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": [NSNull null],  // text is not nullable
        @"createdAt": @"2024-01-15T10:00:00Z"
    };
    NSError *error = nil;
    BOOL valid = [self.validator validateRecord:record
                                     collection:@"app.bsky.feed.post"
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testValidate_NilRecordNilError_DoesNotCrash {
    BOOL valid = [self.validator validateRecord:nil
                                     collection:@"test"
                                           mode:ATProtoValidationModeOff
                                          error:NULL];
    // With mode off, returns YES
    XCTAssertTrue(valid);
}

@end
