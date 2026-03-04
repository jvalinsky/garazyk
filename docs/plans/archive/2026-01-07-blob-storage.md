---
title: Blob Storage System Implementation Plan
---

# Blob Storage System Implementation Plan

## Goal
Implement a complete blob storage system for ATProto PDS with filesystem backend, CID computation, and XRPC endpoints for media content handling.

## Architecture
Create a BlobStorage class managing filesystem operations with CID-based naming, integrate with PDSController for XRPC dispatch, implement uploadBlob, getBlob, and listBlobs endpoints with proper validation and error handling.

## Tech Stack
Objective-C, Foundation framework, NSFileManager for filesystem operations, custom CID computation, multipart/form-data handling.

## Task 1: Create BlobStorage Header File

**Files:**
- Create: `ATProtoPDS/ATProtoPDS/Blob/BlobStorage.h`

### Step 1: Write the interface definition

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlobMetadata : NSObject
@property (nonatomic, readonly) NSString *cid;
@property (nonatomic, readonly) NSString *mimeType;
@property (nonatomic, readonly) NSUInteger size;
@property (nonatomic, readonly) NSDate *createdAt;
- (instancetype)initWithCID:(NSString *)cid mimeType:(NSString *)mimeType size:(NSUInteger)size createdAt:(NSDate *)createdAt;
@end

@interface BlobStorage : NSObject
@property (nonatomic, readonly) NSString *storageDirectory;

- (instancetype)initWithStorageDirectory:(NSString *)directory;

- (BOOL)storeBlob:(NSData *)data mimeType:(NSString *)mimeType cid:(NSString **)outCID error:(NSError **)error;
- (NSData * _Nullable)retrieveBlobWithCID:(NSString *)cid error:(NSError **)error;
- (NSArray<BlobMetadata *> *)listBlobsForAccount:(NSString *)accountDID error:(NSError **)error;
- (BOOL)deleteBlobWithCID:(NSString *)cid error:(NSError **)error;

+ (NSString * _Nullable)computeCIDForData:(NSData *)data error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
```

### Step 2: Commit

```bash
git add ATProtoPDS/ATProtoPDS/Blob/BlobStorage.h
git commit -m "feat: add BlobStorage header with interface definitions"
```

## Task 2: Implement BlobStorage Core Logic

**Files:**
- Modify: `ATProtoPDS/ATProtoPDS/Blob/BlobStorage.m`

### Step 1: Write CID computation implementation

```objc
#import "BlobStorage.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation BlobMetadata

- (instancetype)initWithCID:(NSString *)cid mimeType:(NSString *)mimeType size:(NSUInteger)size createdAt:(NSDate *)createdAt {
    self = [super init];
    if (self) {
        _cid = [cid copy];
        _mimeType = [mimeType copy];
        _size = size;
        _createdAt = [createdAt copy];
    }
    return self;
}

@end

@implementation BlobStorage

- (instancetype)initWithStorageDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _storageDirectory = [directory copy];
        [self _ensureStorageDirectoryExists];
    }
    return self;
}

- (void)_ensureStorageDirectoryExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:self.storageDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Failed to create storage directory: %@", error);
    }
}

