#import "PDSBlobConsistencyCheckOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "PDSBlobAuditUtils.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSBlobProvider.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Core/CID.h"

@implementation PDSBlobConsistencyCheckOperation

- (void)main {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    [self updateProgress:0.0 status:@"Starting consistency check..."];

    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [self.serviceDatabases getAllAccountsWithError:&error];
    if (!accounts) {
        PDS_LOG_ERROR(@"ConsistencyCheck: Failed to list accounts: %@", error);
        [self updateProgress:1.0 status:@"Failed to list accounts"];
        return;
    }

    NSMutableArray *missingBlobs = [NSMutableArray array];
    NSUInteger totalAccounts = accounts.count;
    NSUInteger checkedCount = 0;

    for (NSUInteger i = 0; i < totalAccounts; i++) {
        if (self.isCancelled) return;

        PDSDatabaseAccount *account = accounts[i];
        [self updateProgress:(double)i / (double)totalAccounts
                      status:[NSString stringWithFormat:@"Checking account %lu/%lu: %@", (unsigned long)i+1, (unsigned long)totalAccounts, account.handle]];

        [self.blobStorage.databasePool readWithDid:account.did block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
            // Paginate through all records for this DID
            NSUInteger offset = 0;
            const NSUInteger limit = 1000;
            BOOL done = NO;

            while (!done && !self.isCancelled) {
                NSArray<PDSDatabaseRecord *> *records = [reader listRecordsForDid:account.did collection:nil limit:limit offset:offset error:innerError];
                if (!records || records.count == 0) {
                    done = YES;
                    continue;
                }

                for (PDSDatabaseRecord *record in records) {
                    if (self.isCancelled) break;
                    
                    if (record.value) {
                        NSData *valData = [record.value dataUsingEncoding:NSUTF8StringEncoding];
                        id json = [NSJSONSerialization JSONObjectWithData:valData options:0 error:nil];
                        if (json) {
                            NSSet<NSString *> *referencedCIDs = PDSBlobAuditBlobReferenceCIDsFromJSONObject(json);
                            for (NSString *cidStr in referencedCIDs) {
                                CID *cid = [CID cidFromString:cidStr];
                                if (!cid) continue;

                                PDSDatabaseBlob *blob = [reader getBlobForCID:[cid bytes] error:nil];
                                if (!blob) {
                                    [missingBlobs addObject:@{
                                        @"did": account.did,
                                        @"record": record.uri,
                                        @"cid": cidStr,
                                        @"error": @"Missing metadata"
                                    }];
                                } else {
                                    // 2. Check if file exists
                                    if (![self.blobStorage.provider hasBlobDataForCID:cid]) {
                                        [missingBlobs addObject:@{
                                            @"did": account.did,
                                            @"record": record.uri,
                                            @"cid": cidStr,
                                            @"error": @"Missing file"
                                        }];
                                    }
                                }
                            }
                        }
                    }
                }

                if (records.count < limit) {
                    done = YES;
                } else {
                    offset += limit;
                }
            }
        } error:nil];
    }

    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];
    NSDictionary *results = @{
        @"missingBlobs": missingBlobs,
        @"totalMissing": @(missingBlobs.count),
        @"duration": @(endTime - startTime),
        @"dryRun": @(self.dryRun)
    };

    [self updateProgress:1.0 status:@"Completed"];
    [self saveResults:results error:&error];

    if (error) {
        PDS_LOG_DB_ERROR(@"Failed to save consistency check results: %@", error);
    }
}

@end
