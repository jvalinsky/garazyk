// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Blob/BlobStorage.h"
#import "Blob/PDSBlobProvider.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Blob/MimeTypeValidator.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabaseBlob.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/ATProtoServiceConfiguration.h"
#if !TARGET_OS_LINUX
#import <CommonCrypto/CommonCrypto.h>
#endif

NSString * const BlobStorageErrorDomain = @"com.atproto.blobstorage";

static const NSInteger kMaxBlobSize = 5 * 1024 * 1024; // 5MB
static const uint64_t kRawCodec = 0x55; // raw codec for blobs (per ATProto spec)

#pragma mark - Range Header Parsing Helpers

static NSString *trimmedNonEmptyString(NSString *value);
static BOOL parseUnsignedLongLongString(NSString *value,
                                        unsigned long long *result);
static BOOL parseByteRangeHeader(NSString *rangeHeader,
                                 unsigned long long totalLength, BOOL *hasRange,
                                 BOOL *satisfiable, unsigned long long *start,
                                 unsigned long long *end,
                                 NSString **failureReason);
static HttpResponseBodyChunkProducer
blobFileChunkProducer(NSString *path, unsigned long long startOffset,
                      unsigned long long endOffset, NSError **error);

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

- (nullable ATProtoCID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {

    // Validate the blob first
    if (![self validateBlob:data mimeType:mimeType error:error]) {
        return nil;
    }

    // Compute ATProtoCID for the blob data
    ATProtoCID *cid = [self computeCIDForData:data];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute CID"}];
        }
        return nil;
    }

    // The quota check and metadata insert share the actor-store transaction, so
    // concurrent uploads for the same account cannot both spend the same bytes.
    // The provider is reached only after the quota check succeeds.
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [cid bytes];
    blob.did = did;
    blob.mimeType = mimeType;
    blob.size = data.length;
    blob.createdAt = [NSDate date];
    blob.state = PDSDatabaseBlobStateTemporary;

    __block BOOL savedMetadata = NO;
    __block BOOL providerDataStored = NO;
    __block NSError *dbError = nil;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        PDSDatabaseBlob *existingBlob = [store getBlobForCID:blob.cid error:blockError];
        if (*blockError) return;
        if (existingBlob) {
            savedMetadata = YES;
            return;
        }

        if (config.blobStorageQuotaBytes > 0) {
            NSString *usageSQL = @"SELECT blob_bytes FROM account_usage WHERE did = ?";
            sqlite3_stmt *statement = [store prepareStatement:usageSQL error:blockError];
            if (!statement) return;

            sqlite3_bind_text(statement, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            int result = sqlite3_step(statement);
            unsigned long long usedBytes = 0;
            if (result == SQLITE_ROW) {
                usedBytes = (unsigned long long)sqlite3_column_int64(statement, 0);
            } else if (result != SQLITE_DONE) {
                [store finalizeStatement:statement];
                *blockError = [NSError errorWithDomain:BlobStorageErrorDomain
                                                   code:BlobStorageErrorStorageFailure
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to read account blob usage"}];
                return;
            }
            [store finalizeStatement:statement];

            unsigned long long quota = config.blobStorageQuotaBytes;
            if (data.length > quota || usedBytes > quota - data.length) {
                *blockError = [NSError errorWithDomain:BlobStorageErrorDomain
                                                   code:BlobStorageErrorQuotaExceeded
                                               userInfo:@{NSLocalizedDescriptionKey: @"Blob storage quota exceeded"}];
                return;
            }
        }

        if (![_provider hasBlobDataForCID:cid]) {
            NSError *providerError = nil;
            if (![_provider storeBlobData:data forCID:cid error:&providerError]) {
                *blockError = [NSError errorWithDomain:BlobStorageErrorDomain
                                                   code:BlobStorageErrorStorageFailure
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to store blob data",
                                                          NSUnderlyingErrorKey: providerError ?: [NSNull null]}];
                return;
            }
            providerDataStored = YES;
        }

        savedMetadata = [store saveBlob:blob error:blockError];
    } error:&dbError];

    if (!savedMetadata) {
        if (providerDataStored) {
            NSError *cleanupError = nil;
            if (![_provider deleteBlobDataForCID:cid error:&cleanupError]) {
                GZ_LOG_ERROR(@"Failed to remove blob provider data after metadata save failure: %@", cleanupError);
            }
        }
        // A quota rejection reaches this branch before the provider is written.
        if (error) {
            if (dbError) {
                *error = dbError;
            } else {
                *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                             code:BlobStorageErrorStorageFailure
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to save blob metadata"}];
            }
        }
        return nil;
    }

    return cid;
}

