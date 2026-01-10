#import "PDSBlobService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import <CommonCrypto/CommonDigest.h>

@interface PDSBlobService ()

@end

@implementation PDSBlobService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    return [store getBlockForCID:cid forDid:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error {

    NSError *cidError;
    NSString *cidString = [self generateCIDForData:blobData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return nil;
    }

    NSData *cidData = [self cidDataFromString:cidString];

    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cidData;
    block.repoDid = did;
    block.blockData = blobData;
    block.contentType = mimeType;
    block.size = blobData.length;
    block.createdAt = [NSDate date];

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store putBlock:block forDid:did error:nil];

        if (success) {
            PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
            blob.cid = cidData;
            blob.did = did;
            blob.mimeType = mimeType;
            blob.size = blobData.length;
            blob.createdAt = [NSDate date];
            success = [store saveBlob:blob error:nil];
        }
    } error:nil];

    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to store blob"}];
        }
        return nil;
    }

    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{@"$link": cidString},
            @"mimeType": mimeType,
            @"size": @(blobData.length)
        }
    };
}

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid
                                       did:(NSString *)did
                                    error:(NSError **)error {

    NSData *cidData = [self cidDataFromString:cid];
    if (!cidData) {
        if (error) *error = [NSError errorWithDomain:@"PDSController" code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return nil;
    }

    NSData *blob = [self getBlob:cidData forDid:did error:error];
    if (!blob) return nil;

    PDSActorStore *store = [_databasePool storeForDid:did error:nil];
    PDSDatabaseBlob *metadata = [store getBlobForCID:cidData error:nil];
    NSString *mimeType = metadata.mimeType ?: @"application/octet-stream";

    return @{
        @"blob": blob,
        @"mimeType": mimeType,
        @"size": @(blob.length)
    };
}

- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {

    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return @[];

    NSArray<PDSDatabaseBlob *> *blobs = [store listBlobsForDid:did limit:limit cursor:cursor error:error];

    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseBlob *blob in blobs) {
        [result addObject:@{
            @"cid": [self base32Encode:blob.cid] ?: @"",
            @"mimeType": blob.mimeType ?: @"application/octet-stream",
            @"size": @(blob.size)
        }];
    }
    return result;
}

- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error {
    NSData *cidData = [self cidDataFromString:cid];
    if (!cidData) {
        if (error) *error = [NSError errorWithDomain:@"PDSController" code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return NO;
    }

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteBlobForCID:cidData forDid:did error:nil];
    } error:nil];

    return success;
}

#pragma mark - Private Helpers

- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    // Simple CID generation - in production use proper IPLD library
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    NSMutableString *hashString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hashString appendFormat:@"%02x", (unsigned int)hash[i]];
    }

    return [NSString stringWithFormat:@"bafyrei%@", hashString];
}

- (NSData *)cidDataFromString:(NSString *)cidString {
    // Simple CID decoding - in production use proper IPLD library
    if ([cidString hasPrefix:@"bafyrei"]) {
        NSString *hashHex = [cidString substringFromIndex:7];
        NSMutableData *data = [NSMutableData dataWithCapacity:hashHex.length / 2];

        for (NSUInteger i = 0; i < hashHex.length; i += 2) {
            NSString *byteString = [hashHex substringWithRange:NSMakeRange(i, 2)];
            unsigned char byte = (unsigned char)strtol([byteString UTF8String], NULL, 16);
            [data appendBytes:&byte length:1];
        }

        return data;
    }
    return nil;
}

- (NSString *)base32Encode:(NSData *)data {
    // Simple base32 encoding - in production use proper library
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];

    unsigned char *bytes = (unsigned char *)data.bytes;
    NSUInteger length = data.length;

    for (NSUInteger i = 0; i < length; i += 5) {
        // Simple implementation - in production use proper base32 library
        [result appendFormat:@"%c", alphabet[bytes[i] % 32]];
    }

    return result;
}

@end