// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/GZCommandLineOptions.h"

@interface GZCommandLineOptionsTests : XCTestCase
@end

@implementation GZCommandLineOptionsTests

- (void)testBooleanOption {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    GZCommandLineOption *opt = [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO];
    [parser registerOptions:@[opt] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[@"--verbose"] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"verbose"], @(YES));

    result = [parser parseArguments:@[@"-v"] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"verbose"], @(YES));

    result = [parser parseArguments:@[] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"verbose"], @(NO));
}

- (void)testStringOption {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    GZCommandLineOption *opt = [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO];
    [parser registerOptions:@[opt] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[@"--port", @"8080"] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"port"], @"8080");

    result = [parser parseArguments:@[@"-p", @"9090"] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"port"], @"9090");

    result = [parser parseArguments:@[@"--port"] forCommand:@"serve" error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 2); // Missing value
}

- (void)testRepeatableStringOption {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    GZCommandLineOption *opt = [GZCommandLineOption optionWithLongName:@"relay" shortName:@"r" type:GZCommandLineOptionTypeRepeatableString isRequired:NO];
    [parser registerOptions:@[opt] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[@"--relay", @"url1", @"-r", @"url2"] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    NSArray *expected = @[@"url1", @"url2"];
    XCTAssertEqualObjects(result[@"relay"], expected);

    result = [parser parseArguments:@[] forCommand:@"serve" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"relay"], @[]);
}

- (void)testRequiredOption {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    GZCommandLineOption *opt = [GZCommandLineOption optionWithLongName:@"config" shortName:@"c" type:GZCommandLineOptionTypeString isRequired:YES];
    [parser registerOptions:@[opt] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[] forCommand:@"serve" error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 5); // Missing required
}

- (void)testUnknownOption {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    [parser registerOptions:@[] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[@"--unknown"] forCommand:@"serve" error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 3); // Unknown option
}

- (void)testUnexpectedArgument {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    [parser registerOptions:@[] forCommand:@"serve"];

    NSError *error = nil;
    NSDictionary *result = [parser parseArguments:@[@"positional"] forCommand:@"serve" error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 4); // Unexpected argument
}

@end
