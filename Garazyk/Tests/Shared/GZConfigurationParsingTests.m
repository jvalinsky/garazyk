// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Shared/GZConfigurationParsing.h"

@interface TestTarget : NSObject
@property (nonatomic, copy) NSString *stringProp;
@property (nonatomic, assign) NSInteger integerProp;
@property (nonatomic, assign) double doubleProp;
@property (nonatomic, assign) BOOL booleanProp;
@property (nonatomic, copy) NSArray<NSString *> *arrayProp;
@end

@implementation TestTarget
@end

@interface GZConfigurationParsingTests : XCTestCase
@end

@implementation GZConfigurationParsingTests

- (void)testEnvironmentParsing {
    NSArray *props = @[
        [GZConfigurationProperty propertyWithTargetKey:@"stringProp" jsonKeys:@[] envVar:@"TEST_STRING" type:GZConfigurationPropertyTypeString],
        [GZConfigurationProperty propertyWithTargetKey:@"integerProp" jsonKeys:@[] envVar:@"TEST_INT" type:GZConfigurationPropertyTypeInteger],
        [GZConfigurationProperty propertyWithTargetKey:@"doubleProp" jsonKeys:@[] envVar:@"TEST_DOUBLE" type:GZConfigurationPropertyTypeDouble],
        [GZConfigurationProperty propertyWithTargetKey:@"booleanProp" jsonKeys:@[] envVar:@"TEST_BOOL" type:GZConfigurationPropertyTypeBoolean],
        [GZConfigurationProperty propertyWithTargetKey:@"arrayProp" jsonKeys:@[] envVar:@"TEST_ARRAY" type:GZConfigurationPropertyTypeStringArray]
    ];
    
    GZConfigurationParsing *parser = [[GZConfigurationParsing alloc] initWithProperties:props];
    
    NSDictionary *env = @{
        @"TEST_STRING": @"hello",
        @"TEST_INT": @"42",
        @"TEST_DOUBLE": @"3.14",
        @"TEST_BOOL": @"1",
        @"TEST_ARRAY": @"foo, bar,baz"
    };
    
    TestTarget *target = [[TestTarget alloc] init];
    [parser applyEnvironmentVariables:env toTarget:target];
    
    XCTAssertEqualObjects(target.stringProp, @"hello");
    XCTAssertEqual(target.integerProp, 42);
    XCTAssertEqualWithAccuracy(target.doubleProp, 3.14, 0.001);
    XCTAssertTrue(target.booleanProp);
    NSArray *expectedArray = @[@"foo", @"bar", @"baz"];
    XCTAssertEqualObjects(target.arrayProp, expectedArray);
}

- (void)testDictionaryParsing {
    NSArray *props = @[
        [GZConfigurationProperty propertyWithTargetKey:@"stringProp" jsonKeys:@[@"string_prop"] envVar:@"" type:GZConfigurationPropertyTypeString],
        [GZConfigurationProperty propertyWithTargetKey:@"integerProp" jsonKeys:@[@"int_prop", @"integer_prop"] envVar:@"" type:GZConfigurationPropertyTypeInteger],
        [GZConfigurationProperty propertyWithTargetKey:@"doubleProp" jsonKeys:@[@"double_prop"] envVar:@"" type:GZConfigurationPropertyTypeDouble],
        [GZConfigurationProperty propertyWithTargetKey:@"booleanProp" jsonKeys:@[@"bool_prop"] envVar:@"" type:GZConfigurationPropertyTypeBoolean],
        [GZConfigurationProperty propertyWithTargetKey:@"arrayProp" jsonKeys:@[@"array_prop"] envVar:@"" type:GZConfigurationPropertyTypeStringArray]
    ];
    
    GZConfigurationParsing *parser = [[GZConfigurationParsing alloc] initWithProperties:props];
    
    NSDictionary *dict = @{
        @"string_prop": @"world",
        @"integer_prop": @"99", // fallback key, string value
        @"double_prop": @(2.71),
        @"bool_prop": @YES,
        @"array_prop": @[@"a", @"b"]
    };
    
    TestTarget *target = [[TestTarget alloc] init];
    [parser applyDictionary:dict toTarget:target];
    
    XCTAssertEqualObjects(target.stringProp, @"world");
    XCTAssertEqual(target.integerProp, 99);
    XCTAssertEqualWithAccuracy(target.doubleProp, 2.71, 0.001);
    XCTAssertTrue(target.booleanProp);
    NSArray *expectedArray = @[@"a", @"b"];
    XCTAssertEqualObjects(target.arrayProp, expectedArray);
}

@end
