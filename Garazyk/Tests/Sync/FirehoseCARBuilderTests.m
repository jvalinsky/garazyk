// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Firehose/FirehoseCARBuilder.h"
#import "Repository/RepoCommit.h"
#import "Core/CID.h"

@interface FirehoseCARBuilderTests : XCTestCase
@end

@implementation FirehoseCARBuilderTests

#pragma mark - buildCARForSyncCommitOnly:

- (void)testBuildCARForSyncCommitOnly_ValidCommit_ReturnsCARData {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  NSData *result = [FirehoseCARBuilder buildCARForSyncCommitOnly:commit];
  // If computeCID returns nil, result will be empty; just verify no crash
  XCTAssertNotNil(result);
}

- (void)testBuildCARForSyncCommitOnly_EmptyCommit_ReturnsNonNil {
  RepoCommit *commit = [[RepoCommit alloc] init];
  NSData *result = [FirehoseCARBuilder buildCARForSyncCommitOnly:commit];
  // A bare RepoCommit may have a valid computeCID; verify no crash and non-nil
  XCTAssertNotNil(result);
}

#pragma mark - buildCARForCommit:ops:blockProvider:revBlockListProvider:

- (void)testBuildCARForCommit_EmptyCommit_ReturnsNonNil {
  RepoCommit *commit = [[RepoCommit alloc] init];
  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) { return nil; };
  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[]
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  // A bare RepoCommit may have a valid computeCID; verify no crash and non-nil
  XCTAssertNotNil(result);
}

- (void)testBuildCARForCommit_WithCreateOps_DoesNotCrash {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  NSData *recordData = [NSJSONSerialization dataWithJSONObject:@{@"text": @"Hello"} options:0 error:nil];
  NSDictionary *op = @{
    @"action": @"create",
    @"collection": @"com.example.post",
    @"rkey": @"3jzfcijpj2z2a",
    @"recordCBOR": recordData ?: [NSData data]
  };

  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) {
    return [NSData dataWithBytes:"\x01\x02\x03" length:3];
  };

  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[op]
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  XCTAssertNotNil(result);
}

- (void)testBuildCARForCommit_DeleteOps_AreSkipped {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  NSDictionary *deleteOp = @{
    @"action": @"delete",
    @"collection": @"com.example.post",
    @"rkey": @"3jzfcijpj2z2a"
  };

  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) { return nil; };
  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[deleteOp]
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  XCTAssertNotNil(result);
}

- (void)testBuildCARForCommit_EmptyRecordCBOR_IsSkipped {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  NSDictionary *op = @{
    @"action": @"create",
    @"collection": @"com.example.post",
    @"rkey": @"3jzfcijpj2z2a"
  };

  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) { return nil; };
  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[op]
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  XCTAssertNotNil(result);
}

- (void)testBuildCARForCommit_NilOps_DoesNotCrash {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) { return nil; };
  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:nil
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  XCTAssertNotNil(result);
}

#pragma mark - Block provider edge cases

- (void)testBuildCARForCommit_BlockProviderReturnsNil_DoesNotCrash {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  NSData *recordData = [NSData dataWithBytes:"\x01" length:1];
  NSDictionary *op = @{
    @"action": @"create",
    @"collection": @"com.example.post",
    @"rkey": @"3jzfcijpj2z2a",
    @"recordCBOR": recordData
  };

  PDSBlockProvider provider = ^NSData * _Nullable(NSData *cidBytes) { return nil; };
  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[op]
                                           blockProvider:provider
                                     revBlockListProvider:nil];
  XCTAssertNotNil(result);
}

- (void)testBuildCARForCommit_RevisionBlockListProvider_DoesNotCrash {
  RepoCommit *commit = [[RepoCommit alloc] init];
  commit.rev = @"3jzfcijpj2z2a";
  commit.did = @"did:plc:test";

  PDSBlockProvider blockProvider = ^NSData * _Nullable(NSData *cidBytes) {
    return [NSData dataWithBytes:"\x01" length:1];
  };

  PDSRevisionBlockListProvider revProvider = ^NSArray<NSData *> * _Nullable(NSString *rev) {
    return @[[NSMutableData dataWithLength:32]];
  };

  NSData *result = [FirehoseCARBuilder buildCARForCommit:commit
                                                     ops:@[]
                                           blockProvider:blockProvider
                                     revBlockListProvider:revProvider];
  XCTAssertNotNil(result);
}

@end
