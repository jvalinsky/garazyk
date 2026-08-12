// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/PDSRepoImportValidator.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Repository/CAR.h"
#import "Core/CBOR.h"
#import "Repository/RepoCommit.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/DID.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabaseAccount.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

// Work bounds for a single import. These are DoS guards, not feature limits:
// with maxImportSize capping the body, worst-case work is bounded by the
// configuration. The values were raised from 100k (ADR 0035) because a large
// real account's repo (180 MB CAR) plausibly exceeds 100k records/blocks.
static const NSUInteger kPDSImportRepoMaxCARBlocks = 1000000;
static const NSUInteger kPDSImportRepoMaxMSTNodes = 1000000;
static const NSUInteger kPDSImportRepoMaxRecords = 1000000;
static const NSUInteger kPDSImportRepoMaxMSTDepth = 512;
static const NSUInteger kPDSImportRepoBlockBatchSize = 2048;

static ATProtoCID *cidFromTaggedCBORValue(ATProtoCBORValue *value) {
    if (!value) {
        return nil;
    }

    if (value.type == CBORTypeSimpleOrFloat &&
        value.simpleValue &&
        value.simpleValue.unsignedIntegerValue == 22) {
        return nil;
    }

    if (value.type != CBORTypeTag || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        return nil;
    }

    NSData *bytes = value.tagValue.byteString;
    if (!bytes || bytes.length <= 1) {
        return nil;
    }

    NSData *cidBytes = [bytes subdataWithRange:NSMakeRange(1, bytes.length - 1)];
    return [ATProtoCID cidFromBytes:cidBytes];
}

@implementation PDSRepoImportValidator

+ (BOOL)validateCommitSignature:(ATProtoRepoCommit *)commit did:(NSString *)did databasePool:(PDSDatabasePool *)databasePool allowLocalKeyFallback:(BOOL)allowLocalKeyFallback error:(NSError **)error {
    NSError *resolveError = nil;
    ATProtoDIDDocument *document = [[ATProtoDIDResolver sharedResolver] resolveDIDSync:did error:&resolveError];
    NSMutableArray<NSData *> *candidateKeys = [NSMutableArray array];
    NSData *didDocKey = [ATProtoDIDDocumentFields strictAtprotoSigningKeyBytesFromDocument:document error:nil];
    if (didDocKey) {
        [candidateKeys addObject:didDocKey];
    }

    if (allowLocalKeyFallback) {
        NSError *storeError = nil;
        PDSActorStore *store = [databasePool storeForDid:did error:&storeError];
        NSData *localPublicKey = [store publicSigningKeyWithError:nil];
        if (localPublicKey) {
            [candidateKeys addObject:localPublicKey];
        }
    }

    for (NSData *publicKey in candidateKeys) {
        if ([commit verifySignatureWithPublicKey:publicKey error:nil]) {
            return YES;
        }
    }

    if (error) {
        NSString *message = resolveError
            ? [NSString stringWithFormat:@"Commit signature verification failed and DID document could not be resolved: %@", resolveError.localizedDescription]
            : @"Commit signature did not verify against the DID atproto signing key";
        *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, message);
    }
    return NO;
}

