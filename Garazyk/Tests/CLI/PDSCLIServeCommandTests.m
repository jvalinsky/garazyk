// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDefinitions.h"

@interface PDSCLIServeCommandTests : XCTestCase
@end

@implementation PDSCLIServeCommandTests

- (void)testServeCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLIServeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIServeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"serve");
}

- (void)testServeCommand_Summary {
    Class cmdClass = NSClassFromString(@"PDSCLIServeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIServeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    NSString *summary = [cmd performSelector:NSSelectorFromString(@"summary")];
    XCTAssertNotNil(summary);
}

@end

#pragma mark - PDSCLIHealthCommand Tests

@interface PDSCLIHealthCommandTests : XCTestCase
@end

@implementation PDSCLIHealthCommandTests

- (void)testHealthCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLIHealthCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLIHealthCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"status");
    NSArray *aliases = [cmd performSelector:NSSelectorFromString(@"aliases")];
    XCTAssertTrue([aliases containsObject:@"health"]);
}

- (void)testHealthCommand_Exists {
    Class cmdClass = NSClassFromString(@"PDSCLIHealthCommand");
    XCTAssertNotNil(cmdClass);
}

@end

#pragma mark - PDSCLINukeCommand Tests

@interface PDSCLINukeCommandTests : XCTestCase
@end

@implementation PDSCLINukeCommandTests

- (void)testNukeCommand_Name {
    Class cmdClass = NSClassFromString(@"PDSCLINukeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLINukeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    XCTAssertEqualObjects([cmd performSelector:NSSelectorFromString(@"name")], @"nuke-data");
    NSArray *aliases = [cmd performSelector:NSSelectorFromString(@"aliases")];
    XCTAssertTrue([aliases containsObject:@"nuke"]);
}

- (void)testNukeCommand_HelpText {
    Class cmdClass = NSClassFromString(@"PDSCLINukeCommand");
    if (!cmdClass) {
        XCTSkip(@"PDSCLINukeCommand not found");
        return;
    }
    id cmd = [[cmdClass alloc] init];
    NSString *help = [cmd performSelector:NSSelectorFromString(@"helpText")];
    NSString *lowercaseHelp = [help lowercaseString];
    XCTAssertTrue([lowercaseHelp containsString:@"danger"] || [lowercaseHelp containsString:@"delete"]);
}

- (void)testNukeCommandRecursivelyRemovesShardedActorStoresFromScratchDirectory {
    NSString *scratchDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    XCTAssertTrue([fileManager createDirectoryAtPath:scratchDir withIntermediateDirectories:YES attributes:nil error:nil]);

    NSArray<NSString *> *relativeFiles = @[
        @"plc/ab/did:plc:abc123", @"web/ex/did:web:example.com",
        @"blobs/blob", @"service/service.db", @"sequencer/sequencer.db", @"did_cache/cache.db"
    ];
    for (NSString *relativePath in relativeFiles) {
        NSString *path = [scratchDir stringByAppendingPathComponent:relativePath];
        XCTAssertTrue([fileManager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil]);
        XCTAssertTrue([fileManager createFileAtPath:path contents:[NSData data] attributes:nil]);
    }

    PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];
    context.dataDir = scratchDir;
    id command = [[NSClassFromString(@"PDSCLINukeCommand") alloc] init];
    XCTAssertEqual([command executeWithArguments:@[@"--confirm"] context:context], 0);
    XCTAssertEqual([fileManager contentsOfDirectoryAtPath:scratchDir error:nil].count, 0);

    [fileManager removeItemAtPath:scratchDir error:nil];
}

- (void)testNukeCommandReportsFailureWhenScratchDataCannotBeDeleted {
    NSString *scratchDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *protectedDir = [scratchDir stringByAppendingPathComponent:@"protected"];
    NSString *protectedFile = [protectedDir stringByAppendingPathComponent:@"actor.db"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    XCTAssertTrue([fileManager createDirectoryAtPath:protectedDir withIntermediateDirectories:YES attributes:nil error:nil]);
    XCTAssertTrue([fileManager createFileAtPath:protectedFile contents:[NSData data] attributes:nil]);
    XCTAssertTrue([fileManager setAttributes:@{NSFilePosixPermissions: @0555} ofItemAtPath:protectedDir error:nil]);

    PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];
    context.dataDir = scratchDir;
    id command = [[NSClassFromString(@"PDSCLINukeCommand") alloc] init];
    XCTAssertEqual([command executeWithArguments:@[@"--confirm"] context:context], 1);
    XCTAssertTrue([fileManager fileExistsAtPath:protectedDir]);

    XCTAssertTrue([fileManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:protectedDir error:nil]);
    [fileManager removeItemAtPath:scratchDir error:nil];
}

@end
