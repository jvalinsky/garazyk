#import "MSTPersistence.h"
#import "MST.h"
#import "CBOR.h"
#import "../CID.h"
#import "../Database/PDSDatabase.h"

@implementation MSTPersistence

+ (instancetype)shared {
    static MSTPersistence *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// Following ATProto reference implementation, MST persistence is handled through
// blockstore storage with root CID stored in database. Direct MST serialization
// is not needed - repositories are reconstructed from blockstore using root CID.

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    // Get root CID from database
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@"/tmp/atproto_pds.db"]];
    PDSDatabaseRepo *repoInfo = [db getRepoForDid:did error:error];
    if (!repoInfo || !repoInfo.rootCid) {
        // No repo found or no root CID, return empty MST
        return [[MST alloc] init];
    }

    // In the reference implementation, repositories are loaded from blockstore
    // using the root CID. For now, return empty MST - full blockstore
    // implementation would reconstruct the MST from stored blocks.
    return [[MST alloc] init];
}

- (BOOL)saveMST:(MST *)mst forDid:(NSString *)did error:(NSError **)error {
    // In the reference implementation, MST data is saved to blockstore
    // and only the root CID is stored in the database (handled by controller).
    // No additional MST metadata needs to be saved here.
    return YES;
}

@end