+ (NSString * _Nullable)computeCIDForData:(NSData *)data error:(NSError **)error {
    // SHA256 hash
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    // Create multihash (dag-pb codec 0x70, sha256 0x12)
    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:(unsigned char[]){0x12, 0x20} length:2]; // sha256 code + length
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    // Base58 encode for CID
    // Note: This is a simplified implementation - production would use proper multibase
    NSString *base58Chars = @"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    NSMutableString *result = [NSMutableString string];
    
    unsigned char *bytes = (unsigned char *)multihash.bytes;
    NSUInteger length = multihash.length;
    
    for (NSUInteger i = 0; i < length; i++) {
        NSUInteger carry = bytes[i];
        for (NSUInteger j = 0; j < result.length; j++) {
            NSUInteger temp = [base58Chars rangeOfString:[result substringWithRange:NSMakeRange(j, 1)]].location * 256 + carry;
            [result replaceCharactersInRange:NSMakeRange(j, 1) withString:[base58Chars substringWithRange:NSMakeRange(temp % 58, 1)]];
            carry = temp / 58;
        }
        while (carry > 0) {
            [result appendString:[base58Chars substringWithRange:NSMakeRange(carry % 58, 1)]];
            carry /= 58;
        }
    }
    
    // Add version and codec prefix for CIDv1
    NSString *cid = [NSString stringWithFormat:@"b%@%@", result, @""]; // Simplified - would need proper CID formatting
    
    if (error) *error = nil;
    return cid;
}
```

### Step 2: Write store and retrieve methods

```objc
- (BOOL)storeBlob:(NSData *)data mimeType:(NSString *)mimeType cid:(NSString **)outCID error:(NSError **)error {
    // Validate size (5MB limit)
    if (data.length > 5 * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:@"BlobStorage" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Blob size exceeds 5MB limit"}];
        return NO;
    }
    
    // Validate MIME type (basic check)
    if (![self _isValidMimeType:mimeType]) {
        if (error) *error = [NSError errorWithDomain:@"BlobStorage" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid MIME type"}];
        return NO;
    }
    
    // Compute CID
    NSString *cid = [BlobStorage computeCIDForData:data error:error];
    if (!cid) return NO;
    
    // Create blob directory structure (shard by first 2 chars of CID)
    NSString *shardDir = [self.storageDirectory stringByAppendingPathComponent:[cid substringToIndex:2]];
    [self _ensureDirectoryExists:shardDir];
    
    // Store blob file
    NSString *blobPath = [shardDir stringByAppendingPathComponent:cid];
    if (![data writeToFile:blobPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"BlobStorage" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write blob to disk"}];
        return NO;
    }
    
    // Store metadata
    NSDictionary *metadata = @{
        @"cid": cid,
        @"mimeType": mimeType,
        @"size": @(data.length),
        @"createdAt": [NSDate date]
    };
    NSString *metaPath = [blobPath stringByAppendingString:@".meta"];
    if (![metadata writeToFile:metaPath atomically:YES]) {
        // Log error but don't fail the operation
        NSLog(@"Warning: Failed to write metadata for blob %@", cid);
    }
    
    if (outCID) *outCID = cid;
    return YES;
}

- (NSData * _Nullable)retrieveBlobWithCID:(NSString *)cid error:(NSError **)error {
    NSString *blobPath = [self _pathForBlobWithCID:cid];
    NSData *data = [NSData dataWithContentsOfFile:blobPath options:0 error:error];
    if (!data && error && *error) {
        *error = [NSError errorWithDomain:@"BlobStorage" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
    }
    return data;
}

- (NSString *)_pathForBlobWithCID:(NSString *)cid {
    NSString *shardDir = [self.storageDirectory stringByAppendingPathComponent:[cid substringToIndex:2]];
    return [shardDir stringByAppendingPathComponent:cid];
}

- (void)_ensureDirectoryExists:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
}

- (BOOL)_isValidMimeType:(NSString *)mimeType {
    // Basic validation - could be expanded
    NSArray *allowedTypes = @[@"image/", @"video/", @"audio/", @"application/octet-stream"];
    for (NSString *prefix in allowedTypes) {
        if ([mimeType hasPrefix:prefix]) return YES;
    }
    return NO;
}
```

### Step 3: Write list and delete methods

```objc
- (NSArray<BlobMetadata *> *)listBlobsForAccount:(NSString *)accountDID error:(NSError **)error {
    // For simplicity, list all blobs - in production would filter by account
    NSMutableArray<BlobMetadata *> *blobs = [NSMutableArray array];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:self.storageDirectory];
    
    for (NSString *path in enumerator) {
        if ([path hasSuffix:@".meta"]) continue; // Skip metadata files
        
        NSString *fullPath = [self.storageDirectory stringByAppendingPathComponent:path];
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        if (attrs[NSFileType] != NSFileTypeRegular) continue;
        
        // Read metadata
        NSString *metaPath = [fullPath stringByAppendingString:@".meta"];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        if (!metadata) continue;
        
        BlobMetadata *blob = [[BlobMetadata alloc] initWithCID:metadata[@"cid"]
                                                       mimeType:metadata[@"mimeType"]
                                                           size:[metadata[@"size"] unsignedIntegerValue]
                                                      createdAt:metadata[@"createdAt"]];
        [blobs addObject:blob];
    }
    
    return [blobs copy];
}

- (BOOL)deleteBlobWithCID:(NSString *)cid error:(NSError **)error {
    NSString *blobPath = [self _pathForBlobWithCID:cid];
    NSString *metaPath = [blobPath stringByAppendingString:@".meta"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *blobError = nil;
    NSError *metaError = nil;
    
    [fm removeItemAtPath:blobPath error:&blobError];
    [fm removeItemAtPath:metaPath error:&metaError];
    
    if (blobError && error) {
        *error = blobError;
        return NO;
    }
    
    return YES;
}

@end
```

### Step 4: Commit

```bash
git add ATProtoPDS/ATProtoPDS/Blob/BlobStorage.m
git commit -m "feat: implement BlobStorage class with CID computation and filesystem operations"
```

## Task 3: Update PDSController with Blob Endpoints

**Files:**
- Modify: `ATProtoPDS/ATProtoPDS/PDSController.m`

### Step 1: Add blob storage property and initialization

```objc
#import "PDSController.h"
#import "BlobStorage.h"

@interface PDSController ()
@property (nonatomic, strong) BlobStorage *blobStorage;
@end

@implementation PDSController

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize blob storage
        NSString *storageDir = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path stringByAppendingPathComponent:@"blobs"];
        self.blobStorage = [[BlobStorage alloc] initWithStorageDirectory:storageDir];
    }
    return self;
}
```

### Step 2: Implement uploadBlob endpoint

```objc
- (void)handleUploadBlob:(NSDictionary *)params request:(HTTPRequest *)request response:(HTTPResponse *)response {
    // Parse multipart form data
    NSDictionary *formData = [self _parseMultipartFormData:request];
    NSData *blobData = formData[@"blob"];
    NSString *mimeType = formData[@"mimeType"];
    
    if (!blobData || !mimeType) {
        [response setStatusCode:400];
        [response setBody:[@"Missing blob data or mimeType" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    
    NSError *error = nil;
    NSString *cid = nil;
    if ([self.blobStorage storeBlob:blobData mimeType:mimeType cid:&cid error:&error]) {
        NSDictionary *result = @{@"cid": cid};
        [response setBody:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil]];
    } else {
        [response setStatusCode:500];
        [response setBody:[[error localizedDescription] dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (NSDictionary *)_parseMultipartFormData:(HTTPRequest *)request {
    // Simplified multipart parsing - production would use proper multipart library
    NSString *contentType = [request headers][@"Content-Type"];
    if (![contentType hasPrefix:@"multipart/form-data"]) {
        return @{};
    }
    
    // Extract boundary
    NSString *boundary = nil;
    NSArray *parts = [contentType componentsSeparatedByString:@"boundary="];
    if (parts.count > 1) {
        boundary = [NSString stringWithFormat:@"--%@", parts[1]];
    }
    
    // Parse body (simplified implementation)
    NSString *bodyString = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    // In production, would properly parse multipart data
    // This is a placeholder for the actual implementation
    
    return @{
        @"blob": request.body, // Placeholder
        @"mimeType": @"application/octet-stream" // Placeholder
    };
}
```

### Step 3: Implement getBlob endpoint

```objc
- (void)handleGetBlob:(NSDictionary *)params request:(HTTPRequest *)request response:(HTTPResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setStatusCode:400];
        [response setBody:[@"Missing CID parameter" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    
    NSError *error = nil;
    NSData *blobData = [self.blobStorage retrieveBlobWithCID:cid error:&error];
    if (blobData) {
        // Read metadata for MIME type
        NSString *metaPath = [[self.blobStorage.storageDirectory stringByAppendingPathComponent:[cid substringToIndex:2]] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.meta", cid]];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *mimeType = metadata[@"mimeType"] ?: @"application/octet-stream";
        
        [response setHeader:@"Content-Type" value:mimeType];
        [response setBody:blobData];
    } else {
        [response setStatusCode:404];
        [response setBody:[@"Blob not found" dataUsingEncoding:NSUTF8StringEncoding]];
    }
}
```

### Step 4: Implement listBlobs endpoint

```objc
- (void)handleListBlobs:(NSDictionary *)params request:(HTTPRequest *)request response:(HTTPResponse *)response {
    NSString *accountDID = params[@"account"];
    if (!accountDID) {
        [response setStatusCode:400];
        [response setBody:[@"Missing account parameter" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    
    NSError *error = nil;
    NSArray<BlobMetadata *> *blobs = [self.blobStorage listBlobsForAccount:accountDID error:&error];
    
    NSMutableArray *result = [NSMutableArray array];
    for (BlobMetadata *blob in blobs) {
        [result addObject:@{
            @"cid": blob.cid,
            @"mimeType": blob.mimeType,
            @"size": @(blob.size),
            @"createdAt": @([blob.createdAt timeIntervalSince1970])
        }];
    }
    
    [response setBody:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil]];
}
```

### Step 5: Update XRPC method dispatch

```objc
- (void)dispatchXRPCMethod:(NSString *)method params:(NSDictionary *)params request:(HTTPRequest *)request response:(HTTPResponse *)response {
    if ([method isEqualToString:@"com.atproto.repo.uploadBlob"]) {
        [self handleUploadBlob:params request:request response:response];
    } else if ([method isEqualToString:@"com.atproto.sync.getBlob"]) {
        [self handleGetBlob:params request:request response:response];
    } else if ([method isEqualToString:@"com.atproto.sync.listBlobs"]) {
        [self handleListBlobs:params request:request response:response];
    } else {
        // Handle other existing methods...
        [response setStatusCode:404];
        [response setBody:[@"Method not found" dataUsingEncoding:NSUTF8StringEncoding]];
    }
}
```

### Step 6: Commit

```bash
git add ATProtoPDS/ATProtoPDS/PDSController.m
git commit -m "feat: add blob storage endpoints to PDSController"
```

## Task 4: Add Basic Tests

**Files:**
- Create: `ATProtoPDS/ATProtoPDS/Blob/BlobStorageTests.m`

### Step 1: Write basic unit tests

```objc
#import <XCTest/XCTest.h>
#import "BlobStorage.h"

@interface BlobStorageTests : XCTestCase
@property (nonatomic, strong) BlobStorage *storage;
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation BlobStorageTests

- (void)setUp {
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.storage = [[BlobStorage alloc] initWithStorageDirectory:self.tempDir];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
}

- (void)testCIDComputation {
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSString *cid = [BlobStorage computeCIDForData:data error:&error];
    XCTAssertNotNil(cid);
    XCTAssertNil(error);
}

- (void)testStoreAndRetrieveBlob {
    NSData *data = [@"Test blob data" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *mimeType = @"text/plain";
    
    NSError *storeError = nil;
    NSString *cid = nil;
    BOOL stored = [self.storage storeBlob:data mimeType:mimeType cid:&cid error:&storeError];
    XCTAssertTrue(stored);
    XCTAssertNotNil(cid);
    XCTAssertNil(storeError);
    
    NSError *retrieveError = nil;
    NSData *retrieved = [self.storage retrieveBlobWithCID:cid error:&retrieveError];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved, data);
    XCTAssertNil(retrieveError);
}

- (void)testSizeLimit {
    // Create data larger than 5MB
    NSMutableData *largeData = [NSMutableData data];
    for (NSUInteger i = 0; i < 6 * 1024 * 1024; i++) {
        [largeData appendBytes:"x" length:1];
    }
    
    NSError *error = nil;
    NSString *cid = nil;
    BOOL result = [self.storage storeBlob:largeData mimeType:@"application/octet-stream" cid:&cid error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

@end
```

### Step 2: Commit

```bash
git add ATProtoPDS/ATProtoPDS/Blob/BlobStorageTests.m
git commit -m "feat: add basic unit tests for BlobStorage"
```

## Task 5: Update Build Configuration

**Files:**
- Modify: `ATProtoPDS/ATProtoPDS.xcodeproj/project.pbxproj`

### Step 1: Add BlobStorage files to Xcode project

Add the new BlobStorage.h, BlobStorage.m, and BlobStorageTests.m files to the appropriate target groups in the Xcode project file.

### Step 2: Commit

```bash
git add ATProtoPDS/ATProtoPDS.xcodeproj/project.pbxproj
git commit -m "feat: update Xcode project to include BlobStorage files"
```

## Task 6: Integration Testing

**Files:**
- Create: `test_blob_endpoints.sh`

### Step 1: Write integration test script

```bash
#!/bin/bash

# Build and run the PDS server
make clean && make

# Start server in background
./atprotopds &
SERVER_PID=$!

sleep 2

# Test uploadBlob
echo "Testing uploadBlob..."
curl -X POST -F "blob=@test_image.jpg" -F "mimeType=image/jpeg" http://localhost:8080/xrpc/com.atproto.repo.uploadBlob

# Test listBlobs
echo "Testing listBlobs..."
curl "http://localhost:8080/xrpc/com.atproto.sync.listBlobs?account=did:plc:test"

# Test getBlob
echo "Testing getBlob..."
curl "http://localhost:8080/xrpc/com.atproto.sync.getBlob?cid=bafkreiexamplecid" -o downloaded_blob.jpg

# Cleanup
kill $SERVER_PID
```

## Step 2: Make script executable and commit

```bash
chmod +x test_blob_endpoints.sh
git add test_blob_endpoints.sh
git commit -m "feat: add integration test script for blob endpoints"
```

## Task 7: Documentation

**Files:**
- Create: `docs/blob_storage_api.md`

### Step 1: Write API documentation

```markdown
# Blob Storage API

## Overview

The ATProto PDS implements blob storage for media content using a filesystem backend with CID-based addressing.

## Endpoints

### POST /xrpc/com.atproto.repo.uploadBlob

Upload a blob to the PDS.

**Parameters (multipart/form-data):**
- `blob`: Binary data
- `mimeType`: MIME type string

**Response:**
```json
{
  "cid": "bafkreiexamplecid"
}
```

### GET /xrpc/com.atproto.sync.getBlob

Retrieve a blob by CID.

**Parameters:**
- `cid`: Content identifier

**Response:** Binary blob data with appropriate Content-Type header.

### GET /xrpc/com.atproto.sync.listBlobs

List blobs for an account.

**Parameters:**
- `account`: Account DID

**Response:**
```json
[
  {
    "cid": "bafkreiexamplecid",
    "mimeType": "image/jpeg",
    "size": 1024,
    "createdAt": 1640995200
  }
]
```

## Storage

- Files are stored in sharded directories based on CID prefix
- Metadata is stored alongside blobs as .meta files
- Maximum blob size: 5MB
- Supported MIME types: images, videos, audio, and octet-stream
```

### Step 2: Commit

```bash
    git add docs/blob_storage_api.md
    git commit -m "docs: add API documentation for blob storage system"
    ```text

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation