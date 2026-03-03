# Blob Lifecycle

## Overview

This document covers the complete lifecycle of blobs in the September PDS, from upload through download to deletion. Blobs are binary files (images, videos, documents) that are content-addressed using CIDs and stored separately from repository records.

## Lifecycle Stages

```
┌─────────────────────────────────────────────────────────────┐
│                     Blob Lifecycle                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Upload                                                  │
│     ├─ Validate MIME type and size                         │
│     ├─ Compute CID (content addressing)                    │
│     ├─ Store blob data via provider                        │
│     └─ Save metadata in actor database                     │
│                                                             │
│  2. Reference                                               │
│     ├─ Include blob CID in record                          │
│     ├─ Store record in repository                          │
│     └─ Link blob to record via embed                       │
│                                                             │
│  3. Download                                                │
│     ├─ Verify user has access                              │
│     ├─ Retrieve blob data from provider                    │
│     ├─ Verify CID matches content                          │
│     └─ Stream or return blob data                          │
│                                                             │
│  4. Deletion                                                │
│     ├─ Remove blob metadata from database                  │
│     ├─ Delete blob data from provider                      │
│     └─ Update storage quota                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Upload Workflow

### XRPC Endpoint

Blobs are uploaded via the `com.atproto.repo.uploadBlob` endpoint:

```
POST /xrpc/com.atproto.repo.uploadBlob
Authorization: Bearer <access_token>
Content-Type: image/jpeg

<binary data>
```

**Source:** `ATProtoPDS/Sources/Network/XrpcRepoMethods.m` (lines 503-542)

### Upload Implementation

```objc
// 1. Extract authentication and validate user
NSString *authHeader = [request headerForKey:@"Authorization"];
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                   error:&error];

if (!did) {
    [XrpcErrorHelper setAuthenticationError:response 
                                    message:@"Invalid or missing authentication"];
    return;
}

// 2. Get blob data and MIME type from request
NSData *blobData = request.body;
NSString *contentType = [request headerForKey:@"Content-Type"];

if (!blobData || blobData.length == 0) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Empty blob data"];
    return;
}

// 3. Upload blob via service
NSError *error = nil;
NSDictionary *result = [blobService uploadBlob:blobData
                                        forDid:did
                                      mimeType:contentType ?: @"application/octet-stream"
                                         error:&error];

if (!result) {
    [XrpcErrorHelper setInternalServerError:response];
    return;
}

// 4. Return blob reference
response.statusCode = 200;
response.body = [NSJSONSerialization dataWithJSONObject:result 
                                                options:0 
                                                  error:nil];
```

**Source:** `ATProtoPDS/Sources/Network/XrpcRepoMethods.m` (lines 503-542)

### Service Layer Upload

The `PDSBlobService` coordinates the upload:

```objc
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error {

    // Upload to storage backend
    CID *cid = [self.blobStorage uploadBlob:blobData 
                                   mimeType:mimeType 
                                        did:did 
                                      error:error];
    if (!cid) {
        return nil;
    }
    
    NSString *cidString = cid.stringValue;

    // Return blob reference for use in records
    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{@"$link": cidString},
            @"mimeType": mimeType,
            @"size": @(blobData.length)
        }
    };
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 32-56)

### Storage Backend Upload

The `BlobStorage` class handles validation, CID computation, and persistence:

