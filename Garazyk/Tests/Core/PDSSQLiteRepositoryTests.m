// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/Repositories/PDSSQLiteAccountRepository.h"
#import "Core/Repositories/PDSSQLiteSessionRepository.h"
#import "Core/Repositories/PDSSQLiteRecordRepository.h"
#import "Core/Repositories/PDSSQLiteBlobRepository.h"
#import "Core/Repositories/PDSSQLiteBlockRepository.h"
#import "Core/Repositories/PDSSQLiteRepoRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"

// did:plc identifiers must be exactly 24 lowercase base32 chars (see
// ATProtoValidator validateDID:) - the actor store path derivation rejects
// anything shorter.
static NSString * const kTestDID = @"did:plc:aaaaaaaaaaaaaaaaaaaaaaaa";
static NSString * const kTestDID2 = @"did:plc:bbbbbbbbbbbbbbbbbbbbbbbb";

@interface PDSSQLiteRepositoryTests : XCTestCase {
    NSString *_tempDir;
    PDSDatabasePool *_pool;
    id<PDSAccountRepository> _accountRepo;
    id<PDSSessionRepository> _sessionRepo;
    id<PDSRecordRepository> _recordRepo;
    id<PDSBlobRepository> _blobRepo;
    id<PDSBlockRepository> _blockRepo;
    id<PDSRepoRepository> _repoRepo;
}
@end

@implementation PDSSQLiteRepositoryTests

- (void)setUp {
    [super setUp];
    _tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    _pool = [[PDSDatabasePool alloc] initWithDbDirectory:_tempDir maxSize:4];
    _accountRepo  = [[PDSSQLiteAccountRepository alloc] initWithServicePool:_pool];
    _sessionRepo  = [[PDSSQLiteSessionRepository alloc] initWithServicePool:_pool];
    _recordRepo   = [[PDSSQLiteRecordRepository alloc] initWithDatabasePool:_pool];
    _blobRepo     = [[PDSSQLiteBlobRepository alloc] initWithDatabasePool:_pool];
    _blockRepo    = [[PDSSQLiteBlockRepository alloc] initWithDatabasePool:_pool];
    _repoRepo     = [[PDSSQLiteRepoRepository alloc] initWithServicePool:_pool];
}

