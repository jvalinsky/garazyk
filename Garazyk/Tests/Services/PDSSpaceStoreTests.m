// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Services/PDS/PDSSpaceStore.h"
#import "Security/Space/PDSSpaceLtHash.h"

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
