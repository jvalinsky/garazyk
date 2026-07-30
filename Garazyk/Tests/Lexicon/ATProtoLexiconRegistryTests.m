// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"

@interface ATProtoLexiconRegistryTests : XCTestCase
@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@end

@implementation ATProtoLexiconRegistryTests

- (void)setUp {
    [super setUp];
    self.registry = [[ATProtoLexiconRegistry alloc] init];
}

- (void)tearDown {
    [self.registry clearCache];
    [super tearDown];
}

#pragma mark - schemaForNSID:

- (void)testSchemaForNSID_AfterRegister_ReturnsSchema {
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:nil];
    XCTAssertNotNil(schema);

    [self.registry registerSchema:schema];

    ATProtoLexiconSchema *found = [self.registry schemaForNSID:@"app.bsky.feed.post"];
    XCTAssertNotNil(found);
    XCTAssertEqual(found, schema);
}

- (void)testSchemaForNSID_NotRegistered_ReturnsNil {
    ATProtoLexiconSchema *found = [self.registry schemaForNSID:@"app.bsky.feed.nonexistent"];
    XCTAssertNil(found);
}

- (void)testSchemaForNSID_NilInput_ReturnsNil {
    ATProtoLexiconSchema *found = [self.registry schemaForNSID:nil];
    XCTAssertNil(found);
}

- (void)testSchemaForNSID_EmptyString_ReturnsNil {
    ATProtoLexiconSchema *found = [self.registry schemaForNSID:@""];
    XCTAssertNil(found);
}

#pragma mark - hasSchemaForNSID:

- (void)testHasSchemaForNSID_Registered_ReturnsYES {
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.like",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:nil];
    [self.registry registerSchema:schema];

    XCTAssertTrue([self.registry hasSchemaForNSID:@"app.bsky.feed.like"]);
}

- (void)testHasSchemaForNSID_NotRegistered_ReturnsNO {
    XCTAssertFalse([self.registry hasSchemaForNSID:@"app.bsky.feed.like"]);
}

#pragma mark - registerSchema:

- (void)testRegisterSchema_NilSchema_DoesNotCrash {
    XCTAssertNoThrow([self.registry registerSchema:nil]);
}

- (void)testRegisterSchema_OverwritesExisting {
    ATProtoLexiconSchema *schema1 = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:nil];
    ATProtoLexiconSchema *schema2 = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"query"}}
    } error:nil];

    [self.registry registerSchema:schema1];
    [self.registry registerSchema:schema2];

    ATProtoLexiconSchema *found = [self.registry schemaForNSID:@"app.bsky.feed.post"];
    XCTAssertEqual(found, schema2, @"Should return the latest registered schema");
}

- (void)testRegisterSchema_MultipleSchemas_AllAccessible {
    NSArray *nsids = @[@"app.bsky.feed.post", @"app.bsky.feed.like", @"app.bsky.graph.follow"];
    for (NSString *nsid in nsids) {
        ATProtoLexiconSchema *s = [ATProtoLexiconSchema schemaFromJSONObject:@{
            @"lexicon": @1,
            @"id": nsid,
            @"defs": @{@"main": @{@"type": @"record"}}
        } error:nil];
        [self.registry registerSchema:s];
    }

    for (NSString *nsid in nsids) {
        XCTAssertTrue([self.registry hasSchemaForNSID:nsid], @"Schema for %@ not found", nsid);
    }
}

#pragma mark - clearCache

- (void)testClearCache_RemovesAllSchemas {
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:nil];
    [self.registry registerSchema:schema];

    [self.registry clearCache];

    XCTAssertFalse([self.registry hasSchemaForNSID:@"app.bsky.feed.post"]);
    XCTAssertEqual([self.registry loadedNSIDs].count, (NSUInteger)0);
}

#pragma mark - loadedNSIDs

- (void)testLoadedNSIDs_Empty_ReturnsEmptyArray {
    NSArray *nsids = [self.registry loadedNSIDs];
    XCTAssertNotNil(nsids);
    XCTAssertEqual(nsids.count, (NSUInteger)0);
}

- (void)testLoadedNSIDs_AfterRegistration_ReturnsNSIDs {
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONObject:@{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.post",
        @"defs": @{@"main": @{@"type": @"record"}}
    } error:nil];
    [self.registry registerSchema:schema];

    NSArray *nsids = [self.registry loadedNSIDs];
    XCTAssertEqual(nsids.count, (NSUInteger)1);
    XCTAssertTrue([nsids containsObject:@"app.bsky.feed.post"]);
}

