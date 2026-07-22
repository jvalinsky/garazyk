// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import <sqlite3.h>

#import "Services/PDS/PDSSpaceStore.h"
#import "Security/Space/PDSSpaceLtHash.h"

@interface PDSSpaceStore (Testing)
- (BOOL)rollbackMigrationsToVersion:(NSInteger)version error:(NSError **)error;
@end

static BOOL PDSSpaceTestTableUsesWithoutRowid(NSString *path, NSString *tableName) {
  sqlite3 *database = NULL;
  if (sqlite3_open(path.fileSystemRepresentation, &database) != SQLITE_OK) return NO;
  sqlite3_stmt *statement = NULL;
  BOOL usesWithoutRowid = NO;
  if (sqlite3_prepare_v2(database, "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", -1,
                         &statement, NULL) == SQLITE_OK) {
    sqlite3_bind_text(statement, 1, tableName.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement) == SQLITE_ROW) {
      const unsigned char *sql = sqlite3_column_text(statement, 0);
      usesWithoutRowid = sql && [[NSString stringWithUTF8String:(const char *)sql]
          rangeOfString:@"WITHOUT ROWID" options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
  }
  if (statement) sqlite3_finalize(statement);
  sqlite3_close(database);
  return usesWithoutRowid;
}

@interface PDSSpaceStoreTests : XCTestCase
@property(nonatomic, copy) NSString *temporaryDirectory;
@property(nonatomic, strong) PDSSpaceStore *store;
@end

@implementation PDSSpaceStoreTests

- (void)setUp {
  [super setUp];
  self.temporaryDirectory = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-space-store-%@", NSUUID.UUID.UUIDString]];
  NSError *error = nil;
  self.store = [[PDSSpaceStore alloc]
      initWithDatabasePath:[self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"]
                  error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(self.store);
  XCTAssertTrue([self.store createSpace:[self space]
                                  owner:YES
                                  policy:@"member-list"
                              managingApp:nil
                           appAccessType:@"open"
                               appAllowed:@[]
                                    error:&error]);
  XCTAssertNil(error);
}

- (void)tearDown {
  [self.store close];
  [[NSFileManager defaultManager] removeItemAtPath:self.temporaryDirectory error:nil];
  [super tearDown];
}

- (void)testRepositoriesAreIsolatedPerSpaceAndAuthorAndPersist {
  NSError *error = nil;
  NSDictionary *aliceCommit = [self.store
      applyWrites:@[[self write:PDSSpaceWriteActionCreate cid:@"bafy-alice" value:@"alice"]]
           toSpace:[self space]
            author:@"did:example:alice"
               rev:@"3jzfcijpj2z2a"
             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(aliceCommit);
  NSDictionary *bobCommit = [self.store
      applyWrites:@[[self write:PDSSpaceWriteActionCreate cid:@"bafy-bob" value:@"bob"]]
           toSpace:[self space]
            author:@"did:example:bob"
               rev:@"3jzfcijpj2z2b"
             error:&error];
  XCTAssertNotNil(bobCommit);
  XCTAssertNotEqualObjects(aliceCommit[@"state"], bobCommit[@"state"]);

  NSArray<NSDictionary<NSString *, id> *> *heads = [self.store repositoriesForReconciliation:&error];
  XCTAssertNil(error);
  XCTAssertEqual(heads.count, 2UL);
  BOOL foundAliceHead = NO;
  for (NSDictionary<NSString *, id> *head in heads) {
    if ([head[@"author"] isEqualToString:@"did:example:alice"] &&
        [head[@"rev"] isEqualToString:@"3jzfcijpj2z2a"] && [head[@"hash"] length] == 32) {
      foundAliceHead = YES;
      break;
    }
  }
  XCTAssertTrue(foundAliceHead);

  NSDictionary *alice = [self.store recordForSpace:[self space]
                                            author:@"did:example:alice"
                                        collection:@"com.example.note"
                                              rkey:@"one"
                                             error:&error];
  NSDictionary *bob = [self.store recordForSpace:[self space]
                                          author:@"did:example:bob"
                                      collection:@"com.example.note"
                                            rkey:@"one"
                                           error:&error];
  XCTAssertEqualObjects(alice[@"cid"], @"bafy-alice");
  XCTAssertEqualObjects(bob[@"cid"], @"bafy-bob");

  [self.store close];
  self.store = [[PDSSpaceStore alloc]
      initWithDatabasePath:[self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"]
                  error:&error];
  XCTAssertNotNil(self.store);
  NSDictionary *reloaded = [self.store repositoryStateForSpace:[self space]
                                                         author:@"did:example:alice"
                                                          error:&error];
  XCTAssertEqualObjects(reloaded[@"state"], aliceCommit[@"state"]);
  XCTAssertEqualObjects(reloaded[@"hash"], aliceCommit[@"hash"]);
}

- (void)testUpdateDeleteAndOplogMaintainLTHashState {
  NSError *error = nil;
  NSDictionary *create = [self.store
      applyWrites:@[[self write:PDSSpaceWriteActionCreate cid:@"bafy-first" value:@"one"]]
           toSpace:[self space]
            author:@"did:example:alice"
               rev:@"3jzfcijpj2z2a"
             error:&error];
  NSDictionary *update = [self.store
      applyWrites:@[[self write:PDSSpaceWriteActionUpdate cid:@"bafy-second" value:@"two"]]
           toSpace:[self space]
            author:@"did:example:alice"
               rev:@"3jzfcijpj2z2b"
             error:&error];
  XCTAssertNotEqualObjects(create[@"hash"], update[@"hash"]);
  NSDictionary *delete = [self.store
      applyWrites:@[[self write:PDSSpaceWriteActionDelete cid:nil value:nil]]
           toSpace:[self space]
            author:@"did:example:alice"
               rev:@"3jzfcijpj2z2c"
             error:&error];
  XCTAssertEqualObjects(delete[@"hash"], [[PDSSpaceLtHash alloc] init].digest);
  XCTAssertNil([self.store recordForSpace:[self space]
                                   author:@"did:example:alice"
                               collection:@"com.example.note"
                                     rkey:@"one"
                                    error:&error]);

  NSArray *operations = [self.store repoOperationsForSpace:[self space]
                                                     author:@"did:example:alice"
                                                      since:nil
                                                      limit:10
                                                       error:&error];
  XCTAssertEqual(operations.count, 3UL);
  XCTAssertEqualObjects(operations[0][@"action"], @"create");
  XCTAssertEqualObjects(operations[1][@"prev"], @"bafy-first");
  XCTAssertEqualObjects(operations[2][@"action"], @"delete");
  XCTAssertEqualObjects(operations[2][@"prev"], @"bafy-second");
}

- (void)testOplogPruningReportsRemovedEntries {
  NSError *error = nil;
  for (NSUInteger index = 0; index < 3; index++) {
    NSString *revision = [NSString stringWithFormat:@"3jzfcijpj2z2%lu", (unsigned long)index];
    NSString *cid = [NSString stringWithFormat:@"bafy-%lu", (unsigned long)index];
    PDSSpaceWriteAction action = index == 0 ? PDSSpaceWriteActionCreate : PDSSpaceWriteActionUpdate;
    XCTAssertNotNil([self.store applyWrites:@[[self write:action
                                                      cid:cid
                                                    value:revision]]
                                  toSpace:[self space]
                                   author:@"did:example:alice"
                                      rev:revision
                                    error:&error]);
    XCTAssertNil(error);
  }
  NSUInteger prunedEntries = 0;
  XCTAssertTrue([self.store pruneAllOplogsKeepingRevisions:1
                                             prunedEntries:&prunedEntries
                                                      error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual(prunedEntries, 2UL);
  NSArray *operations = [self.store repoOperationsForSpace:[self space]
                                                     author:@"did:example:alice"
                                                      since:nil
                                                      limit:10
                                                      error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(operations.count, 1UL);
}

- (void)testOnlineBackupRestoresRepositoryLTHashState {
  NSError *error = nil;
  NSDictionary *commit = [self.store applyWrites:@[[self write:PDSSpaceWriteActionCreate
                                                           cid:@"bafy-backup"
                                                         value:@"backup"]]
                                        toSpace:[self space]
                                         author:@"did:example:alice"
                                            rev:@"3jzfcijpj2z2a"
                                          error:&error];
  XCTAssertNotNil(commit);
  XCTAssertNil(error);

  NSString *backupPath = [self.temporaryDirectory stringByAppendingPathComponent:@"restore/spaces.sqlite"];
  XCTAssertTrue([self.store createOnlineBackupAtPath:backupPath error:&error]);
  XCTAssertNil(error);

  PDSSpaceStore *restored = [[PDSSpaceStore alloc] initWithDatabasePath:backupPath error:&error];
  XCTAssertNotNil(restored);
  XCTAssertNil(error);
  NSDictionary *state = [restored repositoryStateForSpace:[self space]
                                                    author:@"did:example:alice"
                                                     error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(state[@"state"], commit[@"state"]);
  XCTAssertEqualObjects(state[@"hash"], commit[@"hash"]);
  NSDictionary *record = [restored recordForSpace:[self space]
                                           author:@"did:example:alice"
                                       collection:@"com.example.note"
                                             rkey:@"one"
                                            error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(record[@"cid"], @"bafy-backup");
  [restored close];
}

- (void)testMembershipWriterSetAndDelegationReplayStateAreDurable {
  NSError *error = nil;
  XCTAssertTrue([self.store addMember:@"did:example:alice" toSpace:[self space] error:&error]);
  XCTAssertTrue([self.store isMember:@"did:example:alice" ofSpace:[self space] error:&error]);
  XCTAssertTrue([self.store removeMember:@"did:example:alice" fromSpace:[self space] error:&error]);
  XCTAssertFalse([self.store isMember:@"did:example:alice" ofSpace:[self space] error:&error]);

  NSData *hash = [NSMutableData dataWithLength:32];
  XCTAssertTrue([self.store recordWriter:@"did:example:alice"
                                forSpace:[self space]
                                     rev:@"3jzfcijpj2z2a"
                                    hash:hash
                                   error:&error]);
  NSMutableData *newerHash = [NSMutableData dataWithLength:32];
  ((uint8_t *)newerHash.mutableBytes)[0] = 1;
  XCTAssertTrue([self.store recordWriter:@"did:example:alice"
                                forSpace:[self space]
                                     rev:@"3jzfcijpj2z2b"
                                    hash:newerHash
                                   error:&error]);
  XCTAssertTrue([self.store recordWriter:@"did:example:alice"
                                forSpace:[self space]
                                     rev:@"3jzfcijpj2z2a"
                                    hash:hash
                                   error:&error]);
  NSArray *writers = [self.store writersForSpace:[self space] limit:10 cursor:nil error:&error];
  XCTAssertEqual(writers.count, 1UL);
  XCTAssertEqualObjects(writers[0][@"did"], @"did:example:alice");
  XCTAssertEqualObjects(writers[0][@"rev"], @"3jzfcijpj2z2b");
  XCTAssertEqualObjects(writers[0][@"hash"], newerHash);

  NSDate *recipientExpiry = [[NSDate date] dateByAddingTimeInterval:60.0];
  XCTAssertTrue([self.store recordCredentialRecipientForSpace:[self space]
                                                    serviceDID:@"did:example:sync"
                                               serviceEndpoint:@"https://sync.example/xrpc"
                                                     expiresAt:recipientExpiry
                                                         error:&error]);
  NSArray *recipients = [self.store credentialRecipientsForSpace:[self space] error:&error];
  XCTAssertEqual(recipients.count, 1UL);
  XCTAssertEqualObjects(recipients[0][@"serviceDID"], @"did:example:sync");
  XCTAssertFalse([self.store recordCredentialRecipientForSpace:[self space]
                                                     serviceDID:@"did:example:expired"
                                                serviceEndpoint:@"https://expired.example/xrpc"
                                                      expiresAt:[NSDate dateWithTimeIntervalSinceNow:-1]
                                                          error:&error]);

  NSDate *now = [NSDate date];
  NSDate *expires = [now dateByAddingTimeInterval:60.0];
  XCTAssertTrue([self.store consumeDelegationID:@"delegation-id" expiresAt:expires now:now error:&error]);
  XCTAssertFalse([self.store consumeDelegationID:@"delegation-id" expiresAt:expires now:now error:&error]);
}

- (void)testReplicaDeletionAndExplicitManagingAppClearArePersistent {
  NSError *error = nil;
  XCTAssertTrue([self.store updateSpace:[self space]
                                 policy:nil
                             managingApp:@"did:web:app.example#manager"
                          appAccessType:nil
                              appAllowed:nil
                                   error:&error]);
  XCTAssertEqualObjects([self.store spaceInfoForURI:[self space] error:nil][@"managingApp"],
                        @"did:web:app.example#manager");
  XCTAssertTrue([self.store updateSpace:[self space]
                                 policy:nil
                             managingApp:@""
                          appAccessType:nil
                              appAllowed:nil
                                   error:&error]);
  XCTAssertEqualObjects([self.store spaceInfoForURI:[self space] error:nil][@"managingApp"], [NSNull null]);

  NSString *replica = @"at://did:example:remote/space/com.example.group/default";
  XCTAssertTrue([self.store createSpace:replica owner:NO policy:@"member-list" managingApp:nil appAccessType:@"open" appAllowed:@[] error:&error]);
  XCTAssertTrue([self.store markReplicatedSpaceDeleted:replica error:&error]);
  XCTAssertNotEqualObjects([self.store spaceInfoForURI:replica error:nil][@"deletedAt"], [NSNull null]);
}

- (void)testReplicaWriterNotificationMaterializesNamespaceAndCannotResurrectTombstone {
  NSString *replica = @"at://did:example:remote/space/com.example.group/replica";
  NSData *hash = [NSMutableData dataWithLength:32];
  NSError *error = nil;

  XCTAssertTrue([self.store recordWriter:@"did:example:writer"
                                forSpace:replica
                                     rev:@"3jzfcijpj2z2a"
                                    hash:hash
                                   error:&error]);
  XCTAssertNil(error);
  NSDictionary *info = [self.store spaceInfoForURI:replica error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(info);
  XCTAssertFalse([info[@"isOwner"] boolValue]);
  XCTAssertEqual([self.store writersForSpace:replica limit:10 cursor:nil error:&error].count, 1UL);

  XCTAssertTrue([self.store markReplicatedSpaceDeleted:replica error:&error]);
  XCTAssertFalse([self.store recordWriter:@"did:example:writer"
                                 forSpace:replica
                                      rev:@"3jzfcijpj2z2b"
                                     hash:hash
                                    error:&error]);
  XCTAssertEqual(error.code, PDSSpaceStoreErrorSpaceNotFound);

  error = nil;
  XCTAssertNil([self.store applyWrites:@[[self write:PDSSpaceWriteActionCreate cid:@"bafy-after-delete" value:@"blocked"]]
                               toSpace:replica
                                author:@"did:example:writer"
                                   rev:@"3jzfcijpj2z2c"
                                 error:&error]);
  XCTAssertEqual(error.code, PDSSpaceStoreErrorSpaceNotFound);
}

- (void)testPrivateBlobsAreScopedToSpaceAndAuthorAndSurviveReopen {
  NSError *error = nil;
  NSData *data = [@"only the intended space can address these bytes" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *stored = [self.store storeBlobData:data
                                          mimeType:@"text/plain"
                                           toSpace:[self space]
                                            author:@"did:example:alice"
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(stored);
  XCTAssertTrue([stored[@"cid"] hasPrefix:@"bafk"]);

  NSDictionary *found = [self.store blobForCID:stored[@"cid"]
                                          space:[self space]
                                         author:@"did:example:alice"
                                          error:&error];
  XCTAssertEqualObjects(found[@"data"], data);
  XCTAssertEqualObjects(found[@"mimeType"], @"text/plain");
  XCTAssertNil([self.store blobForCID:stored[@"cid"]
                                  space:@"at://did:example:other/space/com.example.group/default"
                                 author:@"did:example:alice"
                                  error:&error]);
  XCTAssertNil([self.store blobForCID:stored[@"cid"]
                                  space:[self space]
                                 author:@"did:example:bob"
                                  error:&error]);

  [self.store close];
  self.store = [[PDSSpaceStore alloc]
      initWithDatabasePath:[self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"]
                  error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects([[self.store blobForCID:stored[@"cid"]
                                            space:[self space]
                                           author:@"did:example:alice"
                                            error:&error] objectForKey:@"data"], data);
}

- (void)testWithoutRowidMigrationRollbackAndReapplyPreserveSpaceData {
  NSError *error = nil;
  NSString *path = [self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"];
  XCTAssertTrue([self.store addMember:@"did:example:alice" toSpace:[self space] error:&error]);
  XCTAssertNotNil([self.store applyWrites:@[[self write:PDSSpaceWriteActionCreate cid:@"bafy-round-trip" value:@"round-trip"]]
                                  toSpace:[self space]
                                   author:@"did:example:alice"
                                      rev:@"3jzfcijpj2z2a"
                                    error:&error]);
  XCTAssertTrue([self.store recordWriter:@"did:example:alice"
                                forSpace:[self space]
                                     rev:@"3jzfcijpj2z2a"
                                    hash:[NSMutableData dataWithLength:32]
                                   error:&error]);
  XCTAssertTrue([self.store recordCredentialRecipientForSpace:[self space]
                                                    serviceDID:@"did:example:sync"
                                               serviceEndpoint:@"https://sync.example/xrpc"
                                                     expiresAt:[NSDate dateWithTimeIntervalSinceNow:60]
                                                         error:&error]);
  XCTAssertNotNil([self.store storeBlobData:[@"private" dataUsingEncoding:NSUTF8StringEncoding]
                                    mimeType:@"text/plain"
                                     toSpace:[self space]
                                      author:@"did:example:alice"
                                       error:&error]);
  XCTAssertNil(error);

  XCTAssertTrue([self.store rollbackMigrationsToVersion:3 error:&error], @"%@", error);
  XCTAssertNil(error);
  [self.store close];
  NSArray<NSString *> *tables = @[@"space_member", @"space_repo", @"space_record", @"space_record_oplog",
                                  @"space_writer", @"space_credential_recipient", @"space_blob"];
  for (NSString *table in tables) XCTAssertFalse(PDSSpaceTestTableUsesWithoutRowid(path, table));

  self.store = [[PDSSpaceStore alloc] initWithDatabasePath:path error:&error];
  XCTAssertNotNil(self.store);
  XCTAssertNil(error);
  [self.store close];
  for (NSString *table in tables) XCTAssertTrue(PDSSpaceTestTableUsesWithoutRowid(path, table));

  self.store = [[PDSSpaceStore alloc] initWithDatabasePath:path error:&error];
  XCTAssertEqualObjects([self.store recordForSpace:[self space]
                                            author:@"did:example:alice"
                                        collection:@"com.example.note"
                                              rkey:@"one"
                                             error:&error][@"cid"], @"bafy-round-trip");
  XCTAssertTrue([self.store isMember:@"did:example:alice" ofSpace:[self space] error:&error]);
  XCTAssertEqual([self.store writersForSpace:[self space] limit:10 cursor:nil error:&error].count, 1UL);
  XCTAssertEqual([self.store credentialRecipientsForSpace:[self space] error:&error].count, 1UL);
}

- (PDSSpaceWrite *)write:(PDSSpaceWriteAction)action cid:(NSString *)cid value:(NSString *)value {
  return [PDSSpaceWrite writeWithAction:action
                             collection:@"com.example.note"
                                   rkey:@"one"
                                    cid:cid
                                  value:[value dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSString *)space {
  return @"at://did:example:authority/space/com.example.group/default";
}

@end