- (nullable NSData *)getBlobWithCID:(ATProtoCID *)cid did:(nullable NSString *)did error:(NSError **)error {
    if (did.length == 0) {
        if (error) *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                                 code:BlobStorageErrorBlobNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"A blob owner DID is required"}];
        return nil;
    }

    NSError *dbError = nil;
    PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
    if (!store) {
        if (error) *error = dbError ?: [NSError errorWithDomain:BlobStorageErrorDomain
                                                             code:BlobStorageErrorStorageFailure
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Blob metadata store is unavailable"}];
        return nil;
    }
    PDSDatabaseBlob *blobMeta = [store getBlobForCID:[cid bytes] error:&dbError];
    if (dbError || !blobMeta || ![blobMeta.state isEqualToString:PDSDatabaseBlobStateReferenced]) {
        if (error) *error = dbError ?: [NSError errorWithDomain:BlobStorageErrorDomain
                                                            code:BlobStorageErrorBlobNotFound
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Referenced blob metadata not found for user"}];
        return nil;
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

    // Verify ATProtoCID matches
    ATProtoCID *computedCID = [self computeCIDForData:data];
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

- (nullable NSString *)blobFilePathWithCID:(ATProtoCID *)cid did:(nullable NSString *)did error:(NSError **)error {
    if (did.length == 0) {
        if (error) *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                                 code:BlobStorageErrorBlobNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"A blob owner DID is required"}];
        return nil;
    }

    NSError *dbError = nil;
    PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
    if (!store) {
        if (error) *error = dbError ?: [NSError errorWithDomain:BlobStorageErrorDomain
                                                             code:BlobStorageErrorStorageFailure
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Blob metadata store is unavailable"}];
        return nil;
    }
    PDSDatabaseBlob *blobMeta = [store getBlobForCID:[cid bytes] error:&dbError];
    if (dbError || !blobMeta || ![blobMeta.state isEqualToString:PDSDatabaseBlobStateReferenced]) {
        if (error) *error = dbError ?: [NSError errorWithDomain:BlobStorageErrorDomain
                                                            code:BlobStorageErrorBlobNotFound
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Referenced blob metadata not found for user"}];
        return nil;
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
    
    NSArray<PDSDatabaseBlob *> *blobs = [store listBlobsForDid:did limit:limit cursor:cursor error:error];
    NSPredicate *referenced = [NSPredicate predicateWithBlock:^BOOL(PDSDatabaseBlob *blob, NSDictionary *bindings) {
        return [blob.state isEqualToString:PDSDatabaseBlobStateReferenced];
    }];
    return [blobs filteredArrayUsingPredicate:referenced];
}

- (BOOL)deleteBlobWithCID:(ATProtoCID *)cid did:(NSString *)did error:(NSError **)error {
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

    // Note: We do NOT delete from the provider here because other users might
    // still reference this blob (ATProto blobs are deduplicated).
    // Garbage collection of unreferenced blobs is handled separately.

    return YES;
}

- (nullable PDSDatabaseBlob *)getBlobMetadataWithCID:(NSString *)cidString did:(nullable NSString *)did error:(NSError **)error {
    if (!did) return nil;
    
    ATProtoCID *cid = [ATProtoCID cidFromString:cidString];
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

    return YES;
}

#pragma mark - ATProtoCID Computation

- (ATProtoCID *)computeCIDForData:(NSData *)data {
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

    return [ATProtoCID cidWithMultihash:multihash codec:kRawCodec];
}

#pragma mark - Helpers

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    return [NSDateFormatter atproto_stringFromDate:date];
}

#pragma mark - Range Response Helpers

- (BOOL)respondWithBlobData:(nullable NSData *)blobData
                   filePath:(nullable NSString *)filePath
                totalLength:(unsigned long long)totalLength
                 forRequest:(ATProtoHttpRequest *)request
                   response:(ATProtoHttpResponse *)response
                      error:(NSError **)outError {
    [response setHeader:@"bytes" forKey:@"Accept-Ranges"];

    BOOL hasRange = NO;
    BOOL satisfiable = YES;
    unsigned long long start = 0;
    unsigned long long end = totalLength > 0 ? (totalLength - 1) : 0;
    NSString *rangeFailureReason = nil;
    BOOL validRange = parseByteRangeHeader([request headerForKey:@"Range"],
                                           totalLength, &hasRange, &satisfiable,
                                           &start, &end, &rangeFailureReason);
    if (!validRange) {
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"InvalidRange",
        @"message" : rangeFailureReason ?: @"Range header is invalid"
      }];
      return NO;
    }

    if (hasRange && !satisfiable) {
      response.statusCode = 416;
      response.statusMessage = @"Range Not Satisfiable";
      [response
          setHeader:[NSString stringWithFormat:@"bytes */%llu", totalLength]
             forKey:@"Content-Range"];
      return YES;
    }

    if (hasRange) {
      response.statusCode = 206;
      response.statusMessage = @"Partial Content";
      [response setHeader:[NSString stringWithFormat:@"bytes %llu-%llu/%llu",
                                                     start, end, totalLength]
                   forKey:@"Content-Range"];
    } else {
      response.statusCode = 200;
    }

    if ([filePath isKindOfClass:[NSString class]] && filePath.length > 0) {
      NSError *streamError = nil;
      HttpResponseBodyChunkProducer producer =
          blobFileChunkProducer(filePath, start, end, &streamError);
      if (!producer) {
        response.statusCode = 500;
        [response setJsonBody:@{
          @"error" : @"BlobReadFailed",
          @"message" : streamError.localizedDescription
              ?: @"Failed to stream blob"
        }];
        return NO;
      }
      [response setBodyChunkProducer:producer chunkedTransferEncoding:YES];
      return YES;
    }

    if (![blobData isKindOfClass:[NSData class]]) {
      response.statusCode = 500;
      [response setJsonBody:@{
        @"error" : @"BlobReadFailed",
        @"message" : @"Blob payload unavailable"
      }];
      return NO;
    }

    if (hasRange) {
      NSUInteger offset = (NSUInteger)start;
      NSUInteger length = (NSUInteger)(end - start + 1);
      [response
          setBodyData:[blobData subdataWithRange:NSMakeRange(offset, length)]];
      return YES;
    }

    [response setBodyData:blobData];
    return YES;
}

@end

#pragma mark - Range Parsing Implementation

static NSString *trimmedNonEmptyString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseUnsignedLongLongString(NSString *value,
                                        unsigned long long *result) {
  NSString *trimmed = trimmedNonEmptyString(value);
  if (trimmed.length == 0) {
    return NO;
  }

  errno = 0;
  char *end = NULL;
  unsigned long long parsed = strtoull(trimmed.UTF8String, &end, 10);
  if (errno != 0 || !end || end == trimmed.UTF8String || *end != '\0') {
    return NO;
  }

  if (result) {
    *result = parsed;
  }
  return YES;
}

static BOOL parseByteRangeHeader(NSString *rangeHeader,
                                 unsigned long long totalLength, BOOL *hasRange,
                                 BOOL *satisfiable, unsigned long long *start,
                                 unsigned long long *end,
                                 NSString **failureReason) {
  if (hasRange) {
    *hasRange = NO;
  }
  if (satisfiable) {
    *satisfiable = YES;
  }
  if (start) {
    *start = 0;
  }
  if (end) {
    *end = totalLength > 0 ? (totalLength - 1) : 0;
  }
  if (failureReason) {
    *failureReason = nil;
  }

  NSString *trimmedRange = trimmedNonEmptyString(rangeHeader);
  if (trimmedRange.length == 0) {
    return YES;
  }

  if (hasRange) {
    *hasRange = YES;
  }

  if (![trimmedRange.lowercaseString hasPrefix:@"bytes="]) {
    if (failureReason) {
      *failureReason = @"Range header must use bytes units";
    }
    return NO;
  }

  NSString *spec = [trimmedRange substringFromIndex:6];
  if ([spec containsString:@","]) {
    if (failureReason) {
      *failureReason = @"Multiple ranges are not supported";
    }
    return NO;
  }

  NSRange dashRange = [spec rangeOfString:@"-"];
  if (dashRange.location == NSNotFound) {
    if (failureReason) {
      *failureReason = @"Range header is malformed";
    }
    return NO;
  }

  NSString *startPart = [spec substringToIndex:dashRange.location];
  NSString *endPart = [spec substringFromIndex:dashRange.location + 1];
  if (startPart.length == 0 && endPart.length == 0) {
    if (failureReason) {
      *failureReason = @"Range header is malformed";
    }
    return NO;
  }

  if (totalLength == 0) {
    if (satisfiable) {
      *satisfiable = NO;
    }
    return YES;
  }

  if (startPart.length > 0) {
    unsigned long long parsedStart = 0;
    if (!parseUnsignedLongLongString(startPart, &parsedStart)) {
      if (failureReason) {
        *failureReason = @"Range start is invalid";
      }
      return NO;
    }

    unsigned long long parsedEnd = totalLength - 1;
    if (endPart.length > 0) {
      if (!parseUnsignedLongLongString(endPart, &parsedEnd)) {
        if (failureReason) {
          *failureReason = @"Range end is invalid";
        }
        return NO;
      }
    }

    if (parsedStart >= totalLength) {
      if (satisfiable) {
        *satisfiable = NO;
      }
      return YES;
    }
    if (parsedEnd < parsedStart) {
      if (satisfiable) {
        *satisfiable = NO;
      }
      return YES;
    }
    if (parsedEnd >= totalLength) {
      parsedEnd = totalLength - 1;
    }

    if (start) {
      *start = parsedStart;
    }
    if (end) {
      *end = parsedEnd;
    }
    return YES;
  }

  unsigned long long suffixLength = 0;
  if (!parseUnsignedLongLongString(endPart, &suffixLength) ||
      suffixLength == 0) {
    if (satisfiable) {
      *satisfiable = NO;
    }
    return YES;
  }

  unsigned long long parsedStart =
      (suffixLength >= totalLength) ? 0 : (totalLength - suffixLength);
  if (start) {
    *start = parsedStart;
  }
  if (end) {
    *end = totalLength - 1;
  }
  return YES;
}

static HttpResponseBodyChunkProducer
blobFileChunkProducer(NSString *path, unsigned long long startOffset,
                      unsigned long long endOffset, NSError **error) {
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!fileHandle) {
    if (error) {
      *error = [NSError errorWithDomain:@"BlobStorage"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to open blob file for streaming"
                               }];
    }
    return nil;
  }

  @try {
    [fileHandle seekToFileOffset:startOffset];
  } @catch (NSException *exception) {
    @try {
      [fileHandle closeFile];
    } @catch (NSException *closeException) {
    }
    if (error) {
      *error = [NSError errorWithDomain:@"BlobStorage"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : exception.reason
                                     ?: @"Failed to seek blob file"
                               }];
    }
    return nil;
  }

  __block NSFileHandle *capturedHandle = fileHandle;
  __block unsigned long long bytesRemaining =
      (endOffset >= startOffset) ? (endOffset - startOffset + 1) : 0;
  static const NSUInteger kBlobChunkSize = 64 * 1024;

  return ^NSData *_Nullable(NSError **producerError) {
    if (!capturedHandle || bytesRemaining == 0) {
      if (capturedHandle) {
        @try {
          [capturedHandle closeFile];
        } @catch (NSException *closeException) {
        }
        capturedHandle = nil;
      }
      return nil;
    }

    NSUInteger readLength =
        (NSUInteger)MIN((unsigned long long)kBlobChunkSize, bytesRemaining);
    NSData *chunk = [capturedHandle readDataOfLength:readLength];
    if (chunk.length == 0) {
      @try {
        [capturedHandle closeFile];
      } @catch (NSException *closeException) {
      }
      capturedHandle = nil;
      if (producerError && bytesRemaining > 0) {
        *producerError =
            [NSError errorWithDomain:@"BlobStorage"
                                code:3
                            userInfo:@{
                              NSLocalizedDescriptionKey :
                                  @"Unexpected end-of-file while streaming blob"
                            }];
      }
      return nil;
    }

    bytesRemaining -= chunk.length;
    return chunk;
  };
}