#pragma mark - loadLexiconFromFile:error:

- (void)testLoadLexiconFromFile_NonExistentFile_ReturnsNO {
    NSError *error = nil;
    BOOL loaded = [self.registry loadLexiconFromFile:@"/tmp/nonexistent_lexicon.json" error:&error];
    XCTAssertFalse(loaded);
    XCTAssertNotNil(error);
}

- (void)testLoadLexiconFromFile_InvalidJSON_ReturnsNO {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_bad_lexicon.json"];
    [@"{invalid json" writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSError *error = nil;
    BOOL loaded = [self.registry loadLexiconFromFile:tempPath error:&error];
    XCTAssertFalse(loaded);

    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
}

- (void)testLoadLexiconFromFile_ValidJSON_ReturnsYES {
    NSDictionary *json = @{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.test",
        @"defs": @{@"main": @{@"type": @"record"}}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_valid_lexicon.json"];
    [data writeToFile:tempPath atomically:YES];

    NSError *error = nil;
    BOOL loaded = [self.registry loadLexiconFromFile:tempPath error:&error];
    XCTAssertTrue(loaded);
    XCTAssertNil(error);

    XCTAssertTrue([self.registry hasSchemaForNSID:@"app.bsky.feed.test"]);

    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
}

#pragma mark - loadLexiconsFromDirectory:error:

- (void)testLoadLexiconsFromDirectory_NonExistentDir_ReturnsNO {
    NSError *error = nil;
    BOOL loaded = [self.registry loadLexiconsFromDirectory:@"/tmp/nonexistent_lexicon_dir" error:&error];
    XCTAssertFalse(loaded);
    XCTAssertNotNil(error);
}

- (void)testLoadLexiconsFromDirectory_EmptyDir_ReturnsYES {
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_empty_lexicon_dir"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSError *error = nil;
    BOOL loaded = [self.registry loadLexiconsFromDirectory:tempDir error:&error];
    XCTAssertTrue(loaded);
    XCTAssertNil(error);

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)testLoadLexiconsFromDirectory_SecondLoadSkipsReparse {
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_memo_lexicon_dir"];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *json = @{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.memo",
        @"defs": @{@"main": @{@"type": @"record"}}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSString *filePath = [tempDir stringByAppendingPathComponent:@"memo.json"];
    [data writeToFile:filePath atomically:YES];

    NSError *error = nil;
    XCTAssertTrue([self.registry loadLexiconsFromDirectory:tempDir error:&error]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"app.bsky.feed.memo"]);

    // Corrupt the on-disk file in place. Atomic replacement updates the
    // containing directory's mtime, which correctly invalidates the registry
    // cache and would test a different behavior.
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    XCTAssertNotNil(fileHandle);
    [fileHandle truncateFileAtOffset:0];
    [fileHandle writeData:[@"not-json" dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle closeFile];
    error = nil;
    XCTAssertTrue([self.registry loadLexiconsFromDirectory:tempDir error:&error],
                  @"Second load of an unchanged directory mtime should short-circuit");
    XCTAssertTrue([self.registry hasSchemaForNSID:@"app.bsky.feed.memo"],
                  @"Memoized load must keep the previously registered schema");

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)testLoadLexiconsFromDirectory_ClearCacheForcesReload {
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_memo_reload_lexicon_dir"];
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *json = @{
        @"lexicon": @1,
        @"id": @"app.bsky.feed.reload",
        @"defs": @{@"main": @{@"type": @"record"}}
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSString *filePath = [tempDir stringByAppendingPathComponent:@"reload.json"];
    [data writeToFile:filePath atomically:YES];

    XCTAssertTrue([self.registry loadLexiconsFromDirectory:tempDir error:nil]);
    [self.registry clearCache];
    XCTAssertFalse([self.registry hasSchemaForNSID:@"app.bsky.feed.reload"]);

    XCTAssertTrue([self.registry loadLexiconsFromDirectory:tempDir error:nil]);
    XCTAssertTrue([self.registry hasSchemaForNSID:@"app.bsky.feed.reload"],
                  @"After clearCache, directory memoization must be invalidated");

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

@end
