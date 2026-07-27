// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconError.h"

@interface ATProtoLexiconErrorTests : XCTestCase
@end

@implementation ATProtoLexiconErrorTests

- (void)testErrorWithCode_NoContext {
    NSError *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Test error"
                                                context:nil];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoLexiconErrorDomain);
    XCTAssertEqual(error.code, ATProtoLexiconErrorInvalidSchema);
    XCTAssertEqualObjects(error.localizedDescription, @"Test error");
}

- (void)testErrorWithCode_WithContext {
    NSError *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorMissingRequiredField
                                                message:@"Missing field"
                                                context:@"record.text"];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorMissingRequiredField);
    XCTAssertTrue([error.localizedDescription containsString:@"record.text"]);
    XCTAssertEqualObjects(error.userInfo[@"context"], @"record.text");
}

- (void)testErrorWithCode_AllErrorCodes {
    for (NSInteger code = ATProtoLexiconErrorInvalidSchema; code <= ATProtoLexiconErrorCircularReference; code++) {
        NSError *error = [ATProtoLexiconError errorWithCode:(ATProtoLexiconErrorCode)code
                                                    message:@"test"
                                                    context:nil];
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, code);
    }
}

- (void)testConstraintError_WithFieldAndValue {
    NSError *error = [ATProtoLexiconError constraintError:@"maxLength"
                                                   field:@"record.text"
                                                   value:@"A very long string here"
                                                expected:@"100"];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoLexiconErrorDomain);
    XCTAssertEqual(error.code, ATProtoLexiconErrorConstraintViolation);
    XCTAssertTrue([error.localizedDescription containsString:@"maxLength"]);
    XCTAssertEqualObjects(error.userInfo[@"constraint"], @"maxLength");
    XCTAssertEqualObjects(error.userInfo[@"field"], @"record.text");
    XCTAssertEqualObjects(error.userInfo[@"expected"], @"100");
    XCTAssertNotNil(error.userInfo[@"actualValue"]);
}

- (void)testConstraintError_NilValue {
    NSError *error = [ATProtoLexiconError constraintError:@"minimum"
                                                   field:@"age"
                                                   value:nil
                                                expected:@"0"];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorConstraintViolation);
    XCTAssertTrue([error.localizedDescription containsString:@"null"]);
}

- (void)testConstraintError_NumberValue {
    NSError *error = [ATProtoLexiconError constraintError:@"minimum"
                                                   field:@"age"
                                                   value:@(-5)
                                                expected:@"0"];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorConstraintViolation);
}

- (void)testMissingRequiredFieldError_NoContext {
    NSError *error = [ATProtoLexiconError missingRequiredFieldError:@"text" context:nil];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorMissingRequiredField);
    XCTAssertTrue([error.localizedDescription containsString:@"text"]);
}

- (void)testMissingRequiredFieldError_WithContext {
    NSError *error = [ATProtoLexiconError missingRequiredFieldError:@"name" context:@"profile"];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorMissingRequiredField);
    XCTAssertTrue([error.localizedDescription containsString:@"profile"]);
}

- (void)testTypeMismatchError_NoContext {
    NSError *error = [ATProtoLexiconError typeMismatchError:@"age"
                                                   expected:@"integer"
                                                     actual:@"string"
                                                    context:nil];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorInvalidFieldValue);
    XCTAssertTrue([error.localizedDescription containsString:@"integer"]);
    XCTAssertTrue([error.localizedDescription containsString:@"string"]);
    XCTAssertEqualObjects(error.userInfo[@"field"], @"age");
    XCTAssertEqualObjects(error.userInfo[@"expectedType"], @"integer");
    XCTAssertEqualObjects(error.userInfo[@"actualType"], @"string");
}

- (void)testTypeMismatchError_WithContext {
    NSError *error = [ATProtoLexiconError typeMismatchError:@"age"
                                                   expected:@"integer"
                                                     actual:@"string"
                                                    context:@"record.age"];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoLexiconErrorInvalidFieldValue);
    XCTAssertTrue([error.localizedDescription containsString:@"record.age"]);
}

- (void)testTypeMismatchError_ArrayExpected {
    NSError *error = [ATProtoLexiconError typeMismatchError:@"items"
                                                   expected:@"array"
                                                     actual:@"object"
                                                    context:nil];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.userInfo[@"expectedType"], @"array");
    XCTAssertEqualObjects(error.userInfo[@"actualType"], @"object");
}

@end
