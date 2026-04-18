#import "PDSBlobConsistencyCheckOperation.h"
#import "Blob/BlobStorage.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"

@implementation PDSBlobConsistencyCheckOperation

- (void)main {
    // TODO: Implement consistency check
    // For now, just return empty results
    NSMutableArray *missingFiles = [NSMutableArray array];

    NSDictionary *results = @{
        @"missingFiles": missingFiles,
        @"totalMissing": @0,
        @"checkedBlobs": @0,
        @"duration": @0,
        @"dryRun": @(self.dryRun)
    };

    [self updateProgress:1.0 status:@"Completed"];
    NSError *error = nil;
    [self saveResults:results error:&error];

    if (error) {
        PDS_LOG_DB_ERROR(@"Failed to save consistency check results: %@", error);
    }
}

@end