```objc
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {

    // 1. Validate the blob (MIME type, size, magic bytes)
    if (![self validateBlob:data mimeType:mimeType error:error]) {
        return nil;
    }

    // 2. Compute CID for the blob data
    CID *cid = [self computeCIDForData:data];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Failed to compute CID"}];
        }
        return nil;
    }

    // 3. Check if blob already exists (deduplication)
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (store) {
        PDSDatabaseBlob *existingBlob = [store getBlobForCID:[cid bytes] 
                                                       error:error];
        if (existingBlob) {
            return cid; // Already uploaded
        }
    }

    // 4. Store data via provider (file system, S3, etc.)
    if (![_provider hasBlobDataForCID:cid]) {
        NSError *providerError = nil;
        if (![_provider storeBlobData:data forCID:cid error:&providerError]) {
            if (error) {
                *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                             code:BlobStorageErrorStorageFailure
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"Failed to store blob data",
                    NSUnderlyingErrorKey: providerError
                }];
            }
            return nil;
        }
    }

    // 5. Store blob metadata in database
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [cid bytes];
    blob.did = did;
    blob.mimeType = mimeType;
    blob.size = data.length;
    blob.createdAt = [NSDate date];

    __block BOOL success = NO;
    __block NSError *dbError = nil;
    [_databasePool transactWithDid:did 
                             block:^(id<PDSActorStoreTransactor> transactor, 
                                    NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store saveBlob:blob error:blockError];
    } error:&dbError];

    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to save blob metadata",
                NSUnderlyingErrorKey: dbError ?: [NSNull null]
            }];
        }
        return nil;
    }

    return cid;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 43-130)

### Validation

Blobs are validated before storage:

```objc
- (BOOL)validateBlob:(NSData *)data 
            mimeType:(NSString *)mimeType 
               error:(NSError **)error {
    
    MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];

    // 1. Validate MIME type format
    NSError *mimeError = nil;
    if (![validator isValidMimeType:mimeType error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorInvalidMIMEType
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription 
                                          ?: @"Invalid MIME type",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    // 2. Check if MIME type is supported
    if (![validator isSupportedMimeType:mimeType error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorInvalidMIMEType
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription 
                                          ?: @"Unsupported MIME type",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    // 3. Validate size limits
    if (![validator validateSize:data.length 
                     forMimeType:mimeType 
                           error:&mimeError]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorFileTooLarge
                                     userInfo:@{
                NSLocalizedDescriptionKey: mimeError.localizedDescription 
                                          ?: @"File too large",
                NSUnderlyingErrorKey: mimeError ?: [NSNull null]
            }];
        }
        return NO;
    }

    // 4. Validate magic bytes (file signature)
    if (data.length >= 12) {
        if (![validator validateMagicNumbers:data 
                                 forMimeType:mimeType 
                                       error:&mimeError]) {
            if (error) {
                *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                             code:BlobStorageErrorInvalidMIMEType
                                         userInfo:@{
                    NSLocalizedDescriptionKey: mimeError.localizedDescription 
                                              ?: @"Magic number mismatch",
                    NSUnderlyingErrorKey: mimeError ?: [NSNull null]
                }];
            }
            return NO;
        }
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 280-350)

### CID Computation

Blobs use CIDv1 with raw codec (0x55) and SHA-256 hashing:

```objc
- (CID *)computeCIDForData:(NSData *)data {
    // Create multihash: <algorithm><length><digest>
    // Algorithm 0x12 = sha2-256
    // Length is always 32 for sha256
    NSMutableData *multihash = [NSMutableData data];
    uint8_t algorithm = 0x12; // sha2-256
    uint8_t length = 32;
    [multihash appendBytes:&algorithm length:1];
    [multihash appendBytes:&length length:1];

    // Compute SHA-256 digest
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    [multihash appendBytes:digest length:CC_SHA256_DIGEST_LENGTH];

    // Create CIDv1 with raw codec (0x55)
    return [CID cidWithMultihash:multihash codec:0x55];
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 352-370)

## Download Workflow

### XRPC Endpoint

Blobs are downloaded via the `com.atproto.sync.getBlob` endpoint:

```
GET /xrpc/com.atproto.sync.getBlob?did=<did>&cid=<cid>
```

### Download Implementation

```objc
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                     error:(NSError **)error {

    // 1. Parse CID
    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" 
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Invalid CID format"}];
        }
        return nil;
    }

    // 2. Retrieve blob data from storage
    NSData *blobData = [self.blobStorage getBlobWithCID:cid 
                                                    did:did 
                                                  error:error];
    if (!blobData) {
        return nil;
    }

    // 3. Get metadata
    PDSDatabaseBlob *metadata = [self.blobStorage getBlobMetadataWithCID:cid.stringValue 
                                                                      did:did 
                                                                    error:nil];
    NSString *mimeType = metadata.mimeType ?: @"application/octet-stream";
    NSNumber *blobSize = metadata ? @(metadata.size) : nil;

    // 4. Return blob with metadata
    return @{
        @"blob": blobData,
        @"mimeType": mimeType,
        @"size": blobSize ?: @(blobData.length)
    };
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 58-86)

### Storage Backend Download

