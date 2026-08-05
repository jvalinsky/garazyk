// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobReferenceScanOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "PDSBlobAuditUtils.h"
#import "Blob/BlobStorage.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"

@implementation PDSBlobReferenceScanOperation

- (void)main {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self updateProgress:0.0 status:@"Starting reference scan..."];

    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [self.serviceDatabases getAllAccountsWithError:&error];
    if (!accounts) {
        GZ_LOG_ERROR(@"ReferenceScan: Failed to list accounts: %@", error);
        [self updateProgress:1.0 status:@"Failed to list accounts"];
        return;
    }

    NSMutableArray *unreferencedBlobs = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *invalidMetadataCIDs = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *sweepCandidates = [NSMutableArray array];
    NSMutableSet<NSString *> *retainedProviderCIDs = [NSMutableSet set];
    BOOL temporarySweep = [self.auditType isEqualToString:@"temporary"];
    NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] -
        [ATProtoServiceConfiguration sharedConfiguration].blobTemporaryGracePeriodSeconds;
    NSUInteger totalReferenced = 0;
    NSUInteger totalMetadata = 0;
    NSUInteger totalAccounts = accounts.count;

    for (NSUInteger i = 0; i < totalAccounts; i++) {
        if (self.isCancelled) return;

        PDSDatabaseAccount *account = accounts[i];
        [self updateProgress:(double)i / (double)MAX(totalAccounts, 1)
                      status:[NSString stringWithFormat:@"Scanning account %lu/%lu: %@", (unsigned long)i + 1, (unsigned long)totalAccounts, account.handle]];

        NSMutableSet<NSString *> *metadataCIDs = [NSMutableSet set];
        NSMutableSet<NSString *> *referencedCIDs = [NSMutableSet set];
        NSMutableDictionary<NSString *, PDSDatabaseBlob *> *metadataByCID = [NSMutableDictionary dictionary];
        NSError *readError = nil;

        [self.blobStorage.databasePool readWithDid:account.did block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
            NSString *blobCursor = nil;
            BOOL blobsDone = NO;
            while (!blobsDone && !self.isCancelled) {
                NSArray<PDSDatabaseBlob *> *blobs = [reader listBlobsForDid:account.did limit:1000 cursor:blobCursor error:innerError];
                if (!blobs) {
                    blobsDone = YES;
                    continue;
                }

                for (PDSDatabaseBlob *blob in blobs) {
                    NSString *cidString = PDSBlobAuditCIDStringFromRawBytes(blob.cid);
                    if (cidString.length > 0) {
                        [metadataCIDs addObject:cidString];
                        metadataByCID[cidString] = blob;
                    } else {
                        NSString *rawCID = PDSBlobAuditCursorFromRawBytes(blob.cid) ?: @"";
                        [invalidMetadataCIDs addObject:@{
                            @"did": account.did ?: @"",
                            @"cidBase64": rawCID
                        }];
                    }
                }

                if (blobs.count < 1000) {
                    blobsDone = YES;
                } else {
                    blobCursor = PDSBlobAuditCursorFromRawBytes(blobs.lastObject.cid);
                    if (!blobCursor) {
                        blobsDone = YES;
                    }
                }
            }

            NSUInteger offset = 0;
            const NSUInteger limit = 1000;
            BOOL recordsDone = NO;
            while (!recordsDone && !self.isCancelled) {
                NSArray<PDSDatabaseRecord *> *records = [reader listRecordsForDid:account.did collection:nil limit:limit offset:offset error:innerError];
                if (!records || records.count == 0) {
                    recordsDone = YES;
                    continue;
                }

                for (PDSDatabaseRecord *record in records) {
                    if (record.value.length == 0) {
                        continue;
                    }

                    NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
                    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (!json) {
                        continue;
                    }

                    [referencedCIDs unionSet:PDSBlobAuditBlobReferenceCIDsFromJSONObject(json)];
                }

                if (records.count < limit) {
                    recordsDone = YES;
                } else {
                    offset += limit;
                }
            }
        } error:&readError];

        if (readError) {
            GZ_LOG_ERROR(@"ReferenceScan: Failed to read account %@: %@", account.did, readError);
            continue;
        }

        totalMetadata += metadataCIDs.count;
        totalReferenced += referencedCIDs.count;
        NSMutableSet<NSString *> *unreferenced = [metadataCIDs mutableCopy];
        [unreferenced minusSet:referencedCIDs];
        for (NSString *cidString in PDSBlobAuditSortedStrings(unreferenced)) {
            [unreferencedBlobs addObject:@{
                @"did": account.did ?: @"",
                @"cid": cidString
            }];
        }

        for (NSString *cidString in metadataCIDs) {
            PDSDatabaseBlob *blob = metadataByCID[cidString];
            BOOL eligibleTemporary = temporarySweep &&
                [blob.state isEqualToString:PDSDatabaseBlobStateTemporary] &&
                blob.createdAt.timeIntervalSince1970 <= cutoff &&
                ![referencedCIDs containsObject:cidString];
            if (eligibleTemporary) {
                [sweepCandidates addObject:@{ @"did": account.did ?: @"", @"cid": cidString }];
            } else {
                [retainedProviderCIDs addObject:cidString];
            }
        }
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *sweptBlobs = [NSMutableArray array];
    NSMutableSet<NSString *> *deletedProviderCIDs = [NSMutableSet set];
    if (temporarySweep && !self.dryRun) {
        for (NSDictionary<NSString *, id> *candidate in sweepCandidates) {
            NSString *did = candidate[@"did"];
            NSString *cidString = candidate[@"cid"];
            ATProtoCID *cid = [ATProtoCID cidFromString:cidString];
            NSError *deleteError = nil;
            if (!cid || ![self.blobStorage deleteBlobWithCID:cid did:did error:&deleteError]) {
                GZ_LOG_ERROR(@"TemporaryBlobSweep: Failed to delete metadata %@ for %@: %@", cidString, did, deleteError);
                [retainedProviderCIDs addObject:cidString];
                continue;
            }
            [sweptBlobs addObject:@{ @"did": did, @"cid": cidString }];
        }

        for (NSDictionary<NSString *, id> *candidate in sweepCandidates) {
            NSString *cidString = candidate[@"cid"];
            if ([retainedProviderCIDs containsObject:cidString] || [deletedProviderCIDs containsObject:cidString]) continue;
            ATProtoCID *cid = [ATProtoCID cidFromString:cidString];
            NSError *providerError = nil;
            if (!cid || ![self.blobStorage.provider deleteBlobDataForCID:cid error:&providerError]) {
                GZ_LOG_ERROR(@"TemporaryBlobSweep: Failed to delete provider data %@: %@", cidString, providerError);
                continue;
            }
            [deletedProviderCIDs addObject:cidString];
        }
    }

    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];

    NSDictionary *results = @{
        @"unreferencedBlobs": unreferencedBlobs,
        @"totalUnreferenced": @(unreferencedBlobs.count),
        @"totalReferenced": @(totalReferenced),
        @"totalMetadata": @(totalMetadata),
        @"invalidMetadataCIDs": invalidMetadataCIDs,
        @"sweptBlobs": sweptBlobs,
        @"totalSwept": @(sweptBlobs.count),
        @"gracePeriodSeconds": @([ATProtoServiceConfiguration sharedConfiguration].blobTemporaryGracePeriodSeconds),
        @"duration": @(endTime - startTime),
        @"dryRun": @(self.dryRun)
    };

    [self updateProgress:1.0 status:@"Completed"];
    NSError *saveError = nil;
    [self saveResults:results error:&saveError];

    if (saveError) {
        GZ_LOG_DB_ERROR(@"Failed to save reference scan results: %@", saveError);
    }
}

@end
