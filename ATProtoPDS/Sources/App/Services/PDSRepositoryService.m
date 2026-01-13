#import "PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Repository/RepoCommit.h"
#import "Repository/CARv1Builder.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"

@implementation PDSRepositoryService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    // Load all records to rebuild MST
    // Assuming 10000 limit for now (should be paginated in real implementation)
    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did collection:nil limit:10000 offset:0 error:error];
    if (!records) return nil;
    
    MST *mst = [[MST alloc] init];
    for (PDSDatabaseRecord *record in records) {
        // Parse CID from string
        CID *cid = [CID cidFromString:record.cid];
        if (cid) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [mst put:key valueCID:cid subKey:nil];
        }
    }
    
    return mst;
}

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error {
    MST *mst = [self loadMSTForDid:did error:error];
    if (!mst) return NO;
    
    if (cid) {
        [mst put:key valueCID:cid subKey:nil];
    } else {
        [mst delete:key];
    }
    
    NSData *cbor = [mst serializeToCBOR];
    NSData *digest = [CID sha256Digest:cbor];
    CID *repoRoot = [CID cidWithMultihash:digest codec:0x71];
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return NO;
    
    __block BOOL success = NO;
    __block NSError *innerError = nil;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        success = [transactor updateRepoRoot:did rootCid:[repoRoot bytes] error:&innerError];
    } error:error];
    
    if (innerError && error) *error = innerError;
    return success;
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_databasePool getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    return [store getRepoRootForDid:did error:error];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return NO;
}

- (nullable NSData *)getRecordWithProof:(NSString *)did
                             collection:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  error:(NSError **)error {
    // Get the actor store for this DID
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    // Get the record from database - construct AT URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    PDSDatabaseRecord *record = [store getRecord:uri forDid:did error:error];
    if (!record) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }
    
    // Get the record CID
    CID *recordCid = [CID cidFromString:record.cid];
    if (!recordCid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid record CID"}];
        }
        return nil;
    }
    
    // Encode the record value as DAG-CBOR
    // The record.value should be the JSON representation of the record
    NSData *recordCBOR = [self encodeRecordToCBOR:record.value];
    if (!recordCBOR) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode record to CBOR"}];
        }
        return nil;
    }
    
    // Load the MST to get proof path
    MST *mst = [self loadMSTForDid:did error:nil];
    
    // Build the key for MST lookup (collection/rkey format)
    NSString *mstKey = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    
    // Get MST proof nodes if available
    NSArray<MSTNode *> *proofNodes = nil;
    CID *mstRootCid = nil;
    if (mst) {
        proofNodes = [mst getProofNodesForKey:mstKey];
        mstRootCid = [mst rootCID];
    }
    
    // Create a commit block that references the MST root
    // The commit is what actually gets signed and serves as the repo root
    RepoCommit *commit = nil;
    CID *commitCid = nil;
    NSData *commitCBOR = nil;
    
    if (mstRootCid) {
        commit = [RepoCommit createCommitWithDid:did
                                            data:mstRootCid
                                             rev:nil
                                            prev:nil];
        
        // Try to sign the commit with the repo's signing key
        NSData *signingKey = [store signingKeyPrivateBytesWithError:nil];
        if (signingKey) {
            NSError *signError = nil;
            if ([commit signWithPrivateKey:signingKey error:&signError]) {
                // Commit is now signed
            } else {
                // Signing failed, continue with unsigned commit
                NSLog(@"Warning: Failed to sign commit: %@", signError);
            }
        }
        
        commitCBOR = [commit serialize];
        commitCid = [commit computeCID];
    }
    
    // Determine the root CID for the CAR
    // Should be: commit -> MST root -> ... -> record
    CID *carRoot = commitCid ?: (mstRootCid ?: recordCid);
    
    CARv1Builder *builder = [CARv1Builder builderWithRoot:carRoot];
    
    // Add commit block first (it's the root)
    if (commitCid && commitCBOR) {
        [builder addBlockWithCID:commitCid data:commitCBOR];
    }
    
    // Add MST proof nodes (from root to leaf)
    if (proofNodes) {
        for (MSTNode *node in proofNodes) {
            NSData *nodeCBOR = [mst serializeNode:node];
            if (nodeCBOR) {
                // Compute CID for the node
                NSData *nodeDigest = [CID sha256Digest:nodeCBOR];
                CID *nodeCid = [CID cidWithDigest:nodeDigest codec:0x71]; // dag-cbor
                [builder addBlockWithCID:nodeCid data:nodeCBOR];
            }
        }
    }
    
    // Add the record block
    [builder addBlockWithCID:recordCid data:recordCBOR];
    
    return [builder build];
}

#pragma mark - CBOR Encoding Helpers

- (nullable NSData *)encodeRecordToCBOR:(id)value {
    if (!value) return nil;
    
    // If value is already NSData (raw CBOR), return as-is
    if ([value isKindOfClass:[NSData class]]) {
        return value;
    }
    
    // If value is a dictionary or array, encode to DAG-CBOR
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        CBORValue *cborValue = [self jsonToCBOR:value];
        if (cborValue) {
            return [cborValue encode];
        }
    }
    
    // If value is a string (JSON), parse and encode
    if ([value isKindOfClass:[NSString class]]) {
        NSData *jsonData = [value dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonError = nil;
        id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        if (jsonObj && !jsonError) {
            CBORValue *cborValue = [self jsonToCBOR:jsonObj];
            if (cborValue) {
                return [cborValue encode];
            }
        }
    }
    
    return nil;
}

- (CBORValue *)jsonToCBOR:(id)json {
    if (!json || [json isKindOfClass:[NSNull class]]) {
        return [CBORValue nilValue];
    }
    
    if ([json isKindOfClass:[NSNumber class]]) {
        NSNumber *num = json;
        // Check if it's a boolean - CBOR uses simple values 20=false, 21=true
        if (strcmp([num objCType], @encode(BOOL)) == 0) {
            return num.boolValue ? [CBORValue simple:21] : [CBORValue simple:20];
        }
        // Check if it's an integer
        if (strcmp([num objCType], @encode(int)) == 0 ||
            strcmp([num objCType], @encode(long)) == 0 ||
            strcmp([num objCType], @encode(long long)) == 0) {
            long long val = num.longLongValue;
            if (val >= 0) {
                return [CBORValue unsignedInteger:(uint64_t)val];
            } else {
                return [CBORValue negativeInteger:(int64_t)val];
            }
        }
        // Floating point
        return [CBORValue floatingPoint:num.doubleValue];
    }
    
    if ([json isKindOfClass:[NSString class]]) {
        return [CBORValue textString:json];
    }
    
    if ([json isKindOfClass:[NSArray class]]) {
        NSArray *arr = json;
        NSMutableArray<CBORValue *> *cborArr = [NSMutableArray arrayWithCapacity:arr.count];
        for (id item in arr) {
            CBORValue *cborItem = [self jsonToCBOR:item];
            if (cborItem) {
                [cborArr addObject:cborItem];
            }
        }
        return [CBORValue array:cborArr];
    }
    
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = json;
        NSMutableDictionary<CBORValue *, CBORValue *> *cborDict = [NSMutableDictionary dictionary];
        for (NSString *key in dict) {
            CBORValue *cborKey = [CBORValue textString:key];
            CBORValue *cborValue = [self jsonToCBOR:dict[key]];
            if (cborKey && cborValue) {
                cborDict[cborKey] = cborValue;
            }
        }
        return [CBORValue map:cborDict];
    }
    
    if ([json isKindOfClass:[NSData class]]) {
        return [CBORValue byteString:json];
    }
    
    return nil;
}

@end