- (void)tearDown {
    [_pool closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:_tempDir error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (PDSDatabaseAccount *)accountWithDID:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *a = [[PDSDatabaseAccount alloc] init];
    a.did = did;
    a.handle = handle;
    a.status = @"active";
    a.createdAt = [[NSDate date] timeIntervalSince1970];
    a.updatedAt = a.createdAt;
    return a;
}

- (PDSDatabaseRepo *)repoWithDID:(NSString *)did {
    PDSDatabaseRepo *r = [[PDSDatabaseRepo alloc] init];
    r.ownerDid = did;
    r.rootCid = [@"8a2b4c" dataUsingEncoding:NSUTF8StringEncoding];
    r.createdAt = [NSDate date];
    r.updatedAt = r.createdAt;
    return r;
}

- (PDSDatabaseRecord *)recordWithURI:(NSString *)uri did:(NSString *)did {
    // AT-URI shape: at://<did>/<collection>/<rkey> - derive collection/rkey
    // from the actual URI rather than hardcoding, so callers passing distinct
    // collections/rkeys (e.g. testRecordListForDID) get distinct records.
    NSArray<NSString *> *components = [uri componentsSeparatedByString:@"/"];
    NSString *collection = components.count >= 2 ? components[components.count - 2] : @"app.bsky.actor.profile";
    NSString *rkey = components.count >= 1 ? components[components.count - 1] : @"self";

    PDSDatabaseRecord *rec = [[PDSDatabaseRecord alloc] init];
    rec.uri = uri;
    rec.did = did;
    rec.collection = collection;
    rec.rkey = rkey;
    rec.cid = @"bafyreicid";
    rec.createdAt = [NSDate date];
    rec.value = @"{}";
    return rec;
}

- (PDSDatabaseBlock *)blockWithCID:(NSData *)cid repoDid:(NSString *)did {
    PDSDatabaseBlock *b = [[PDSDatabaseBlock alloc] init];
    b.cid = cid;
    b.repoDid = did;
    b.blockData = [@"test-block-data" dataUsingEncoding:NSUTF8StringEncoding];
    b.size = b.blockData.length;
    b.createdAt = [NSDate date];
    return b;
}

- (NSData *)fakeCID {
    return [@"fakecid12345678" dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)fakeCID2 {
    return [@"fakecid87654321" dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Account Repository

- (void)testAccountRepoSaveAndLookupByDID {
    PDSDatabaseAccount *account = [self accountWithDID:kTestDID handle:@"alice.test"];
    NSError *error = nil;
    XCTAssertTrue([_accountRepo saveAccount:account error:&error], @"save: %@", error);

    PDSDatabaseAccount *found = [_accountRepo accountForDid:kTestDID error:&error];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.handle, @"alice.test");
}

- (void)testAccountRepoLookupByHandle {
    PDSDatabaseAccount *account = [self accountWithDID:kTestDID handle:@"bob.test"];
    [_accountRepo saveAccount:account error:nil];

    PDSDatabaseAccount *found = [_accountRepo accountForHandle:@"bob.test" error:nil];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.did, kTestDID);
}

- (void)testAccountRepoLookupByEmail {
    PDSDatabaseAccount *account = [self accountWithDID:kTestDID handle:@"carol.test"];
    account.email = @"carol@example.com";
    [_accountRepo saveAccount:account error:nil];

    PDSDatabaseAccount *found = [_accountRepo accountForEmail:@"carol@example.com" error:nil];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.did, kTestDID);
}

- (void)testAccountRepoDelete {
    PDSDatabaseAccount *account = [self accountWithDID:kTestDID handle:@"del.test"];
    [_accountRepo saveAccount:account error:nil];

    NSError *error = nil;
    XCTAssertTrue([_accountRepo deleteAccount:kTestDID error:&error], @"delete: %@", error);

    PDSDatabaseAccount *found = [_accountRepo accountForDid:kTestDID error:nil];
    XCTAssertNil(found);
}

- (void)testAccountRepoListPagination {
    for (int i = 0; i < 5; i++) {
        // did:plc identifiers must be exactly 24 lowercase base32 chars; pad
        // with 'a' and vary a single trailing base32 digit ('2'-'7') for uniqueness.
        PDSDatabaseAccount *a = [self accountWithDID:
            [NSString stringWithFormat:@"did:plc:pg%caaaaaaaaaaaaaaaaaaaaa", (char)('2' + i)]
                                             handle:[NSString stringWithFormat:@"pg%d.test", i]];
        [_accountRepo saveAccount:a error:nil];
    }

    NSArray *page1 = [_accountRepo listAccountsWithLimit:2 cursor:nil error:nil];
    XCTAssertEqual(page1.count, 2);

    NSString *cursor = ((PDSDatabaseAccount *)page1.lastObject).did;
    NSArray *page2 = [_accountRepo listAccountsWithLimit:2 cursor:cursor error:nil];
    XCTAssertEqual(page2.count, 2);
    XCTAssertNotEqualObjects(((PDSDatabaseAccount *)page2.firstObject).did,
                             ((PDSDatabaseAccount *)page1.firstObject).did);
}

- (void)testAccountRepoUpdateExisting {
    PDSDatabaseAccount *account = [self accountWithDID:kTestDID handle:@"orig.test"];
    [_accountRepo saveAccount:account error:nil];

    account.handle = @"updated.test";
    NSError *error = nil;
    XCTAssertTrue([_accountRepo saveAccount:account error:&error], @"update: %@", error);

    PDSDatabaseAccount *found = [_accountRepo accountForDid:kTestDID error:nil];
    XCTAssertEqualObjects(found.handle, @"updated.test");
}

#pragma mark - Session Repository

- (void)testSessionStoreAndLookup {
    NSString *token = @"refresh-token-abc";
    NSString *sid = @"session-001";
    NSError *error = nil;
    XCTAssertTrue([_sessionRepo storeRefreshToken:token sessionID:sid forAccountDid:kTestDID error:&error],
                  @"store: %@", error);

    NSString *did = [_sessionRepo accountDidForRefreshToken:token error:&error];
    XCTAssertEqualObjects(did, kTestDID);
}

- (void)testSessionInfoForToken {
    NSString *token = @"refresh-token-info";
    NSString *sid = @"session-002";
    [_sessionRepo storeRefreshToken:token sessionID:sid forAccountDid:kTestDID error:nil];

    NSDictionary *info = [_sessionRepo sessionInfoForRefreshToken:token error:nil];
    XCTAssertNotNil(info);
    XCTAssertEqualObjects(info[@"account_did"], kTestDID);
}

- (void)testSessionIsActive {
    NSString *token = @"refresh-token-active";
    NSString *sid = @"session-003";
    [_sessionRepo storeRefreshToken:token sessionID:sid forAccountDid:kTestDID error:nil];

    NSError *error = nil;
    BOOL active = [_sessionRepo isSessionActive:sid forAccountDid:kTestDID error:&error];
    XCTAssertTrue(active);
}

- (void)testSessionRevokeToken {
    NSString *token = @"refresh-token-revoke";
    NSString *sid = @"session-004";
    [_sessionRepo storeRefreshToken:token sessionID:sid forAccountDid:kTestDID error:nil];

    NSError *error = nil;
    XCTAssertTrue([_sessionRepo revokeRefreshToken:token error:&error], @"revoke: %@", error);

    NSString *did = [_sessionRepo accountDidForRefreshToken:token error:nil];
    XCTAssertNil(did);
}

- (void)testSessionRevokeSingleSession {
    NSString *token1 = @"token-s1";
    NSString *sid1 = @"session-r1";
    NSString *token2 = @"token-s2";
    NSString *sid2 = @"session-r2";
    [_sessionRepo storeRefreshToken:token1 sessionID:sid1 forAccountDid:kTestDID error:nil];
    [_sessionRepo storeRefreshToken:token2 sessionID:sid2 forAccountDid:kTestDID error:nil];

    NSError *error = nil;
    XCTAssertTrue([_sessionRepo revokeSession:sid1 error:&error], @"revoke: %@", error);

    NSString *did1 = [_sessionRepo accountDidForRefreshToken:token1 error:nil];
    XCTAssertNil(did1);
    NSString *did2 = [_sessionRepo accountDidForRefreshToken:token2 error:nil];
    XCTAssertEqualObjects(did2, kTestDID);
}

- (void)testSessionRevokeAllForAccount {
    NSString *token1 = @"token-all1";
    NSString *sid1 = @"session-all1";
    NSString *token2 = @"token-all2";
    NSString *sid2 = @"session-all2";
    [_sessionRepo storeRefreshToken:token1 sessionID:sid1 forAccountDid:kTestDID error:nil];
    [_sessionRepo storeRefreshToken:token2 sessionID:sid2 forAccountDid:kTestDID error:nil];

    NSError *error = nil;
    XCTAssertTrue([_sessionRepo revokeAllRefreshTokensForAccountDid:kTestDID error:&error],
                  @"revoke all: %@", error);

    XCTAssertNil([_sessionRepo accountDidForRefreshToken:token1 error:nil]);
    XCTAssertNil([_sessionRepo accountDidForRefreshToken:token2 error:nil]);
}

#pragma mark - Record Repository

- (void)testRecordSaveAndRetrieve {
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", kTestDID];
    PDSDatabaseRecord *rec = [self recordWithURI:uri did:kTestDID];

    NSError *error = nil;
    XCTAssertTrue([_recordRepo saveRecord:rec error:&error], @"save: %@", error);

    PDSDatabaseRecord *found = [_recordRepo recordForUri:uri error:&error];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.uri, uri);
    XCTAssertEqualObjects(found.collection, @"app.bsky.actor.profile");
}

