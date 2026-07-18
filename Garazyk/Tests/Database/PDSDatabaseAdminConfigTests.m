// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseAdminConfigTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseAdminConfigTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"adminconfig_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open database: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Set & Get

- (void)testSetAndGetConfigValue {
    NSError *error = nil;
    BOOL set = [self.database setAdminConfigValue:@"production" forKey:@"pds.mode" error:&error];
    XCTAssertTrue(set, @"setAdminConfigValue should succeed");
    XCTAssertNil(error);

    NSString *value = [self.database getAdminConfigValue:@"pds.mode" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(value, @"production");
}

- (void)testGetConfigValueNotFound {
    NSError *error = nil;
    NSString *value = [self.database getAdminConfigValue:@"nonexistent.key" error:&error];
    XCTAssertNil(value, @"Should return nil for nonexistent key");
    XCTAssertNil(error);
}

- (void)testOverwriteConfigValue {
    NSError *error = nil;
    [self.database setAdminConfigValue:@"old-value" forKey:@"config.key" error:&error];
    BOOL overwritten = [self.database setAdminConfigValue:@"new-value" forKey:@"config.key" error:&error];
    XCTAssertTrue(overwritten, @"Overwriting config should succeed");
    XCTAssertNil(error);

    NSString *value = [self.database getAdminConfigValue:@"config.key" error:&error];
    XCTAssertEqualObjects(value, @"new-value");
}

- (void)testMultipleConfigKeys {
    NSError *error = nil;
    [self.database setAdminConfigValue:@"value-a" forKey:@"key.a" error:&error];
    [self.database setAdminConfigValue:@"value-b" forKey:@"key.b" error:&error];
    [self.database setAdminConfigValue:@"value-c" forKey:@"key.c" error:&error];

    XCTAssertEqualObjects([self.database getAdminConfigValue:@"key.a" error:nil], @"value-a");
    XCTAssertEqualObjects([self.database getAdminConfigValue:@"key.b" error:nil], @"value-b");
    XCTAssertEqualObjects([self.database getAdminConfigValue:@"key.c" error:nil], @"value-c");
}

@end
