#import "PDSBlobService.h"
#import "Blob/BlobStorage.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoBase32.h"
#import <CommonCrypto/CommonDigest.h>

@interface PDSBlobService ()

@end

@implementation PDSBlobService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool storage:(BlobStorage *)storage {
    if (self = [super init]) {
        _databasePool = databasePool;
        _blobStorage = storage;
    }
    return self;
}

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cidData forDid:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromBytes:cidData];
    if (!cid) return nil;
    return [self.blobStorage getBlobWithCID:cid did:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error {

    CID *cid = [self.blobStorage uploadBlob:blobData mimeType:mimeType did:did error:error];
    if (!cid) {
        return nil;
    }
    
    NSString *cidString = cid.stringValue;

    // We no longer need to manually put block into ActorStore, BlobStorage handles generic storage.
    // However, if the old logic put BLOBS as BLOCKS, do we need to emulate that?
    // The previous implementation put the blob as a block in the ActorStore. 
    // If the system expects blobs to be readable via `getRecord` or `getBlock`, we might break that.
    // BUT: Blobs are usually separate from the Repo MST blocks.
    // `PDSBlobService` was using `putBlock` likely because it lacked a real blob store.
    
    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{@"$link": cidString},
            @"mimeType": mimeType,
            @"size": @(blobData.length)
        }
    };
}

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                     error:(NSError **)error {

    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"PDSController" code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return nil;
    }

    NSData *blobData = [self.blobStorage getBlobWithCID:cid did:did error:error];
    if (!blobData) return nil;

    PDSDatabaseBlob *metadata = [self.blobStorage getBlobMetadataWithCID:cid.stringValue did:did error:nil];
    NSString *mimeType = metadata.mimeType ?: @"application/octet-stream";

    return @{
        @"blob": blobData,
        @"mimeType": mimeType,
        @"size": @(blobData.length)
    };
}

- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {

    NSArray<PDSDatabaseBlob *> *blobs = [self.blobStorage listBlobsForDID:did limit:limit cursor:cursor error:error];
    if (!blobs) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseBlob *blob in blobs) {
        
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidStr = cid.stringValue;
        [result addObject:@{
            @"cid": cidStr ?: @"",
            @"mimeType": blob.mimeType ?: @"application/octet-stream",
            @"size": @(blob.size)
        }];
    }
    return result;
}

- (BOOL)deleteBlobWithCID:(NSString *)cidString did:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"PDSController" code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return NO;
    }

    return [self.blobStorage deleteBlobWithCID:cid did:did error:error];
}

#pragma mark - Private Helpers

- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    // CIDv1 = version(0x01) + codec(0x71 dag-cbor) + hash_alg(0x12 sha2-256) + hash_len(0x20) + hash
    // Prefix bytes: 0x01 0x71 0x12 0x20 (for blobs we should use 0x55 raw? No, spec says sha-256)
    // Actually blobs are raw binary usually?
    // If it's a "blob" object in repo, it's a reference.
    // The blob ITSELF is stored.
    // AtProto blobs are raw data. CID is typically raw (0x55) or just sha256?
    // Spec says: "Blobs... are referenced by hash (CID)..."
    // "Blessed CID formats... for records... is CIDv1... dag-cbor"
    // But for BLOBS?
    // Usually blobs are `bafkrei...` (CIDv1, raw (0x55), sha2-256)
    // `raw` = 0x55. `dag-cbor` = 0x71.
    // If I use 0x71 for blobs, it means the blob content is DAG-CBOR? No.
    // If blob is image, it is RAW.
    // So I should use 0x55 (raw) codec for blobs?
    // Let's assume standard behavior: `raw` codec for blobs.
    // 0x55 = 85.
    
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    NSMutableData *cidData = [NSMutableData dataWithCapacity:4 + CC_SHA256_DIGEST_LENGTH];
    // Use raw codec (0x55) for blobs? Or just generic?
    // Let's stick to what was there implicitly or check spec?
    // Spec says "Large binary blobs... are not stored directly in repositories... referenced by hash".
    // If I upload an image, it is raw bytes.
    // The CID should reflect that. `bafkrei...` is typical. `k` = `0x55` (raw) in base32? No.
    // `raw` codec is 0x55.
    // `0x01` `0x55` `0x12` `0x20` ...
    // Let's use 0x55 for blobs.
    
    const unsigned char prefix[] = {0x01, 0x55, 0x12, 0x20};
    [cidData appendBytes:prefix length:4];
    [cidData appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    NSString *base32 = [ATProtoBase32 encodeData:cidData];
    return [NSString stringWithFormat:@"b%@", base32];
}

- (NSData *)cidDataFromString:(NSString *)cidString {
    if ([cidString hasPrefix:@"b"]) {
        return [ATProtoBase32 decodeString:[cidString substringFromIndex:1]];
    }
    return nil;
}

@end