- (void)testRecordListForDID {
    NSString *uri1 = [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", kTestDID];
    NSString *uri2 = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/rkey1", kTestDID];
    [_recordRepo saveRecord:[self recordWithURI:uri1 did:kTestDID] error:nil];
    [_recordRepo saveRecord:[self recordWithURI:uri2 did:kTestDID] error:nil];

    NSArray *all = [_recordRepo recordsForDid:kTestDID collection:nil error:nil];
    XCTAssertEqual(all.count, 2);

    NSArray *profileOnly = [_recordRepo recordsForDid:kTestDID
                                           collection:@"app.bsky.actor.profile"
                                                error:nil];
    XCTAssertEqual(profileOnly.count, 1);
}

- (void)testRecordDelete {
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", kTestDID];
    [_recordRepo saveRecord:[self recordWithURI:uri did:kTestDID] error:nil];

    NSError *error = nil;
    XCTAssertTrue([_recordRepo deleteRecord:uri error:&error], @"delete: %@", error);

    PDSDatabaseRecord *found = [_recordRepo recordForUri:uri error:nil];
    XCTAssertNil(found);
}

- (void)testRecordOverwrite {
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", kTestDID];
    PDSDatabaseRecord *v1 = [self recordWithURI:uri did:kTestDID];
    v1.value = @"{\"version\":1}";
    [_recordRepo saveRecord:v1 error:nil];

    PDSDatabaseRecord *v2 = [self recordWithURI:uri did:kTestDID];
    v2.value = @"{\"version\":2}";
    NSError *error = nil;
    XCTAssertTrue([_recordRepo saveRecord:v2 error:&error], @"overwrite: %@", error);

    PDSDatabaseRecord *found = [_recordRepo recordForUri:uri error:nil];
    XCTAssertEqualObjects(found.value, @"{\"version\":2}");
}

#pragma mark - Blob Repository

- (void)testBlobSaveAndLookup {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [self fakeCID];
    blob.did = kTestDID;
    blob.mimeType = @"image/png";
    blob.size = 1024;
    blob.createdAt = [NSDate date];

    NSError *error = nil;
    XCTAssertTrue([_blobRepo saveBlob:blob error:&error], @"save: %@", error);

    PDSDatabaseBlob *found = [_blobRepo blobWithCid:[self fakeCID] did:kTestDID error:&error];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.mimeType, @"image/png");
    XCTAssertEqual(found.size, 1024);
}

