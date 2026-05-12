// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobOrphanScanOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "PDSBlobAuditUtils.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSBlobProvider.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Core/CID.h"
#import <sqlite3.h>

@implementation PDSBlobOrphanScanOperation

- (void)main {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self updateProgress:0.0 status:@"Starting orphan scan..."];

    NSError *error = nil;
    NSArray<CID *> *allCIDs = [self.blobStorage.provider listAllCIDsWithError:&error];
    if (!allCIDs) {
        GZ_LOG_ERROR(@"OrphanScan: Failed to list CIDs from provider: %@", error);
        [self updateProgress:1.0 status:@"Failed to list CIDs"];
        return;
    }

    NSMutableSet<NSString *> *orphanCIDs = [NSMutableSet setWithCapacity:allCIDs.count];
    for (CID *cid in allCIDs) {
        [orphanCIDs addObject:cid.stringValue];
    }

    [self updateProgress:0.1 status:[NSString stringWithFormat:@"Scanned %lu files, checking metadata...", (unsigned long)allCIDs.count]];

    NSArray<PDSDatabaseAccount *> *accounts = [self.serviceDatabases getAllAccountsWithError:&error];
    if (!accounts) {
        GZ_LOG_ERROR(@"OrphanScan: Failed to list accounts: %@", error);
        [self updateProgress:1.0 status:@"Failed to list accounts"];
        return;
    }

    NSUInteger totalAccounts = accounts.count;
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *invalidMetadataCIDs = [NSMutableArray array];
    for (NSUInteger i = 0; i < totalAccounts; i++) {
        if (self.isCancelled) return;

        PDSDatabaseAccount *account = accounts[i];
        [self updateProgress:0.1 + (0.8 * ((double)i / (double)totalAccounts))
                      status:[NSString stringWithFormat:@"Checking account %lu/%lu: %@", (unsigned long)i+1, (unsigned long)totalAccounts, account.handle]];

        NSError *readError = nil;
        [self.blobStorage.databasePool readWithDid:account.did block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
            NSString *cursor = nil;
            BOOL done = NO;
            while (!done && !self.isCancelled) {
                NSArray<PDSDatabaseBlob *> *blobs = [reader listBlobsForDid:account.did limit:1000 cursor:cursor error:innerError];
                if (!blobs) {
                    done = YES;
                    continue;
                }

                for (PDSDatabaseBlob *blob in blobs) {
                    NSString *cidString = PDSBlobAuditCIDStringFromRawBytes(blob.cid);
                    if (cidString.length > 0) {
                        [orphanCIDs removeObject:cidString];
                    } else {
                        NSString *rawCID = PDSBlobAuditCursorFromRawBytes(blob.cid) ?: @"";
                        [invalidMetadataCIDs addObject:@{
                            @"did": account.did ?: @"",
                            @"cidBase64": rawCID
                        }];
                    }
                }

                if (blobs.count < 1000) {
                    done = YES;
                } else {
                    cursor = PDSBlobAuditCursorFromRawBytes(blobs.lastObject.cid);
                    if (!cursor) {
                        done = YES;
                    }
                }
            }
        } error:&readError];
        if (readError) {
            GZ_LOG_ERROR(@"OrphanScan: Failed to read account %@: %@", account.did, readError);
        }
    }

    NSMutableArray *orphanedFiles = [[orphanCIDs allObjects] mutableCopy];
    [orphanedFiles sortUsingSelector:@selector(compare:)];

    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];
    NSDictionary *results = @{
        @"orphanedFiles": orphanedFiles,
        @"totalOrphans": @(orphanedFiles.count),
        @"totalSizeMB": @0, // We could sum up sizes but listAllCIDs doesn't provide them easily
        @"scannedFiles": @(allCIDs.count),
        @"invalidMetadataCIDs": invalidMetadataCIDs,
        @"duration": @(endTime - startTime),
        @"dryRun": @(self.dryRun)
    };

    [self updateProgress:1.0 status:@"Completed"];
    [self saveResults:results error:&error];

    if (error) {
        GZ_LOG_DB_ERROR(@"Failed to save orphan scan results: %@", error);
    }
}

@end
