#import "Blob/BlobStorage.h"
#import "Blob/PDSBlobProvider.h"
#import "Debug/PDSLogger.h"
#import "Blob/MimeTypeValidator.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import <CommonCrypto/CommonCrypto.h>

NSString * const BlobStorageErrorDomain = @"com.atproto.blobstorage";

static const NSInteger kMaxBlobSize = 5 * 1024 * 1024; // 5MB
static const uint64_t kRawCodec = 0x55; // raw codec for blobs (per ATProto spec)

@interface BlobStorage ()

@end

@implementation BlobStorage

+ (instancetype)sharedStorage {
    static BlobStorage *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // This will need to be initialized properly in the app
        sharedInstance = [[BlobStorage alloc] init];
    });
    return sharedInstance;
}

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool provider:(id<PDSBlobProvider>)provider {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
        _provider = provider;
    }
    return self;
}

#pragma mark - Blob Operations

- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {

    // Validate the blob first
    if (![self validateBlob:data mimeType:mimeType error:error]) {
        return nil;
    }

    // Compute CID for the blob data
    CID *cid = [self computeCIDForData:data];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute CID"}];
        }
        return nil;
    }

    // Check if blob already exists in DB (User's DB)
    __block NSError *dbError = nil;
    __block PDSDatabaseBlob *existingBlob = nil;
    
    // We can't easily check 'all' databases, so we check this user's DB.
    // If another user uploaded it, we might duplicate data storage call to provider,
    // but provider 'storeBlobData' should be idempotent/deduplicating.
    PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
    if (store) {
        existingBlob = [store getBlobForCID:[cid bytes] error:&dbError];
    }
    
    if (existingBlob) {
        return cid;
    }

    // Check if provider has it (for consistency)
    if (![_provider hasBlobDataForCID:cid]) {
        // Store data via provider
        NSError *providerError = nil;
        if (![_provider storeBlobData:data forCID:cid error:&providerError]) {
            if (error) {
                *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                             code:BlobStorageErrorStorageFailure
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to store blob data",
                                                    NSUnderlyingErrorKey: providerError}];
            }
            return nil;
        }
    }

    // Store blob metadata in database using transaction
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [cid bytes];
    blob.did = did;
    blob.mimeType = mimeType;
    blob.size = data.length;
    blob.createdAt = [NSDate date];

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store saveBlob:blob error:blockError];
    } error:&dbError];

    if (!success) {
        // We do NOT delete from provider here typically, as another user might rely on it.
        // Garbage collection is a separate concern.
        
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save blob metadata",
                                                NSUnderlyingErrorKey: dbError ?: [NSNull null]}];
        }
        return nil;
    }

    return cid;
}

- (nullable NSData *)getBlobWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error {
    // If DID is provided, we can optionally check metadata existence
    if (did) {
        NSError *dbError = nil;
        PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
        if (store) {
            PDSDatabaseBlob *blobMeta = [store getBlobForCID:[cid bytes] error:&dbError];
            if (!blobMeta) {
                 if (error) {
                    *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                                  code:BlobStorageErrorBlobNotFound
                                              userInfo:@{NSLocalizedDescriptionKey: @"Blob metadata not found for user"}];
                }
                return nil;
            }
        }
    }

    // Retrieve data from provider
    if (![_provider hasBlobDataForCID:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorBlobNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob data not found"}];
        }
        return nil;
    }

    NSError *providerError = nil;
    NSData *data = [_provider retrieveBlobDataForCID:cid error:&providerError];
    if (!data) {
        if (error) *error = providerError;
        return nil;
    }

    // Verify CID matches
    CID *computedCID = [self computeCIDForData:data];
    if (!computedCID || ![computedCID isEqualToCID:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorCIDMismatch
                                     userInfo:@{NSLocalizedDescriptionKey: @"CID verification failed"}];
        }
        return nil;
    }

    return data;
}

- (nullable NSString *)blobFilePathWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error {
    if (did) {
        NSError *dbError = nil;
        PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
        if (store) {
            PDSDatabaseBlob *blobMeta = [store getBlobForCID:[cid bytes] error:&dbError];
            if (!blobMeta) {
                if (error) {
                    *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                                 code:BlobStorageErrorBlobNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"Blob metadata not found for user"}];
                }
                return nil;
            }
        }
    }

    if (![_provider hasBlobDataForCID:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorBlobNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob data not found"}];
        }
        return nil;
    }

    if ([_provider respondsToSelector:@selector(blobFileURLForCID:error:)]) {
        NSError *providerError = nil;
        NSURL *fileURL = [_provider blobFileURLForCID:cid error:&providerError];
        if (fileURL.path.length > 0) {
            return fileURL.path;
        }
        if (providerError && error) {
            *error = providerError;
        }
    }

    return nil;
}

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDID:(NSString *)did
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {

    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return @[];
    
    return [store listBlobsForDid:did limit:limit cursor:cursor error:error];
}

- (BOOL)deleteBlobWithCID:(CID *)cid did:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *dbError = nil;
    
    // Delete metadata first using transaction
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
         PDSActorStore *store = (PDSActorStore *)transactor;
         success = [store deleteBlobForCID:[cid bytes] forDid:did error:blockError];
    } error:&dbError];

    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to delete blob metadata",
                                                NSUnderlyingErrorKey: dbError ?: [NSNull null]}];
        }
        return NO;
    }

    // Optionally delete from provider if we implement ref-counting or garbage collection later.
    // For now, consistent with keeping datasafe.
    
    return YES;
}

- (nullable PDSDatabaseBlob *)getBlobMetadataWithCID:(NSString *)cidString did:(nullable NSString *)did error:(NSError **)error {
    if (!did) return nil;
    
    CID *cid = [CID cidFromString:cidString];
    if (!cid) return nil;
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    return [store getBlobForCID:[cid bytes] error:error];
}

#pragma mark - Validation

- (BOOL)validateBlob:(NSData *)data mimeType:(NSString *)mimeType error:(NSError **)error {
    MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];

    NSError *mimeError = nil;
    if (![validator isValidMimeType:mimeType error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorInvalidMIMEType
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription ?: @"Invalid MIME type",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    if (![validator isSupportedMimeType:mimeType error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorInvalidMIMEType
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription ?: @"Unsupported MIME type",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    if (![validator validateSize:data.length forMimeType:mimeType error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileTooLarge
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription ?: @"File too large",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    if (data.length >= 12) {
        if (![validator validateMagicNumbers:data forMimeType:mimeType error:&mimeError]) {
            if (error) {
                *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                             code:BlobStorageErrorInvalidMIMEType
                                         userInfo:@{
                    NSLocalizedDescriptionKey: mimeError.localizedDescription ?: @"Magic number mismatch",
                    NSUnderlyingErrorKey: mimeError ?: [NSNull null]
                }];
            }
            return NO;
        }
    }

    return YES;
}

#pragma mark - CID Computation

- (CID *)computeCIDForData:(NSData *)data {
    // Create multihash: <algorithm><length><digest>
    // Algorithm 0x12 = sha2-256
    // Length is always 32 for sha256
    NSMutableData *multihash = [NSMutableData data];
    uint8_t algorithm = 0x12; // sha2-256
    uint8_t length = 32;
    [multihash appendBytes:&algorithm length:1];
    [multihash appendBytes:&length length:1];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    [multihash appendBytes:digest length:CC_SHA256_DIGEST_LENGTH];

    return [CID cidWithMultihash:multihash codec:kRawCodec];
}

#pragma mark - Helpers

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    });
    return [formatter stringFromDate:date];
}

@end
