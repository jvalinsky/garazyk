// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService+RecordMaterializer.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Repository/CBOR.h"
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

@implementation PDSRepositoryService (RecordMaterializer)

#pragma mark - Record Loading

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error {
    NSMutableArray<PDSDatabaseRecord *> *allRecords = [NSMutableArray array];
    const NSUInteger pageSize = 1000;
    NSUInteger offset = 0;
    const NSUInteger maxIterations = 100; // Public sync export cap: 100k records.
    NSUInteger iterations = 0;
    BOOL reachedRecordCap = YES;

    while (iterations++ < maxIterations) {
        NSArray<PDSDatabaseRecord *> *page = [store listRecordsForDid:did
                                                                collection:nil
                                                                     limit:pageSize
                                                                    offset:offset
                                                                     error:error];
        if (!page) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo"
                                             code:6
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to list repository records"}];
            }
            return nil;
        }

        [allRecords addObjectsFromArray:page];
        if (page.count < pageSize) {
            reachedRecordCap = NO;
            break;
        }
        offset += pageSize;
    }

    if (reachedRecordCap) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:413
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository export exceeds 100000 record safety cap"}];
        }
        return nil;
    }

    return allRecords;
}

#pragma mark - Record Block Data

- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record {
    if (!record.cid) {
        return nil;
    }

    // 1. Try to fetch from ipld_blocks first (canonical store)
    PDSActorStore *store = [self.databasePool storeForDid:record.did error:nil];
    if (store) {
        CID *cid = [CID cidFromString:record.cid];
        if (cid) {
            NSData *blockData = [store getBlockForCID:cid.bytes forDid:record.did error:nil];
            if (blockData.length > 0) {
                return blockData;
            }
        }
    }

    // 2. Fallback to materializing from JSON (legacy/self-healing)
    if (record.value.length == 0) {
        return nil;
    }

    NSData *jsonData = [record.value dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        return nil;
    }

    NSError *jsonError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    if (!jsonObject || jsonError) {
        return nil;
    }

    NSError *cborError = nil;
    NSData *cborData = [ATProtoDagCBOR encodeJSONObject:jsonObject error:&cborError];
    if (!cborData || cborError) {
        return nil;
    }

    CID *expectedCID = [CID cidFromString:record.cid];
    if (!expectedCID) {
        return nil;
    }

    CID *actualCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
    if (!actualCID || ![actualCID isEqualToCID:expectedCID]) {
        return nil;
    }

    return cborData;
}

#pragma mark - CID Link Value

- (CBORValue *)cidLinkValueForCID:(CID *)cid {
    NSMutableData *cidBytes = [NSMutableData dataWithCapacity:1 + cid.bytes.length];
    uint8_t marker = 0x00;
    [cidBytes appendBytes:&marker length:1];
    [cidBytes appendData:cid.bytes];
    return [CBORValue tag:42 value:[CBORValue byteString:cidBytes]];
}

@end