```objc
- (nullable NSData *)getBlobWithCID:(CID *)cid 
                                did:(nullable NSString *)did 
                              error:(NSError **)error {
    
    // 1. Check metadata exists (if DID provided)
    if (did) {
        NSError *dbError = nil;
        PDSActorStore *store = [_databasePool storeForDid:did error:&dbError];
        if (store) {
            PDSDatabaseBlob *blobMeta = [store getBlobForCID:[cid bytes] 
                                                       error:&dbError];
            if (!blobMeta) {
                if (error) {
                    *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                                 code:BlobStorageErrorBlobNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                       @"Blob metadata not found for user"}];
                }
                return nil;
            }
        }
    }

    // 2. Check provider has blob data
    if (![_provider hasBlobDataForCID:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorBlobNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Blob data not found"}];
        }
        return nil;
    }

    // 3. Retrieve data from provider
    NSError *providerError = nil;
    NSData *data = [_provider retrieveBlobDataForCID:cid error:&providerError];
    if (!data) {
        if (error) *error = providerError;
        return nil;
    }

    // 4. Verify CID matches (integrity check)
    CID *computedCID = [self computeCIDForData:data];
    if (!computedCID || ![computedCID isEqualToCID:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorCIDMismatch
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"CID verification failed"}];
        }
        return nil;
    }

    return data;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 132-185)

### Streaming Download

For large blobs, streaming is more efficient:

```objc
- (nullable NSDictionary *)getBlobStreamWithCID:(NSString *)cidString
                                            did:(NSString *)did
                                          error:(NSError **)error {
    
    // 1. Parse CID
    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Invalid CID format"}];
        }
        return nil;
    }

    // 2. Get metadata
    PDSDatabaseBlob *metadata = [self.blobStorage getBlobMetadataWithCID:cid.stringValue 
                                                                      did:did 
                                                                    error:error];
    if (!metadata) {
        return nil;
    }

    // 3. Get file path for streaming
    NSString *filePath = [self.blobStorage blobFilePathWithCID:cid 
                                                            did:did 
                                                          error:error];
    if (filePath.length == 0) {
        return nil;
    }

    // 4. Return file path and metadata for streaming
    return @{
        @"filePath": filePath,
        @"mimeType": metadata.mimeType ?: @"application/octet-stream",
        @"size": @(metadata.size)
    };
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 88-120)

## Deletion Workflow

### Service Layer Deletion

```objc
- (BOOL)deleteBlobWithCID:(NSString *)cidString 
                      did:(NSString *)did 
                    error:(NSError **)error {
    
    // 1. Parse CID
    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" 
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                               @"Invalid CID format"}];
        }
        return NO;
    }

    // 2. Delete via storage backend
    return [self.blobStorage deleteBlobWithCID:cid did:did error:error];
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 145-160)

### Storage Backend Deletion

```objc
- (BOOL)deleteBlobWithCID:(CID *)cid 
                      did:(NSString *)did 
                    error:(NSError **)error {
    
    __block BOOL success = NO;
    __block NSError *dbError = nil;
    
    // 1. Delete metadata from database (in transaction)
    [_databasePool transactWithDid:did 
                             block:^(id<PDSActorStoreTransactor> transactor, 
                                    NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteBlobForCID:[cid bytes] 
                                   forDid:did 
                                    error:blockError];
    } error:&dbError];

    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to delete blob metadata",
                NSUnderlyingErrorKey: dbError ?: [NSNull null]
            }];
        }
        return NO;
    }

    // 2. Delete blob data from provider
    NSError *providerError = nil;
    if (![self.provider deleteBlobDataForCID:cid error:&providerError]) {
        PDS_LOG_ERROR_C(PDSLogComponentBlob,
            @"Failed to delete blob data from provider for CID %@: %@",
            cid.stringValue, providerError);
        // Note: We don't fail the operation if provider deletion fails
        // Garbage collection can clean up orphaned data later
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 230-270)

## Referencing Blobs in Records

After uploading a blob, reference it in a record using an embed:

```objc
// 1. Upload image blob
NSError *error = nil;
NSDictionary *uploadResult = [blobService uploadBlob:imageData
                                              forDid:userDid
                                            mimeType:@"image/jpeg"
                                               error:&error];

if (!uploadResult) {
    NSLog(@"Image upload failed: %@", error);
    return;
}

// 2. Extract blob reference
NSDictionary *blobRef = uploadResult[@"blob"];

// 3. Create post with image embed
NSDictionary *post = @{
    @"$type": @"app.bsky.feed.post",
    @"text": @"Check out this image!",
    @"createdAt": [self iso8601StringFromDate:[NSDate date]],
    @"embed": @{
        @"$type": @"app.bsky.embed.images",
        @"images": @[
            @{
                @"image": blobRef,
                @"alt": @"Description of image"
            }
        ]
    }
};

// 4. Create record with blob reference
NSString *recordUri = [recordService createRecord:userDid
                                       collection:@"app.bsky.feed.post"
                                           rkey:nil
                                          value:post
                                          error:&error];

if (recordUri) {
    NSLog(@"Post created with image: %@", recordUri);
}
```

### Blob Reference Format

Blob references in records follow this structure:

