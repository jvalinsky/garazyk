// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSRASLResolver.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSDatabaseAccount.h"
#import "Database/PDSDatabaseBlock.h"
#import "Core/CID.h"

/// A minimal `PDSAccountService` test double: `getAllAccountsWithError:`
/// returns exactly the DIDs the test injects, in order. Every other method
/// is unused by `PDSRASLResolver` and stubbed to fail loudly if ever called.
@interface FakeRASLAccountService : NSObject <PDSAccountService>
@property (nonatomic, copy) NSArray<NSString *> *accountDIDs;
@end

@implementation FakeRASLAccountService

@synthesize sessionRepository = _sessionRepository;

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];
    for (NSString *did in self.accountDIDs) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;
        account.handle = did;
        account.status = @"active";
        [accounts addObject:account];
    }
    return accounts;
}

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email password:(NSString *)password handle:(NSString *)handle did:(nullable NSString *)did error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)loginWithHandle:(NSString *)handle password:(NSString *)password error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier password:(NSString *)password error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier password:(NSString *)password authFactorToken:(nullable NSString *)authFactorToken error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error {
    return nil;
}
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken error:(NSError **)error {
    return nil;
}
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {
    return NO;
}

@end

@interface PDSRASLResolverTests : XCTestCase
@property (nonatomic, strong) NSURL *testDBURL;
@property (nonatomic, strong) NSURL *testStorageURL;
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSBlobStorage *blobStorage;
@property (nonatomic, strong) PDSBlobService *blobService;
@property (nonatomic, strong) PDSRecordService *recordService;
@property (nonatomic, strong) FakeRASLAccountService *accountService;
@property (nonatomic, strong) PDSRASLResolver *resolver;
@end

@implementation PDSRASLResolverTests

- (void)setUp {
    [super setUp];
    self.testDBURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pds_rasl_resolver_test"]];
    self.testStorageURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pds_rasl_resolver_storage"]];
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.testDBURL withIntermediateDirectories:YES attributes:nil error:nil];

    self.databasePool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDBURL.path maxSize:5];
    PDSDiskBlobProvider *provider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:self.testStorageURL];
    self.blobStorage = [[PDSBlobStorage alloc] initWithDatabasePool:self.databasePool provider:provider];
    self.blobService = [[PDSBlobService alloc] initWithDatabasePool:self.databasePool storage:self.blobStorage];
    self.recordService = [[PDSRecordService alloc] initWithDatabasePool:self.databasePool];
    self.accountService = [[FakeRASLAccountService alloc] init];
    self.resolver = [[PDSRASLResolver alloc] initWithDatabasePool:self.databasePool
                                                        blobService:self.blobService
                                                      accountService:self.accountService];
}

- (void)tearDown {
    [self.databasePool closeAll];
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [super tearDown];
}

/// Blobs stay in the "temporary" lifecycle state (see Schema.m /
/// docs/plans/prompts/phase-15-blob-lifecycle.md) until a record references
/// them, and PDSBlobStorage's own read path refuses to serve unreferenced
/// blobs. Match that by writing a referencing record, the same way
/// PDSBlobServiceTests does.
- (void)referenceBlobWithCIDString:(NSString *)cidString forDid:(NSString *)did {
    NSError *error = nil;
    uint8_t privateKey[32] = {0};
    memset(privateKey, 1, sizeof(privateKey));
    PDSActorStore *store = [self.databasePool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"%@", error);
    XCTAssertTrue([store importSigningKey:[NSData dataWithBytes:privateKey length:sizeof(privateKey)] error:&error], @"%@", error);

    NSDictionary *value = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"references an uploaded blob",
        @"embed": @{
            @"$type": @"blob",
            @"ref": @{ @"$link": cidString }
        }
    };
    BOOL stored = [self.recordService putRecord:@"app.bsky.feed.post"
                                           rkey:[[NSUUID UUID] UUIDString]
                                          value:value
                                         forDid:did
                                 validationMode:PDSValidationModeOff
                                          error:&error];
    XCTAssertTrue(stored, @"%@", error);
}

- (void)putBlockData:(NSData *)data cid:(ATProtoCID *)cid forDid:(NSString *)did {
    NSError *error = nil;
    PDSActorStore *store = [self.databasePool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"%@", error);
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid.bytes;
    block.repoDid = did;
    block.blockData = data;
    block.size = data.length;
    block.createdAt = [NSDate date];
    XCTAssertTrue([store putBlock:block forDid:did error:&error], @"%@", error);
}

- (void)testFindsBlockOnMatchingAccount {
    NSString *did = @"did:web:rasl-block.example.com";
    self.accountService.accountDIDs = @[did];

    NSData *content = [@"a repo block" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCID sha256:content];
    [self putBlockData:content cid:cid forDid:did];

    NSData *found = [self.resolver dataForCID:cid maxAccountsToScan:10];
    XCTAssertEqualObjects(found, content);
}

- (void)testFindsBlobOnMatchingAccount {
    NSString *did = @"did:web:rasl-blob.example.com";
    self.accountService.accountDIDs = @[did];

    NSData *content = [@"an uploaded blob" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *result = [self.blobService uploadBlob:content forDid:did mimeType:@"application/octet-stream" error:&error];
    XCTAssertNotNil(result, @"%@", error);
    NSString *cidString = result[@"blob"][@"ref"][@"$link"];
    ATProtoCID *cid = [ATProtoCID cidFromString:cidString];
    XCTAssertNotNil(cid);
    [self referenceBlobWithCIDString:cidString forDid:did];

    NSData *found = [self.resolver dataForCID:cid maxAccountsToScan:10];
    XCTAssertEqualObjects(found, content);
}

- (void)testScansPastAccountsWithoutTheCID {
    NSString *emptyDid = @"did:web:rasl-empty.example.com";
    NSString *ownerDid = @"did:web:rasl-owner.example.com";
    self.accountService.accountDIDs = @[emptyDid, ownerDid];

    NSData *content = [@"owned by the second account" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCID sha256:content];
    [self putBlockData:content cid:cid forDid:ownerDid];

    NSData *found = [self.resolver dataForCID:cid maxAccountsToScan:10];
    XCTAssertEqualObjects(found, content);
}

- (void)testMissingCIDReturnsNil {
    self.accountService.accountDIDs = @[@"did:web:rasl-miss.example.com"];
    NSData *content = [@"never stored" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCID sha256:content];

    XCTAssertNil([self.resolver dataForCID:cid maxAccountsToScan:10]);
}

- (void)testScanBoundIsRespected {
    NSString *ownerDid = @"did:web:rasl-bound-owner.example.com";
    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    for (NSInteger i = 0; i < 5; i++) {
        [dids addObject:[NSString stringWithFormat:@"did:web:rasl-bound-%ld.example.com", (long)i]];
    }
    [dids addObject:ownerDid];
    self.accountService.accountDIDs = dids;

    NSData *content = [@"beyond the scan bound" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [ATProtoCID sha256:content];
    [self putBlockData:content cid:cid forDid:ownerDid];

    // ownerDid is the 6th account; a bound of 3 must not reach it.
    XCTAssertNil([self.resolver dataForCID:cid maxAccountsToScan:3]);
    // A bound that covers all 6 must find it.
    XCTAssertEqualObjects([self.resolver dataForCID:cid maxAccountsToScan:10], content);
}

@end
