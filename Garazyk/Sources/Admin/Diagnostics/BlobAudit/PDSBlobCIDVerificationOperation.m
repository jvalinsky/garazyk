// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobCIDVerificationOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSBlobProvider.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Core/CID.h"

@implementation PDSBlobCIDVerificationOperation

- (void)main {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self updateProgress:0.0 status:@"Starting CID verification scan..."];

    NSError *error = nil;
    NSArray<CID *> *allCIDs = [self.blobStorage.provider listAllCIDsWithError:&error];
    if (!allCIDs) {
        PDS_LOG_ERROR(@"CIDVerify: Failed to list CIDs from provider: %@", error);
        [self updateProgress:1.0 status:@"Failed to list CIDs"];
        return;
    }

    NSMutableArray *mismatchedCIDs = [NSMutableArray array];
    NSUInteger totalCIDs = allCIDs.count;
    
    for (NSUInteger i = 0; i < totalCIDs; i++) {
        if (self.isCancelled) return;

        CID *originalCID = allCIDs[i];
        [self updateProgress:(double)i / (double)totalCIDs
                      status:[NSString stringWithFormat:@"Verifying %lu/%lu: %@", (unsigned long)i+1, (unsigned long)totalCIDs, originalCID.stringValue]];

        NSData *data = [self.blobStorage.provider retrieveBlobDataForCID:originalCID error:nil];
        if (!data) {
            PDS_LOG_WARN(@"CIDVerify: Failed to retrieve data for %@", originalCID.stringValue);
            [mismatchedCIDs addObject:@{
                @"cid": originalCID.stringValue,
                @"error": @"Missing data"
            }];
            continue;
        }

        // Compute new CID from data
        // For blobs, we assume raw codec (0x55) and sha256
        CID *computedCID = [CID sha256:data];
        
        if (![computedCID isEqualToCID:originalCID]) {
            PDS_LOG_ERROR(@"CIDVerify: CID mismatch for %@ (computed %@)", originalCID.stringValue, computedCID.stringValue);
            [mismatchedCIDs addObject:@{
                @"cid": originalCID.stringValue,
                @"expected": computedCID.stringValue,
                @"error": @"Hash mismatch"
            }];
        }
    }

    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];
    NSDictionary *results = @{
        @"mismatchedCIDs": mismatchedCIDs,
        @"totalMismatched": @(mismatchedCIDs.count),
        @"scannedFiles": @(allCIDs.count),
        @"duration": @(endTime - startTime),
        @"dryRun": @(self.dryRun)
    };

    [self updateProgress:1.0 status:@"Completed"];
    [self saveResults:results error:&error];

    if (error) {
        PDS_LOG_DB_ERROR(@"Failed to save CID verification results: %@", error);
    }
}

@end