```json
{
  "$type": "blob",
  "ref": {
    "$link": "bafkreiabcd1234..."
  },
  "mimeType": "image/jpeg",
  "size": 102400
}
```

## Listing Blobs

List all blobs for a user:

```objc
- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {

    // Get blobs from storage
    NSArray<PDSDatabaseBlob *> *blobs = [self.blobStorage listBlobsForDID:did 
                                                                     limit:limit 
                                                                    cursor:cursor 
                                                                     error:error];
    if (!blobs) {
        return @[];
    }

    // Convert to response format
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
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 122-143)

## Error Handling

### Common Error Codes

```objc
typedef NS_ENUM(NSInteger, BlobStorageError) {
    BlobStorageErrorBlobNotFound = 1,
    BlobStorageErrorInvalidMIMEType = 2,
    BlobStorageErrorFileTooLarge = 3,
    BlobStorageErrorStorageFailure = 4,
    BlobStorageErrorCIDMismatch = 5
};
```

### Error Handling Pattern

```objc
NSError *error = nil;
NSDictionary *result = [blobService uploadBlob:blobData
                                        forDid:userDid
                                      mimeType:mimeType
                                         error:&error];

if (!result) {
    switch (error.code) {
        case BlobStorageErrorInvalidMIMEType:
            NSLog(@"Invalid MIME type: %@", error.localizedDescription);
            break;
            
        case BlobStorageErrorFileTooLarge:
            NSLog(@"File too large: %@", error.localizedDescription);
            break;
            
        case BlobStorageErrorStorageFailure:
            NSLog(@"Storage failure: %@", error.localizedDescription);
            break;
            
        default:
            NSLog(@"Upload failed: %@", error.localizedDescription);
            break;
    }
    return;
}

NSLog(@"Blob uploaded successfully: %@", result[@"blob"][@"ref"][@"$link"]);
```

## Best Practices

### Upload

1. **Validate Early** — Check MIME type and size before uploading
2. **Use Transactions** — Wrap metadata updates in database transactions
3. **Handle Duplicates** — Check if blob already exists before storing
4. **Return References** — Always return blob reference for use in records

### Download

1. **Verify CID** — Always verify downloaded data matches CID
2. **Stream Large Files** — Use streaming for blobs over 1MB
3. **Check Permissions** — Verify user has access to blob
4. **Cache Metadata** — Cache blob metadata to reduce database queries

### Deletion

1. **Check References** — Verify blob is not referenced before deletion
2. **Use Transactions** — Wrap deletion in database transactions
3. **Handle Failures** — Log provider deletion failures but don't fail operation
4. **Update Quotas** — Update storage quotas after deletion

### Security

1. **Validate Content** — Check magic bytes match MIME type
2. **Enforce Limits** — Enforce size limits per MIME type
3. **Scan Content** — Consider malware scanning for user uploads
4. **Access Control** — Verify user owns blob before allowing access

## Performance Considerations

### Deduplication

Blobs with identical content share the same CID:

```objc
// Upload same data twice
CID *cid1 = [blobStorage uploadBlob:data mimeType:@"image/jpeg" did:user1 error:nil];
CID *cid2 = [blobStorage uploadBlob:data mimeType:@"image/jpeg" did:user2 error:nil];

// Both users get same CID
assert([cid1 isEqualToCID:cid2]);
```

The provider stores data once, but each user has separate metadata.

### Streaming

For large blobs, use streaming to avoid loading entire file into memory:

```objc
// Get file path for streaming
NSDictionary *streamInfo = [blobService getBlobStreamWithCID:cidString
                                                          did:userDid
                                                        error:&error];

if (streamInfo) {
    NSString *filePath = streamInfo[@"filePath"];
    
    // Stream file directly to HTTP response
    [response streamFileAtPath:filePath
                      mimeType:streamInfo[@"mimeType"]
                          size:[streamInfo[@"size"] integerValue]];
}
```

### Caching

Cache frequently accessed blobs:

```objc
// Check cache first
NSData *cachedData = [blobCache objectForKey:cid.stringValue];
if (cachedData) {
    return cachedData;
}

// Retrieve from storage
NSData *data = [blobStorage getBlobWithCID:cid did:did error:error];

// Cache for future requests
if (data) {
    [blobCache setObject:data forKey:cid.stringValue];
}

return data;
```

## See Also

- [Blob Storage](./blob-storage) — Storage architecture and providers
- [Blob Service](../03-application-layer/blob-service) — Service layer API
- [CID and Hashing](./cid-and-hashing) — Content addressing
- [Repository Basics](./repository-basics) — Repository structure
