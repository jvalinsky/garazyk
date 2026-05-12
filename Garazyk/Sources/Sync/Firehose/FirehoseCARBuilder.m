// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Firehose/FirehoseCARBuilder.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Debug/GZLogger.h"
#import "Core/NSDictionary+CID.h"

@implementation FirehoseCARBuilder

+ (NSData *)buildCARForCommit:(RepoCommit *)commit
                          ops:(NSArray<NSDictionary *> *)ops
                blockProvider:(PDSBlockProvider)blockProvider
          revBlockListProvider:(nullable PDSRevisionBlockListProvider)revBlockListProvider {
  CID *commitCID = commit.computeCID;
  if (!commitCID) {
    return [NSData data];
  }

  CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
  NSMutableSet<NSString *> *seenCIDs = [NSMutableSet set];
  [seenCIDs addObject:commitCID.stringValue];

  NSData *commitBlockData = [commit serializeSigned];
  if (commitBlockData.length > 0) {
    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitBlockData]];
  }

  for (NSDictionary *op in ops) {
    NSString *action = op[@"action"];
    if ([action isEqualToString:@"delete"])
      continue;

    NSData *recordCBOR = op[@"recordCBOR"];
    if (![recordCBOR isKindOfClass:[NSData class]] || recordCBOR.length == 0)
      continue;

    CID *recordCID = [op cidObjectForKey:@"cid"];
    if (!recordCID) {
      NSData *digest = [CID rawSha256:recordCBOR];
      recordCID = digest ? [CID cidWithDigest:digest codec:0x71] : nil;
    }
    
    if (recordCID && ![seenCIDs containsObject:recordCID.stringValue]) {
      [seenCIDs addObject:recordCID.stringValue];
      [writer addBlock:[CARBlock blockWithCID:recordCID data:recordCBOR]];
    }
  }

  NSUInteger revisionBlockCount = 0;
  if (commit.rev.length > 0 && revBlockListProvider) {
    NSArray<NSData *> *cids = revBlockListProvider(commit.rev);
    for (NSData *cidBytes in cids) {
      CID *cid = [CID cidFromBytes:cidBytes];
      if (!cid || [seenCIDs containsObject:cid.stringValue]) continue;
      
      NSData *blockData = blockProvider(cidBytes);
      if (blockData.length > 0) {
        [seenCIDs addObject:cid.stringValue];
        [writer addBlock:[CARBlock blockWithCID:cid data:blockData]];
        revisionBlockCount++;
      }
    }
  }

  if (revisionBlockCount == 0 && commit.dataCID) {
    [self addMSTNodeBlocksForRootCID:commit.dataCID
                      blockProvider:blockProvider
                           toWriter:writer];
  }

  return [writer serialize];
}

+ (void)addMSTNodeBlocksForRootCID:(CID *)rootCID
                    blockProvider:(PDSBlockProvider)blockProvider
                         toWriter:(CARWriter *)writer {
  NSMutableArray<NSData *> *queue = [NSMutableArray arrayWithObject:[rootCID bytes]];
  NSMutableSet<NSString *> *visited = [NSMutableSet set];

  while (queue.count > 0) {
    NSData *cidBytes = queue.firstObject;
    [queue removeObjectAtIndex:0];

    CID *nodeCID = [CID cidFromBytes:cidBytes];
    if (!nodeCID || [visited containsObject:nodeCID.stringValue]) continue;
    [visited addObject:nodeCID.stringValue];

    NSData *blockData = blockProvider(cidBytes);
    if (!blockData) continue;

    [writer addBlock:[CARBlock blockWithCID:nodeCID data:blockData]];

    CBORValue *nodeMap = [CBORValue decode:blockData];
    if (!nodeMap || nodeMap.type != CBORTypeMap) continue;
    // (Note: The original implementation has a comment about not recursing to avoid OOM)
  }
}

+ (NSData *)buildCARForSyncCommitOnly:(RepoCommit *)commit {
  CID *commitCID = commit.computeCID;
  if (!commitCID) return [NSData data];

  CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
  NSData *commitBlockData = [commit serializeSigned];
  if (commitBlockData.length > 0) {
    [writer addBlock:[CARBlock blockWithCID:commitCID data:commitBlockData]];
  }
  return [writer serialize];
}

@end
