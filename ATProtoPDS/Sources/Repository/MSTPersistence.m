#import "Repository/MSTPersistence.h"
#import "Repository/MST.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"

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
    return YES;
}

- (BOOL)saveMSTNode:(MSTNode *)node withCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error {
    return YES;
}

- (nullable MSTNode *)loadMSTNodeWithCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error {
    return [[MSTNode alloc] init];
}

- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error {
    return YES;
}

@end
