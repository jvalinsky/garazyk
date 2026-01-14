/*!
 @file BlobStorage.m

 @abstract Blob storage implementation with file system persistence.

 @discussion Stores blobs in a hierarchical directory structure based on CID prefix,
 validates blobs against ATProto constraints, and maintains metadata in SQLite.
 Computes CIDv1 with raw codec and verifies integrity on retrieval.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Blob/BlobStorage.h"
#import "Debug/PDSLogger.h"
#import "Blob/MimeTypeValidator.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import <CommonCrypto/CommonCrypto.h>

NSString * const BlobStorageErrorDomain = @"com.atproto.blobstorage";

static const NSInteger kMaxBlobSize = 5 * 1024 * 1024; // 5MB
static const uint64_t kRawCodec = 0x55; // raw codec for blobs (per ATProto spec)

@interface BlobStorage ()

@property (nonatomic, strong) NSFileManager *fileManager;

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

- (instancetype)initWithDatabase:(PDSDatabase *)database storageDirectory:(NSURL *)storageDirectory {
    self = [super init];
    if (self) {
        _database = database;
        _storageDirectory = storageDirectory;
        _fileManager = [NSFileManager defaultManager];

        // Create storage directory if it doesn't exist
        NSError *createError = nil;
        if (![_fileManager createDirectoryAtURL:storageDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&createError]) {
            PDS_LOG_ERROR_C(PDSLogComponentBlob, @"Failed to create blob storage directory: %@", createError);
        }
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

    NSString *cidString = [cid stringValue];

    // Check if blob already exists
    NSError *dbError = nil;
    PDSDatabaseBlob *existingBlob = [_database getBlobWithCid:[cid bytes] error:&dbError];
    if (existingBlob) {
        // Blob already exists, return existing CID
    return cid;
    }

    // Store the blob file
    NSURL *blobURL = [self blobURLForCID:cid];
    if (![_fileManager createDirectoryAtURL:[blobURL URLByDeletingLastPathComponent]
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&dbError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create blob directory",
                                                NSUnderlyingErrorKey: dbError}];
        }
        return nil;
    }

    if (![data writeToURL:blobURL options:NSDataWritingAtomic error:&dbError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to write blob data",
                                                NSUnderlyingErrorKey: dbError}];
        }
        return nil;
    }

    // Store blob metadata in database
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [cid bytes];
    blob.did = did;
    blob.mimeType = mimeType;
    blob.size = data.length;
    blob.createdAt = [NSDate date];

    if (![_database saveBlob:blob error:&dbError]) {
        // Clean up the file if database save failed
        [_fileManager removeItemAtURL:blobURL error:nil];
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save blob metadata",
                                                NSUnderlyingErrorKey: dbError}];
        }
        return nil;
    }

    return cid;
}

- (nullable NSData *)getBlobWithCID:(CID *)cid error:(NSError **)error {
    NSURL *blobURL = [self blobURLForCID:cid];

    if (![_fileManager fileExistsAtPath:blobURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
        }
        return nil;
    }

    NSError *readError = nil;
#if defined(__APPLE__)
    NSData *data = [NSData dataWithContentsOfURL:blobURL options:0 error:&readError];
#else
    NSData *data = [NSData dataWithContentsOfURL:blobURL];
    if (!data) {
        readError = [NSError errorWithDomain:@"BlobStorage" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read blob data"}];
    }
#endif

    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to read blob data",
                                                NSUnderlyingErrorKey: readError}];
        }
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

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDID:(NSString *)did
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {

    NSError *dbError = nil;
    // Convert cursor to offset for database query
    NSInteger offset = 0;
    if (cursor) {
        // For simplicity, assume cursor is an offset number for now
        offset = [cursor integerValue];
    }

    NSArray<PDSDatabaseBlob *> *blobs = [_database getBlobsForDid:did
                                                             limit:limit
                                                            offset:offset
                                                             error:&dbError];

    if (dbError) {
        if (error) *error = dbError;
        return nil;
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:blobs.count];
    for (PDSDatabaseBlob *blob in blobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        if (cid) {
            [result addObject:@{
                @"cid": [cid stringValue],
                @"mimeType": blob.mimeType ?: @"application/octet-stream",
                @"size": @(blob.size),
                @"createdAt": [self iso8601StringFromDate:blob.createdAt]
            }];
        }
    }

    return [result copy];
}

- (BOOL)deleteBlobWithCID:(CID *)cid did:(NSString *)did error:(NSError **)error {
    // Check if blob exists
    NSError *dbError = nil;
    PDSDatabaseBlob *blob = [_database getBlobWithCid:[cid bytes] error:&dbError];

    if (!blob) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
        }
        return NO;
    }

    // Verify ownership (optional - for now allow deletion by anyone who knows the CID)
    if (![blob.did isEqualToString:did]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
        }
        return NO;
    }

    // Delete from filesystem
    NSURL *blobURL = [self blobURLForCID:cid];
    NSError *fileError = nil;
    if (![_fileManager removeItemAtURL:blobURL error:&fileError]) {
        // Log but don't fail if file doesn't exist
        if (fileError.code != NSFileNoSuchFileError) {
            PDS_LOG_INFO_C(PDSLogComponentBlob, @"Warning: Failed to delete blob file: %@", fileError);
        }
    }

    // Delete from database
    if (![_database deleteBlob:[cid bytes] error:&dbError]) {
        if (error) *error = dbError;
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseBlob *)getBlobMetadataWithCID:(NSString *)cidString
                                                error:(NSError **)error {
    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        }
        return nil;
    }

    return [_database getBlobWithCid:[cid bytes] error:error];
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

#pragma mark - File Management

- (NSURL *)blobURLForCID:(CID *)cid {
    NSString *cidString = cid.stringValue;
    // Create a directory structure based on CID to avoid too many files in one directory
    // Use first 2 chars as directory, rest as filename
    if (cidString.length < 3) {
        return [_storageDirectory URLByAppendingPathComponent:cidString];
    }

    NSString *dirName = [cidString substringToIndex:2];
    NSString *fileName = [cidString substringFromIndex:2];

    NSURL *dirURL = [_storageDirectory URLByAppendingPathComponent:dirName];
    return [dirURL URLByAppendingPathComponent:fileName];
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