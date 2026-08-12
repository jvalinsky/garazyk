// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Firehose/FirehoseCARBuilder.h"
#import "Repository/CAR.h"
#import "Core/CBOR.h"
#import "Debug/GZLogger.h"
#import "Core/NSDictionary+CID.h"

@implementation ATProtoFirehoseCARBuilder

+ (NSData *)buildCARForCommit:(ATProtoRepoCommit *)commit
                          ops:(NSArray<NSDictionary *> *)ops
                blockProvider:(PDSBlockProvider)blockProvider
          revBlockListProvider:(nullable PDSRevisionBlockListProvider)revBlockListProvider {
  ATProtoCID *commitCID = commit.computeCID;
  if (!commitCID) {
    return [NSData data];
  }

  ATProtoCARWriter *writer = [ATProtoCARWriter writerWithRootCID:commitCID];
  NSMutableSet<NSString *> *seenCIDs = [NSMutableSet set];
  [seenCIDs addObject:commitCID.stringValue];

  NSData *commitBlockData = [commit serializeSigned];
  if (commitBlockData.length > 0) {
    [writer addBlock:[ATProtoCARBlock blockWithCID:commitCID data:commitBlockData]];
  }

  for (NSDictionary *op in ops) {
    NSString *action = op[@"action"];
    if ([action isEqualToString:@"delete"])
      continue;

    NSData *recordCBOR = op[@"recordCBOR"];
    if (![recordCBOR isKindOfClass:[NSData class]] || recordCBOR.length == 0)
      continue;

    ATProtoCID *recordCID = [op cidObjectForKey:@"cid"];
    if (!recordCID) {
      NSData *digest = [ATProtoCID rawSha256:recordCBOR];
      recordCID = digest ? [ATProtoCID cidWithDigest:digest codec:0x71] : nil;
    }
    
    if (recordCID && ![seenCIDs containsObject:recordCID.stringValue]) {
      [seenCIDs addObject:recordCID.stringValue];
      [writer addBlock:[ATProtoCARBlock blockWithCID:recordCID data:recordCBOR]];
    }
  }

  NSUInteger revisionBlockCount = 0;
  if (commit.rev.length > 0 && revBlockListProvider) {
    NSArray<NSData *> *cids = revBlockListProvider(commit.rev);
    for (NSData *cidBytes in cids) {
      ATProtoCID *cid = [ATProtoCID cidFromBytes:cidBytes];
      if (!cid || [seenCIDs containsObject:cid.stringValue]) continue;
      
      NSData *blockData = blockProvider(cidBytes);
      if (blockData.length > 0) {
        [seenCIDs addObject:cid.stringValue];
        [writer addBlock:[ATProtoCARBlock blockWithCID:cid data:blockData]];
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

+ (void)addMSTNodeBlocksForRootCID:(ATProtoCID *)rootCID
                    blockProvider:(PDSBlockProvider)blockProvider
                         toWriter:(ATProtoCARWriter *)writer {
  NSMutableArray<NSData *> *queue = [NSMutableArray arrayWithObject:[rootCID bytes]];
  NSMutableSet<NSString *> *visited = [NSMutableSet set];

  while (queue.count > 0) {
    NSData *cidBytes = queue.firstObject;
    [queue removeObjectAtIndex:0];

    ATProtoCID *nodeCID = [ATProtoCID cidFromBytes:cidBytes];
    if (!nodeCID || [visited containsObject:nodeCID.stringValue]) continue;
    [visited addObject:nodeCID.stringValue];

    NSData *blockData = blockProvider(cidBytes);
    if (!blockData) continue;

    [writer addBlock:[ATProtoCARBlock blockWithCID:nodeCID data:blockData]];

    ATProtoCBORValue *nodeMap = [ATProtoCBORValue decode:blockData];
    if (!nodeMap || nodeMap.type != CBORTypeMap) continue;

    ATProtoCBORValue *leftTag = nodeMap.map[[ATProtoCBORValue textString:@"l"]];
    if (leftTag && leftTag.type == CBORTypeTag) {
      NSData *lBytes = leftTag.tagValue.byteString;
      if (lBytes.length > 1) {
        NSData *lCidBytes = [lBytes subdataWithRange:NSMakeRange(1, lBytes.length - 1)];
        ATProtoCID *leftCID = [ATProtoCID cidFromBytes:lCidBytes];
        if (leftCID && ![visited containsObject:leftCID.stringValue]) {
          [queue addObject:lCidBytes];
        }
      }
    }

    ATProtoCBORValue *entriesValue = nodeMap.map[[ATProtoCBORValue textString:@"e"]];
    if (entriesValue && entriesValue.type == CBORTypeArray) {
      for (ATProtoCBORValue *entryMap in entriesValue.array) {
        if (entryMap.type != CBORTypeMap) continue;
        ATProtoCBORValue *treeTag = entryMap.map[[ATProtoCBORValue textString:@"t"]];
        if (treeTag && treeTag.type == CBORTypeTag) {
          NSData *tBytes = treeTag.tagValue.byteString;
          if (tBytes.length > 1) {
            NSData *tCidBytes = [tBytes subdataWithRange:NSMakeRange(1, tBytes.length - 1)];
            ATProtoCID *treeCID = [ATProtoCID cidFromBytes:tCidBytes];
            if (treeCID && ![visited containsObject:treeCID.stringValue]) {
              [queue addObject:tCidBytes];
            }
          }
        }
      }
    }
  }
}

+ (NSData *)buildCARForSyncCommitOnly:(ATProtoRepoCommit *)commit {
  ATProtoCID *commitCID = commit.computeCID;
  if (!commitCID) return [NSData data];

  ATProtoCARWriter *writer = [ATProtoCARWriter writerWithRootCID:commitCID];
  NSData *commitBlockData = [commit serializeSigned];
  if (commitBlockData.length > 0) {
    [writer addBlock:[ATProtoCARBlock blockWithCID:commitCID data:commitBlockData]];
  }
  return [writer serialize];
}

@end