+ (nullable NSArray<PDSDatabaseRecord *> *)extractRecordsFromMSTRoot:(ATProtoCID *)rootCID
                                                                 did:(NSString *)did
                                                              reader:(ATProtoCARStreamReader *)reader
                                                                 rev:(NSString *)rev
                                                               error:(NSError **)error {
    if (!rootCID) {
        return @[];
    }

    NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
    NSMutableSet<NSString *> *visitedCIDs = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{
        @"cid": rootCID,
        @"prevKey": @"",
        @"depth": @0,
    }];
    NSUInteger nodeCount = 0;

    while (stack.count > 0) {
        NSDictionary *frame = stack.lastObject;
        [stack removeLastObject];

        ATProtoCID *nodeCID = frame[@"cid"];
        NSString *prevKey = frame[@"prevKey"] ?: @"";
        NSUInteger depth = [frame[@"depth"] unsignedIntegerValue];
        if (depth > kPDSImportRepoMaxMSTDepth) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported MST exceeds maximum depth");
            return nil;
        }

        NSString *nodeKey = nodeCID.stringValue ?: @"";
        if ([visitedCIDs containsObject:nodeKey]) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST contains a cycle");
            return nil;
        }
        [visitedCIDs addObject:nodeKey];

        nodeCount += 1;
        if (nodeCount > kPDSImportRepoMaxMSTNodes) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported MST has too many nodes");
            return nil;
        }

        ATProtoCARBlock *block = [reader blockWithCID:nodeCID];
        if (!block) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST references a missing block");
            return nil;
        }

        ATProtoCBORValue *nodeValue = [ATProtoCBORValue decode:block.data];
        if (!nodeValue || nodeValue.type != CBORTypeMap) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST node is invalid");
            return nil;
        }

        NSMutableArray<NSDictionary *> *childFrames = [NSMutableArray array];
        ATProtoCBORValue *leftTag = nodeValue.map[[ATProtoCBORValue textString:@"l"]];
        ATProtoCID *leftCID = cidFromTaggedCBORValue(leftTag);
        if (leftCID) {
            [childFrames addObject:@{@"cid": leftCID, @"prevKey": prevKey, @"depth": @(depth + 1)}];
        }

        ATProtoCBORValue *entriesValue = nodeValue.map[[ATProtoCBORValue textString:@"e"]];
        NSArray<ATProtoCBORValue *> *entriesArray = (entriesValue && entriesValue.type == CBORTypeArray) ? entriesValue.array : @[];
        NSString *currentPrevKey = prevKey;

        for (ATProtoCBORValue *entryMap in entriesArray) {
            if (entryMap.type != CBORTypeMap) continue;

            NSData *suffixData = entryMap.map[[ATProtoCBORValue textString:@"k"]].byteString ?: [NSData data];
            ATProtoCBORValue *prefixValue = entryMap.map[[ATProtoCBORValue textString:@"p"]];
            NSUInteger prefixLen = prefixValue.unsignedInteger.unsignedIntegerValue;
            NSUInteger safePrefixLen = MIN(prefixLen, currentPrevKey.length);
            NSString *prefix = [currentPrevKey substringToIndex:safePrefixLen];
            NSString *suffix = [[NSString alloc] initWithData:suffixData encoding:NSUTF8StringEncoding] ?: @"";
            NSString *fullKey = [prefix stringByAppendingString:suffix];

            ATProtoCID *valueCID = cidFromTaggedCBORValue(entryMap.map[[ATProtoCBORValue textString:@"v"]]);
            if (valueCID) {
                ATProtoCARBlock *valueBlock = [reader blockWithCID:valueCID];
                if (!valueBlock) {
                    if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST references a missing record block");
                    return nil;
                }

                PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
                record.did = did;
                record.cid = valueCID.stringValue;
                record.rev = rev;
                record.createdAt = [NSDate date];

                NSRange slashRange = [fullKey rangeOfString:@"/"];
                if (slashRange.location != NSNotFound) {
                    record.collection = [fullKey substringToIndex:slashRange.location];
                    record.rkey = [fullKey substringFromIndex:slashRange.location + 1];
                } else {
                    record.collection = @"unknown";
                    record.rkey = fullKey;
                }
                record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, record.collection, record.rkey];

                id jsonObj = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:YES] JSONObjectWithData:valueBlock.data error:nil];
                if (jsonObj) {
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
                    if (jsonData) {
                        record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    }
                }

                [records addObject:record];
                if (records.count > kPDSImportRepoMaxRecords) {
                    if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported repository has too many records");
                    return nil;
                }
            }

            ATProtoCID *treeCID = cidFromTaggedCBORValue(entryMap.map[[ATProtoCBORValue textString:@"t"]]);
            if (treeCID) {
                [childFrames addObject:@{@"cid": treeCID, @"prevKey": fullKey, @"depth": @(depth + 1)}];
            }

            currentPrevKey = fullKey;
        }

        for (NSDictionary *childFrame in [childFrames reverseObjectEnumerator]) {
            [stack addObject:childFrame];
        }
    }

    return [records copy];
}

+ (NSUInteger)maxImportCARBlocks {
    return kPDSImportRepoMaxCARBlocks;
}

+ (NSUInteger)importBlockBatchSize {
    return kPDSImportRepoBlockBatchSize;
}

+ (nullable PDSRepoImportValidationResult *)validateCARData:(NSData *)carData
                                                     reader:(ATProtoCARStreamReader *)reader
                                                     commit:(ATProtoRepoCommit *)commit
                                                        did:(NSString *)did
                                              databasePool:(PDSDatabasePool *)databasePool
                                     allowLocalKeyFallback:(BOOL)allowLocalKeyFallback
                                             maxImportSize:(NSUInteger)maxImportSize
                                                      error:(NSError **)error {
    if (carData.length > maxImportSize) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Repository import body too large");
        return nil;
    }

    // Single streaming pass over the whole body: the strict stream reader
    // verifies every block's CID against its payload as it goes, and this
    // loop enforces the block-count bound before any database work. A
    // failure here is a clean validation error that never touches the store.
    __block NSUInteger blockCount = 0;
    if (![reader enumerateBlocksWithError:error handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
        (void)block;
        blockCount += 1;
        if (blockCount > kPDSImportRepoMaxCARBlocks) {
            if (stopError) {
                *stopError = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Repository import has too many CAR blocks");
            }
            return NO;
        }
        return YES;
    }]) {
        return nil;
    }

    ATProtoCID *computedCommitCID = [commit computeCID];
    if (!computedCommitCID || ![computedCommitCID isEqualToCID:reader.rootCID]) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Commit CID does not match CAR root");
        return nil;
    }

    if (![self validateCommitSignature:commit did:did databasePool:databasePool allowLocalKeyFallback:allowLocalKeyFallback error:error]) {
        return nil;
    }

    NSArray<PDSDatabaseRecord *> *records = [self extractRecordsFromMSTRoot:commit.dataCID
                                                                        did:did
                                                                     reader:reader
                                                                        rev:commit.rev ?: @""
                                                                      error:error];
    if (!records) {
        return nil;
    }

    PDSRepoImportValidationResult *result = [[PDSRepoImportValidationResult alloc] init];
    result.records = records;
    return result;
}

@end
