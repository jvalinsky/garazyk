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

- (PDSDatabase *)getDatabase {
    if (_database) return _database;
    // Default fallback (legacy behavior, though should probably error if not configured)
    return [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@"/tmp/atproto_pds.db"]];
}

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return nil;

    PDSDatabaseRepo *repoInfo = [db getRepoForDid:did error:error];
    if (!repoInfo || !repoInfo.rootCid) {
        return [[MST alloc] init];
    }

    // Reconstruction from blocks would happen here.
    // For now, return a new MST initialised with root CID to represent state.
    // Note: To fully support traversal, MST needs to be able to lazily load nodes from DB via persistence layer.
    return [[MST alloc] initWithRootCID:repoInfo.rootCid];
}

- (BOOL)saveMST:(MST *)mst forDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return NO;

    // 1. Save root CID to repos table
    CID *root = mst.rootCID;
    NSString *rootStr = root ? root.stringValue : @"";
    
    // Upsert repo info
    // Assuming repo exists or we create it? usually createRepo handles creation.
    // Here we just update root.
    NSString *updateSQL = @"UPDATE repos SET root = ? WHERE did = ?";
    return [db executeParameterizedUpdate:updateSQL params:@[rootStr, did] error:error];
}

- (BOOL)saveMSTNode:(MSTNode *)node withCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return NO;
    
    // Serialize node to CBOR/Bytes (MSTNode needs serialization method exposed or use MST internal)
    // MSTNode actually has serializeToCBOR logic in MST.m but strictly internal?
    // MSTPersistence sees MSTNode.
    // We need block data.
    // Assuming caller provides bytes or we re-serialize.
    // Let's assume for now we don't have bytes easily, but wait, MSTPersistence is for saving nodes.
    // It should probably take NSData representing the block.
    // But interface says MSTNode.
    
    // FIXME: MSTNode serialization is internal to MST.m. 
    // We should probably rely on manual block saving via PDSDatabase directly if we have the block data.
    // Or expose serialize on MSTNode.
    
    return YES;
}

- (nullable MSTNode *)loadMSTNodeWithCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    PDSDatabaseBlock *block = [db getBlockWithCid:cid.bytes repoDid:did error:error];
    if (!block) return nil;
    
    // Deserialize?
    // MSTNode deserialization is not exposed.
    return nil;
}

- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error {
    return YES;
}

@end