- (void)testBlobListForDID {
    for (int i = 0; i < 3; i++) {
        PDSDatabaseBlob *b = [[PDSDatabaseBlob alloc] init];
        b.cid = [[NSString stringWithFormat:@"cid%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        b.did = kTestDID;
        b.mimeType = @"text/plain";
        b.size = 100 * (i + 1);
        b.createdAt = [NSDate date];
        [_blobRepo saveBlob:b error:nil];
    }

    NSArray *blobs = [_blobRepo blobsForDid:kTestDID limit:2 offset:0 error:nil];
    XCTAssertEqual(blobs.count, 2);

    NSArray *page2 = [_blobRepo blobsForDid:kTestDID limit:2 offset:2 error:nil];
    XCTAssertEqual(page2.count, 1);
}

- (void)testBlobCount {
    for (int i = 0; i < 4; i++) {
        PDSDatabaseBlob *b = [[PDSDatabaseBlob alloc] init];
        b.cid = [[NSString stringWithFormat:@"cnt%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        b.did = kTestDID;
        b.size = 50;
        b.createdAt = [NSDate date];
        [_blobRepo saveBlob:b error:nil];
    }

    NSInteger count = [_blobRepo blobCountForDid:kTestDID error:nil];
    XCTAssertEqual(count, 4);
}

- (void)testBlobDelete {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [self fakeCID];
    blob.did = kTestDID;
    blob.size = 256;
    blob.createdAt = [NSDate date];
    [_blobRepo saveBlob:blob error:nil];

    NSError *error = nil;
    XCTAssertTrue([_blobRepo deleteBlob:[self fakeCID] did:kTestDID error:&error], @"delete: %@", error);

    PDSDatabaseBlob *found = [_blobRepo blobWithCid:[self fakeCID] did:kTestDID error:nil];
    XCTAssertNil(found);
}

- (void)testBlobCountPerDID {
    PDSDatabaseBlob *b1 = [[PDSDatabaseBlob alloc] init];
    b1.cid = [self fakeCID];
    b1.did = kTestDID;
    b1.size = 10;
    b1.createdAt = [NSDate date];
    [_blobRepo saveBlob:b1 error:nil];

    PDSDatabaseBlob *b2 = [[PDSDatabaseBlob alloc] init];
    b2.cid = [self fakeCID2];
    b2.did = kTestDID2;
    b2.size = 20;
    b2.createdAt = [NSDate date];
    [_blobRepo saveBlob:b2 error:nil];

    XCTAssertEqual([_blobRepo blobCountForDid:kTestDID error:nil], 1);
    XCTAssertEqual([_blobRepo blobCountForDid:kTestDID2 error:nil], 1);
}

#pragma mark - Block Repository

- (void)testBlockSaveAndRetrieve {
    NSData *cid = [self fakeCID];
    PDSDatabaseBlock *block = [self blockWithCID:cid repoDid:kTestDID];

    NSError *error = nil;
    XCTAssertTrue([_blockRepo saveBlock:block error:&error], @"save: %@", error);

    PDSDatabaseBlock *found = [_blockRepo blockWithCid:cid repoDid:kTestDID error:&error];
    XCTAssertNotNil(found);
    XCTAssertEqual(found.size, block.blockData.length);
}

- (void)testBlockSaveBatch {
    NSData *cid1 = [self fakeCID];
    NSData *cid2 = [self fakeCID2];
    PDSDatabaseBlock *b1 = [self blockWithCID:cid1 repoDid:kTestDID];
    PDSDatabaseBlock *b2 = [self blockWithCID:cid2 repoDid:kTestDID];

    NSError *error = nil;
    NSArray<PDSDatabaseBlock *> *blocks = @[b1, b2];
    XCTAssertTrue([_blockRepo saveBlocks:blocks error:&error], @"batch save: %@", error);

    NSInteger count = [_blockRepo blockCountForRepo:kTestDID error:nil];
    XCTAssertEqual(count, 2);
}

- (void)testBlockCount {
    for (int i = 0; i < 3; i++) {
        NSData *cid = [[NSString stringWithFormat:@"blk%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        [_blockRepo saveBlock:[self blockWithCID:cid repoDid:kTestDID] error:nil];
    }

    NSInteger count = [_blockRepo blockCountForRepo:kTestDID error:nil];
    XCTAssertEqual(count, 3);
}

- (void)testBlockDelete {
    NSData *cid = [self fakeCID];
    [_blockRepo saveBlock:[self blockWithCID:cid repoDid:kTestDID] error:nil];

    NSError *error = nil;
    XCTAssertTrue([_blockRepo deleteBlock:cid repoDid:kTestDID error:&error], @"delete: %@", error);

    PDSDatabaseBlock *found = [_blockRepo blockWithCid:cid repoDid:kTestDID error:nil];
    XCTAssertNil(found);
}

- (void)testBlockListPagination {
    for (int i = 0; i < 5; i++) {
        NSData *cid = [[NSString stringWithFormat:@"pgb%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        [_blockRepo saveBlock:[self blockWithCID:cid repoDid:kTestDID] error:nil];
    }

    NSArray *page1 = [_blockRepo blocksForRepo:kTestDID limit:2 offset:0 error:nil];
    XCTAssertEqual(page1.count, 2);

    NSArray *page2 = [_blockRepo blocksForRepo:kTestDID limit:2 offset:2 error:nil];
    XCTAssertEqual(page2.count, 2);
}

- (void)testBlockPerRepoIsolation {
    NSData *cid = [self fakeCID];
    [_blockRepo saveBlock:[self blockWithCID:cid repoDid:kTestDID] error:nil];

    PDSDatabaseBlock *found = [_blockRepo blockWithCid:cid repoDid:kTestDID2 error:nil];
    XCTAssertNil(found);
}

#pragma mark - Repo Repository

- (void)testRepoCreateAndLookup {
    PDSDatabaseRepo *repo = [self repoWithDID:kTestDID];

    NSError *error = nil;
    XCTAssertTrue([_repoRepo createRepo:repo error:&error], @"create: %@", error);

    PDSDatabaseRepo *found = [_repoRepo repoForDid:kTestDID error:&error];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.ownerDid, kTestDID);
}

- (void)testRepoUpdateRoot {
    PDSDatabaseRepo *repo = [self repoWithDID:kTestDID];
    [_repoRepo createRepo:repo error:nil];

    NSData *newRoot = [@"newrootcid" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    XCTAssertTrue([_repoRepo updateRepoRoot:kTestDID rootCid:newRoot error:&error], @"update: %@", error);

    PDSDatabaseRepo *found = [_repoRepo repoForDid:kTestDID error:nil];
    XCTAssertEqualObjects(found.rootCid, newRoot);
}

- (void)testRepoDelete {
    PDSDatabaseRepo *repo = [self repoWithDID:kTestDID];
    [_repoRepo createRepo:repo error:nil];

    NSError *error = nil;
    XCTAssertTrue([_repoRepo deleteRepo:kTestDID error:&error], @"delete: %@", error);

    PDSDatabaseRepo *found = [_repoRepo repoForDid:kTestDID error:nil];
    XCTAssertNil(found);
}

- (void)testRepoAllRepos {
    for (int i = 0; i < 3; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:all%caaaaaaaaaaaaaaaaaaaa", (char)('2' + i)];
        [_repoRepo createRepo:[self repoWithDID:did] error:nil];
    }

    NSError *error = nil;
    NSArray *all = [_repoRepo allReposWithError:&error];
    XCTAssertNotNil(all, @"allRepos: %@", error);
    XCTAssertEqual(all.count, 3);
}

@end
