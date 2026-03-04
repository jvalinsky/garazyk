# Blob Quotas

## Overview

This document covers blob quota management in the September PDS, including per-blob size limits, per-user storage quotas, quota tracking mechanisms, and enforcement strategies. Proper quota management is essential for preventing storage abuse, ensuring fair resource allocation, and maintaining server performance.

## Size Limit Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Blob Size Limits                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Per-Blob Limits (by MIME type category):                  │
│    ├─ Images:       5 MB                                   │
│    ├─ Videos:      50 MB                                   │
│    ├─ Audio:       10 MB                                   │
│    ├─ Fonts:       10 MB                                   │
│    ├─ 3D Models:  100 MB                                   │
│    ├─ Documents:   10 MB                                   │
│    ├─ Application:  5 MB                                   │
│    └─ Other:        5 MB                                   │
│                                                             │
│  Rate Limits (per user):                                   │
│    ├─ Upload limit: 50 blobs per hour (default)           │
│    └─ Configurable via rate_limit.blob_limit              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Per-Blob Size Limits

### MIME Type Categories

The PDS enforces size limits based on MIME type categories. Each category has a maximum file size to prevent abuse and ensure reasonable resource usage.

**Source:** `ATProtoPDS/Sources/Blob/MimeTypeValidator.m` (lines 5-12)

```objc
static const NSUInteger kMaxImageSize = 5 * 1024 * 1024;       // 5 MB
static const NSUInteger kMaxVideoSize = 50 * 1024 * 1024;      // 50 MB
static const NSUInteger kMaxAudioSize = 10 * 1024 * 1024;      // 10 MB
static const NSUInteger kMaxFontSize = 10 * 1024 * 1024;       // 10 MB
static const NSUInteger kMaxModelSize = 100 * 1024 * 1024;     // 100 MB
static const NSUInteger kMaxDocumentSize = 10 * 1024 * 1024;   // 10 MB
static const NSUInteger kMaxApplicationSize = 5 * 1024 * 1024; // 5 MB
static const NSUInteger kMaxOtherSize = 5 * 1024 * 1024;       // 5 MB
```


### Size Validation Implementation

The `MimeTypeValidator` class enforces size limits during blob upload:

```objc
- (BOOL)validateSize:(NSUInteger)fileSize 
        forMimeType:(NSString *)mimeType 
               error:(NSError **)error {
    
    NSUInteger maxSize = [self maxSizeForMimeType:mimeType];

    if (fileSize > maxSize) {
        if (error) {
            NSString *category = [self stringForCategory:[self categoryForMimeType:mimeType]];
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorTooLarge
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"File size %lu bytes exceeds maximum for %@ (%lu bytes)", 
                    (unsigned long)fileSize, category, (unsigned long)maxSize],
                @"maxSize": @(maxSize),
                @"actualSize": @(fileSize)
            }];
        }
        return NO;
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Blob/MimeTypeValidator.m` (lines 380-405)

### Category-Based Limits

Size limits are stored in a dictionary keyed by category:

```objc
- (void)setupMaxSizes {
    _maxSizesByCategory = @{
        @(MimeCategoryImage): @(kMaxImageSize),
        @(MimeCategoryVideo): @(kMaxVideoSize),
        @(MimeCategoryAudio): @(kMaxAudioSize),
        @(MimeCategoryFont): @(kMaxFontSize),
        @(MimeCategoryModel): @(kMaxModelSize),
        @(MimeCategoryApplication): @(kMaxApplicationSize),
        @(MimeCategoryOther): @(kMaxOtherSize),
    };
}
```

**Source:** `ATProtoPDS/Sources/Blob/MimeTypeValidator.m` (lines 280-290)


### Getting Maximum Size for MIME Type

```objc
- (NSUInteger)maxSizeForMimeType:(NSString *)mimeType {
    MimeCategory category = [self categoryForMimeType:mimeType];
    NSNumber *maxSize = _maxSizesByCategory[@(category)];
    return maxSize ? maxSize.unsignedIntegerValue : kMaxOtherSize;
}
```

**Source:** `ATProtoPDS/Sources/Blob/MimeTypeValidator.m` (lines 407-412)

### Validation During Upload

Size validation occurs in the `BlobStorage` upload flow:

```objc
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {

    // 1. Validate the blob (MIME type, size, magic bytes)
    if (![self validateBlob:data mimeType:mimeType error:error]) {
        return nil;
    }

    // ... rest of upload logic
}

- (BOOL)validateBlob:(NSData *)data 
            mimeType:(NSString *)mimeType 
               error:(NSError **)error {
    
    MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];

    // ... MIME type validation ...

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

    // ... magic number validation ...

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 43-130, 280-350)


## Upload Rate Limiting

### Configuration

Blob uploads are rate-limited per user to prevent abuse:

```objc
// Default configuration
_rateLimitBlobLimit = 50;              // 50 uploads per window
_rateLimitBlobWindowSeconds = 3600;    // 1 hour window
```

**Source:** `ATProtoPDS/Sources/App/PDSConfiguration.m` (lines 175-176)

### Configuration Options

Rate limits can be configured via `config.json`:

```json
{
  "rate_limit": {
    "enabled": true,
    "blob_limit": 50,
    "blob_window": 3600
  }
}
```

**Configuration properties:**

```objc
/*! Blob upload limit (requests per window). */
@property (nonatomic, readonly) NSUInteger rateLimitBlobLimit;

/*! Blob upload window size in seconds. */
@property (nonatomic, readonly) NSTimeInterval rateLimitBlobWindowSeconds;
```

**Source:** `ATProtoPDS/Sources/App/PDSConfiguration.h` (lines 175-179)

### Environment Variable Overrides

Rate limits can also be set via environment variables:

```bash
export PDS_RATELIMIT_BLOB_LIMIT=100
export PDS_RATELIMIT_BLOB_WINDOW=7200
```

**Implementation:**

```objc
NSString *envBlobLimit =
    [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_LIMIT" default:nil];
if (envBlobLimit)
  _rateLimitBlobLimit = [envBlobLimit integerValue];

NSString *envBlobWindow =
    [self resolveEnvOverrideForKey:@"PDS_RATELIMIT_BLOB_WINDOW" default:nil];
if (envBlobWindow)
  _rateLimitBlobWindowSeconds = [envBlobWindow doubleValue];
```

**Source:** `ATProtoPDS/Sources/App/PDSConfiguration.m` (lines 581-589)


### Rate Limit Enforcement

The `RateLimiter` tracks blob uploads per user:

```objc
NSString *upsertSQL = @"INSERT INTO blob_rate_limits (did, upload_count, window_start) "
                      @"VALUES (?, ?, ?) "
                      @"ON CONFLICT(did) DO UPDATE SET "
                      @"upload_count = upload_count + 1, "
                      @"window_start = CASE "
                      @"  WHEN ? - window_start > ? THEN ? "
                      @"  ELSE window_start "
                      @"END";
```

**Source:** `ATProtoPDS/Sources/Network/RateLimiter.m` (lines 368-371)

**Rate limiting flow:**

1. Check current upload count for user's DID
2. If window expired, reset count and start new window
3. If count exceeds limit, reject upload with 429 error
4. Otherwise, increment count and allow upload

## Storage Quota Tracking

### Per-User Blob Statistics

The PDS tracks blob count and total size per user in the actor database:

```sql
CREATE TABLE blobs (
    cid BLOB PRIMARY KEY,
    did TEXT NOT NULL,
    mimeType TEXT NOT NULL,
    size INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_blobs_did ON blobs(did);
CREATE INDEX idx_blobs_cid ON blobs(cid);
```

**Source:** `ATProtoPDS/Sources/Database/PDSDatabase.h` (lines 398-401)

### Querying Blob Count

```objc
- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";
    
    // Execute query and return count
    NSArray *rows = [self executeQuery:sql withParams:@[did] error:error];
    if (rows.count > 0) {
        return [rows[0][@"COUNT(*)"] integerValue];
    }
    
    return 0;
}
```

**Source:** `ATProtoPDS/Sources/Database/PDSDatabase.m` (lines 1596-1599)


### Aggregate Statistics

The admin service provides aggregate blob statistics across all users:

```objc
// Blob count and size
NSArray *blobs = [_database executeQuery:
    @"SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size FROM blobs" 
    error:error];

if (blobs.count > 0) {
    stats[@"blobs_total"] = blobs.firstObject[@"count"] ?: @0;
    stats[@"blobs_size_bytes"] = blobs.firstObject[@"total_size"] ?: @0;
}
```

**Source:** `ATProtoPDS/Sources/Services/PDSAdminService.m` (lines 650-653)

### Metrics Collection

The `PDSMetrics` class tracks blob statistics for monitoring:

```objc
/*! Total number of blobs stored. */
@property (nonatomic, assign) NSInteger blobCount;

/*! Total blob storage in bytes. */
@property (nonatomic, assign) NSUInteger blobStorageBytes;

/*! Increments the blob count by one. */
- (void)incrementBlobCount;

/*! Adds bytes to the total blob storage counter. */
- (void)addBlobStorageBytes:(NSUInteger)bytes;
```

**Source:** `ATProtoPDS/Sources/Metrics/PDSMetrics.h` (lines 42-97)

**Prometheus export format:**

```
# HELP pds_blob_count Total number of blobs
# TYPE pds_blob_count gauge
pds_blob_count 1234

# HELP pds_blob_storage_bytes Total blob storage used
# TYPE pds_blob_storage_bytes gauge
pds_blob_storage_bytes 52428800
```

**Source:** `ATProtoPDS/Sources/Metrics/PDSMetrics.m` (lines 119-124)


## Quota Enforcement Strategies

### Strategy 1: Hard Limits (Not Currently Implemented)

A hard quota system would reject uploads when a user exceeds their storage limit:

```objc
- (BOOL)checkQuotaForDid:(NSString *)did 
              blobSize:(NSUInteger)blobSize 
                 error:(NSError **)error {
    
    // 1. Get user's quota limit (e.g., from configuration or database)
    NSUInteger quotaLimit = [self getQuotaLimitForDid:did];
    
    // 2. Calculate current usage
    NSString *sql = @"SELECT COALESCE(SUM(size), 0) as total_size FROM blobs WHERE did = ?";
    NSArray *rows = [self executeQuery:sql withParams:@[did] error:error];
    
    if (!rows || rows.count == 0) {
        return NO;
    }
    
    NSUInteger currentUsage = [rows[0][@"total_size"] unsignedIntegerValue];
    
    // 3. Check if new blob would exceed quota
    if (currentUsage + blobSize > quotaLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"BlobQuota"
                                         code:1001
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Storage quota exceeded: %lu/%lu bytes used, cannot upload %lu bytes",
                    (unsigned long)currentUsage,
                    (unsigned long)quotaLimit,
                    (unsigned long)blobSize]
            }];
        }
        return NO;
    }
    
    return YES;
}
```

**Usage in upload flow:**

```objc
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {

    // Check quota before upload
    if (![self checkQuotaForDid:did blobSize:data.length error:error]) {
        return nil;
    }

    // Proceed with upload
    // ...
}
```


### Strategy 2: Soft Limits with Warnings

Soft limits allow uploads but warn users when approaching quota:

```objc
- (NSDictionary *)checkQuotaStatusForDid:(NSString *)did error:(NSError **)error {
    
    NSUInteger quotaLimit = [self getQuotaLimitForDid:did];
    
    // Get current usage
    NSString *sql = @"SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size "
                    @"FROM blobs WHERE did = ?";
    NSArray *rows = [self executeQuery:sql withParams:@[did] error:error];
    
    if (!rows || rows.count == 0) {
        return nil;
    }
    
    NSUInteger blobCount = [rows[0][@"count"] unsignedIntegerValue];
    NSUInteger totalSize = [rows[0][@"total_size"] unsignedIntegerValue];
    NSUInteger remaining = quotaLimit > totalSize ? quotaLimit - totalSize : 0;
    double percentUsed = (double)totalSize / (double)quotaLimit * 100.0;
    
    return @{
        @"quota_limit": @(quotaLimit),
        @"used_bytes": @(totalSize),
        @"remaining_bytes": @(remaining),
        @"percent_used": @(percentUsed),
        @"blob_count": @(blobCount),
        @"warning": @(percentUsed >= 80.0),
        @"critical": @(percentUsed >= 95.0)
    };
}
```

**XRPC endpoint for quota status:**

```objc
// In XrpcRepoMethods.m
- (void)handleGetQuotaStatus:(XrpcRequest *)request 
                     response:(XrpcResponse *)response {
    
    NSString *did = [XrpcAuthHelper extractDIDFromRequest:request error:nil];
    if (!did) {
        [XrpcErrorHelper setAuthenticationError:response 
                                        message:@"Authentication required"];
        return;
    }
    
    NSError *error = nil;
    NSDictionary *status = [blobService checkQuotaStatusForDid:did error:&error];
    
    if (!status) {
        [XrpcErrorHelper setInternalServerError:response];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:status 
                                                    options:0 
                                                      error:nil];
}
```


### Strategy 3: Tiered Quotas

Different quota tiers based on account type or subscription:

```objc
typedef NS_ENUM(NSInteger, QuotaTier) {
    QuotaTierFree = 0,      // 1 GB
    QuotaTierBasic = 1,     // 10 GB
    QuotaTierPro = 2,       // 100 GB
    QuotaTierEnterprise = 3 // Unlimited
};

- (NSUInteger)getQuotaLimitForDid:(NSString *)did {
    // Query account tier from database
    NSString *sql = @"SELECT quota_tier FROM accounts WHERE did = ?";
    NSArray *rows = [self executeQuery:sql withParams:@[did] error:nil];
    
    if (rows.count == 0) {
        return 1 * 1024 * 1024 * 1024; // Default: 1 GB
    }
    
    QuotaTier tier = [rows[0][@"quota_tier"] integerValue];
    
    switch (tier) {
        case QuotaTierFree:
            return 1ULL * 1024 * 1024 * 1024;      // 1 GB
        case QuotaTierBasic:
            return 10ULL * 1024 * 1024 * 1024;     // 10 GB
        case QuotaTierPro:
            return 100ULL * 1024 * 1024 * 1024;    // 100 GB
        case QuotaTierEnterprise:
            return NSUIntegerMax;                   // Unlimited
        default:
            return 1ULL * 1024 * 1024 * 1024;      // Default: 1 GB
    }
}
```

**Database schema:**

```sql
ALTER TABLE accounts ADD COLUMN quota_tier INTEGER DEFAULT 0;
ALTER TABLE accounts ADD COLUMN custom_quota_bytes INTEGER DEFAULT NULL;

-- Custom quota overrides tier-based quota
CREATE INDEX idx_accounts_quota ON accounts(quota_tier);
```

### Strategy 4: Time-Based Quotas

Reset quotas periodically (e.g., monthly):

```objc
- (NSUInteger)getMonthlyQuotaUsageForDid:(NSString *)did error:(NSError **)error {
    
    // Get start of current month
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth
                                               fromDate:[NSDate date]];
    NSDate *monthStart = [calendar dateFromComponents:components];
    NSInteger monthStartTimestamp = (NSInteger)[monthStart timeIntervalSince1970];
    
    // Sum blob sizes uploaded this month
    NSString *sql = @"SELECT COALESCE(SUM(size), 0) as total_size "
                    @"FROM blobs WHERE did = ? AND created_at >= ?";
    NSArray *rows = [self executeQuery:sql 
                            withParams:@[did, @(monthStartTimestamp)] 
                                 error:error];
    
    if (rows.count > 0) {
        return [rows[0][@"total_size"] unsignedIntegerValue];
    }
    
    return 0;
}
```


## Quota Management APIs

### Listing User Blobs

Get all blobs for a user with pagination:

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
            @"size": @(blob.size),
            @"createdAt": @(blob.createdAt)
        }];
    }
    
    return result;
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 122-143)

### Getting Repository Statistics

Retrieve comprehensive statistics including blob usage:

```objc
- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did 
                                        error:(NSError **)error {
    
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    // Record count
    NSString *recordSQL = @"SELECT COUNT(*) as count FROM records WHERE did = ?";
    NSArray *records = [self executeQuery:recordSQL withParams:@[did] error:error];
    if (records.count > 0) {
        stats[@"record_count"] = records[0][@"count"] ?: @0;
    }
    
    // Blob count and total size
    NSString *blobSQL = @"SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size "
                        @"FROM blobs WHERE did = ?";
    NSArray *blobs = [self executeQuery:blobSQL withParams:@[did] error:error];
    if (blobs.count > 0) {
        stats[@"blob_count"] = blobs[0][@"count"] ?: @0;
        stats[@"blob_size_bytes"] = blobs[0][@"total_size"] ?: @0;
    }
    
    // Repository commit count
    NSString *commitSQL = @"SELECT COUNT(*) as count FROM commits WHERE did = ?";
    NSArray *commits = [self executeQuery:commitSQL withParams:@[did] error:error];
    if (commits.count > 0) {
        stats[@"commit_count"] = commits[0][@"count"] ?: @0;
    }
    
    return stats;
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSRecordService.h` (lines 135-137)


### Admin Statistics Endpoint

Server-wide blob statistics for administrators:

```objc
// In PDSAdminService.m
- (nullable NSDictionary *)getServerStats:(NSError **)error {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    // ... other stats ...
    
    // Blob count and size across all users
    NSArray *blobs = [_database executeQuery:
        @"SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size FROM blobs" 
        error:error];
    
    if (blobs.count > 0) {
        stats[@"blobs_total"] = blobs.firstObject[@"count"] ?: @0;
        stats[@"blobs_size_bytes"] = blobs.firstObject[@"total_size"] ?: @0;
    }
    
    return stats;
}
```

**Source:** `ATProtoPDS/Sources/Services/PDSAdminService.m` (lines 650-653)

**Response format:**

```json
{
  "repos_total": 150,
  "records_total": 5432,
  "blobs_total": 1234,
  "blobs_size_bytes": 52428800,
  "blocks_total": 8765
}
```

## Quota Enforcement Examples

### Example 1: Pre-Upload Quota Check

```objc
// In XrpcRepoMethods.m - uploadBlob handler
- (void)handleUploadBlob:(XrpcRequest *)request 
                response:(XrpcResponse *)response {
    
    // 1. Extract authentication
    NSString *did = [XrpcAuthHelper extractDIDFromRequest:request error:nil];
    if (!did) {
        [XrpcErrorHelper setAuthenticationError:response 
                                        message:@"Authentication required"];
        return;
    }
    
    // 2. Get blob data
    NSData *blobData = request.body;
    NSString *contentType = [request headerForKey:@"Content-Type"];
    
    if (!blobData || blobData.length == 0) {
        [XrpcErrorHelper setValidationError:response 
                                    message:@"Empty blob data"];
        return;
    }
    
    // 3. Check quota before upload
    NSError *quotaError = nil;
    if (![blobService checkQuotaForDid:did blobSize:blobData.length error:&quotaError]) {
        response.statusCode = 413; // Payload Too Large
        response.body = [NSJSONSerialization dataWithJSONObject:@{
            @"error": @"QuotaExceeded",
            @"message": quotaError.localizedDescription ?: @"Storage quota exceeded"
        } options:0 error:nil];
        return;
    }
    
    // 4. Proceed with upload
    NSDictionary *result = [blobService uploadBlob:blobData
                                            forDid:did
                                          mimeType:contentType ?: @"application/octet-stream"
                                             error:&quotaError];
    
    if (!result) {
        [XrpcErrorHelper setInternalServerError:response];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result 
                                                    options:0 
                                                      error:nil];
}
```


### Example 2: Quota Warning System

```objc
- (void)sendQuotaWarningIfNeeded:(NSString *)did {
    
    NSError *error = nil;
    NSDictionary *status = [self checkQuotaStatusForDid:did error:&error];
    
    if (!status) {
        return;
    }
    
    double percentUsed = [status[@"percent_used"] doubleValue];
    BOOL warning = [status[@"warning"] boolValue];
    BOOL critical = [status[@"critical"] boolValue];
    
    if (critical && !self.criticalWarningSent[did]) {
        // Send critical warning (95%+ used)
        [self sendNotification:did 
                          type:@"quota_critical"
                       message:[NSString stringWithFormat:
                           @"Storage quota critical: %.1f%% used. "
                           @"Please delete unused blobs to free space.",
                           percentUsed]];
        
        self.criticalWarningSent[did] = @YES;
        
    } else if (warning && !self.warningsSent[did]) {
        // Send warning (80%+ used)
        [self sendNotification:did 
                          type:@"quota_warning"
                       message:[NSString stringWithFormat:
                           @"Storage quota warning: %.1f%% used. "
                           @"Consider cleaning up old blobs.",
                           percentUsed]];
        
        self.warningsSent[did] = @YES;
    }
}
```

### Example 3: Automatic Cleanup on Quota Exceeded

```objc
- (BOOL)uploadBlobWithAutoCleanup:(NSData *)data
                         mimeType:(NSString *)mimeType
                              did:(NSString *)did
                            error:(NSError **)error {
    
    // 1. Try normal upload
    CID *cid = [self uploadBlob:data mimeType:mimeType did:did error:error];
    if (cid) {
        return YES; // Success
    }
    
    // 2. Check if failure was due to quota
    if (error && (*error).code == BlobStorageErrorQuotaExceeded) {
        
        PDS_LOG_INFO_C(PDSLogComponentBlob,
            @"Quota exceeded for %@, attempting automatic cleanup", did);
        
        // 3. Run garbage collection to free space
        NSUInteger deletedCount = [self collectGarbageBlobsForDID:did error:nil];
        
        if (deletedCount > 0) {
            PDS_LOG_INFO_C(PDSLogComponentBlob,
                @"Freed space by deleting %lu orphaned blobs", 
                (unsigned long)deletedCount);
            
            // 4. Retry upload
            cid = [self uploadBlob:data mimeType:mimeType did:did error:error];
            if (cid) {
                return YES;
            }
        }
        
        // 5. Still failed - quota genuinely exceeded
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorQuotaExceeded
                                     userInfo:@{
                NSLocalizedDescriptionKey: 
                    @"Storage quota exceeded. Please delete unused blobs manually."
            }];
        }
        return NO;
    }
    
    return NO;
}
```


## Configuration Best Practices

### Recommended Quota Settings

**Small PDS (1-100 users):**

```json
{
  "rate_limit": {
    "enabled": true,
    "blob_limit": 50,
    "blob_window": 3600
  },
  "quotas": {
    "default_per_user_gb": 5,
    "max_blob_size_mb": 50
  }
}
```

**Medium PDS (100-1000 users):**

```json
{
  "rate_limit": {
    "enabled": true,
    "blob_limit": 100,
    "blob_window": 3600
  },
  "quotas": {
    "default_per_user_gb": 2,
    "max_blob_size_mb": 25
  }
}
```

**Large PDS (1000+ users):**

```json
{
  "rate_limit": {
    "enabled": true,
    "blob_limit": 50,
    "blob_window": 1800
  },
  "quotas": {
    "default_per_user_gb": 1,
    "max_blob_size_mb": 10,
    "enable_tiered_quotas": true
  }
}
```

### Monitoring Quota Usage

**Prometheus metrics:**

```
# Total blob storage across all users
pds_blob_storage_bytes 52428800

# Total blob count
pds_blob_count 1234

# Per-user metrics (if implemented)
pds_user_blob_storage_bytes{did="did:plc:abc123"} 10485760
pds_user_blob_count{did="did:plc:abc123"} 42
```

**Query examples:**

```bash
# Get top 10 users by storage usage
curl -s http://localhost:2583/metrics | grep pds_user_blob_storage_bytes | sort -t' ' -k2 -n -r | head -10

# Get total storage usage
curl -s http://localhost:2583/metrics | grep '^pds_blob_storage_bytes'
```


### Database Maintenance

**Optimize blob table:**

```sql
-- Analyze blob table for query optimization
ANALYZE blobs;

-- Rebuild indexes
REINDEX blobs;

-- Vacuum to reclaim space (run during maintenance window)
VACUUM;
```

**Monitor table size:**

```sql
-- Get blob table size
SELECT 
    COUNT(*) as blob_count,
    SUM(size) as total_bytes,
    AVG(size) as avg_bytes,
    MAX(size) as max_bytes
FROM blobs;

-- Get per-user statistics
SELECT 
    did,
    COUNT(*) as blob_count,
    SUM(size) as total_bytes,
    MAX(size) as largest_blob
FROM blobs
GROUP BY did
ORDER BY total_bytes DESC
LIMIT 20;
```

## Error Handling

### Quota Error Codes

```objc
typedef NS_ENUM(NSInteger, BlobStorageError) {
    BlobStorageErrorBlobNotFound = 1,
    BlobStorageErrorInvalidMIMEType = 2,
    BlobStorageErrorFileTooLarge = 3,
    BlobStorageErrorStorageFailure = 4,
    BlobStorageErrorCIDMismatch = 5,
    BlobStorageErrorQuotaExceeded = 6,
    BlobStorageErrorRateLimitExceeded = 7
};
```

### Client Error Responses

**File too large:**

```json
{
  "error": "BlobTooLarge",
  "message": "File size 6291456 bytes exceeds maximum for Image (5242880 bytes)"
}
```

HTTP Status: `413 Payload Too Large`

**Quota exceeded:**

```json
{
  "error": "QuotaExceeded",
  "message": "Storage quota exceeded: 1073741824/1073741824 bytes used"
}
```

HTTP Status: `413 Payload Too Large`

**Rate limit exceeded:**

```json
{
  "error": "RateLimitExceeded",
  "message": "Blob upload rate limit exceeded. Try again in 1800 seconds."
}
```

HTTP Status: `429 Too Many Requests`


### Error Handling Pattern

```objc
NSError *error = nil;
NSDictionary *result = [blobService uploadBlob:blobData
                                        forDid:userDid
                                      mimeType:mimeType
                                         error:&error];

if (!result) {
    switch (error.code) {
        case BlobStorageErrorFileTooLarge:
            NSLog(@"File too large: %@", error.localizedDescription);
            // Show user the maximum allowed size
            NSNumber *maxSize = error.userInfo[@"maxSize"];
            NSLog(@"Maximum size: %@ bytes", maxSize);
            break;
            
        case BlobStorageErrorQuotaExceeded:
            NSLog(@"Quota exceeded: %@", error.localizedDescription);
            // Prompt user to delete old blobs
            [self showQuotaExceededDialog];
            break;
            
        case BlobStorageErrorRateLimitExceeded:
            NSLog(@"Rate limit exceeded: %@", error.localizedDescription);
            // Show retry timer
            NSNumber *retryAfter = error.userInfo[@"retryAfter"];
            [self showRateLimitDialog:retryAfter];
            break;
            
        case BlobStorageErrorInvalidMIMEType:
            NSLog(@"Invalid MIME type: %@", error.localizedDescription);
            // Show supported types
            [self showSupportedTypesDialog];
            break;
            
        default:
            NSLog(@"Upload failed: %@", error.localizedDescription);
            break;
    }
    return;
}

NSLog(@"Blob uploaded successfully: %@", result[@"blob"][@"ref"][@"$link"]);
```

## Performance Considerations

### Indexing Strategy

Ensure proper indexes for quota queries:

```sql
-- Primary indexes (already exist)
CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did);
CREATE INDEX IF NOT EXISTS idx_blobs_cid ON blobs(cid);

-- Composite index for quota queries
CREATE INDEX IF NOT EXISTS idx_blobs_did_size ON blobs(did, size);

-- Index for time-based queries
CREATE INDEX IF NOT EXISTS idx_blobs_created_at ON blobs(created_at);

-- Covering index for statistics
CREATE INDEX IF NOT EXISTS idx_blobs_did_size_created 
    ON blobs(did, size, created_at);
```

### Query Optimization

**Efficient quota check:**

```sql
-- Fast: Uses idx_blobs_did_size
SELECT COALESCE(SUM(size), 0) as total_size 
FROM blobs 
WHERE did = ?;

-- Slow: Full table scan
SELECT SUM(size) as total_size 
FROM blobs;
```

**Pagination for large result sets:**

```sql
-- Good: Paginated query
SELECT cid, size, mimeType, created_at 
FROM blobs 
WHERE did = ? AND cid > ?
ORDER BY cid 
LIMIT 100;

-- Bad: Fetching all blobs at once
SELECT cid, size, mimeType, created_at 
FROM blobs 
WHERE did = ?;
```


### Caching Quota Information

Cache quota status to reduce database queries:

```objc
@interface BlobQuotaCache : NSObject

@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *quotaCache;
@property (nonatomic, assign) NSTimeInterval cacheTTL; // Default: 300 seconds

- (nullable NSDictionary *)getCachedQuotaForDid:(NSString *)did;
- (void)cacheQuota:(NSDictionary *)quota forDid:(NSString *)did;
- (void)invalidateQuotaForDid:(NSString *)did;

@end

@implementation BlobQuotaCache

- (instancetype)init {
    self = [super init];
    if (self) {
        _quotaCache = [[NSCache alloc] init];
        _quotaCache.countLimit = 1000; // Cache up to 1000 users
        _cacheTTL = 300; // 5 minutes
    }
    return self;
}

- (nullable NSDictionary *)getCachedQuotaForDid:(NSString *)did {
    NSDictionary *cached = [self.quotaCache objectForKey:did];
    
    if (!cached) {
        return nil;
    }
    
    // Check if cache entry is still valid
    NSDate *cachedAt = cached[@"cached_at"];
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:cachedAt];
    
    if (age > self.cacheTTL) {
        [self.quotaCache removeObjectForKey:did];
        return nil;
    }
    
    return cached;
}

- (void)cacheQuota:(NSDictionary *)quota forDid:(NSString *)did {
    NSMutableDictionary *entry = [quota mutableCopy];
    entry[@"cached_at"] = [NSDate date];
    [self.quotaCache setObject:entry forKey:did];
}

- (void)invalidateQuotaForDid:(NSString *)did {
    [self.quotaCache removeObjectForKey:did];
}

@end
```

**Usage:**

```objc
// Check cache first
NSDictionary *quota = [self.quotaCache getCachedQuotaForDid:did];

if (!quota) {
    // Cache miss - query database
    quota = [self checkQuotaStatusForDid:did error:nil];
    
    if (quota) {
        [self.quotaCache cacheQuota:quota forDid:did];
    }
}

// Invalidate cache after upload
[self.quotaCache invalidateQuotaForDid:did];
```


## Security Considerations

### Preventing Quota Abuse

**1. Validate MIME Types**

Always verify file content matches claimed MIME type:

```objc
// Validate magic numbers match claimed type
if (![validator validateMagicNumbers:data 
                         forMimeType:mimeType 
                               error:&error]) {
    // Reject upload - potential type spoofing
    return nil;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 280-350)

**2. Enforce Rate Limits**

Prevent rapid-fire uploads that could exhaust quotas:

```objc
// Check rate limit before processing upload
if (![rateLimiter checkBlobUploadLimit:did error:&error]) {
    // Return 429 Too Many Requests
    return nil;
}
```

**3. Monitor Suspicious Patterns**

Track unusual upload patterns:

```objc
- (BOOL)detectSuspiciousActivity:(NSString *)did {
    
    // Check for rapid uploads of maximum-size files
    NSString *sql = @"SELECT COUNT(*) as count FROM blobs "
                    @"WHERE did = ? AND created_at > ? AND size > ?";
    
    NSInteger recentTimestamp = (NSInteger)[[NSDate dateWithTimeIntervalSinceNow:-3600] 
                                            timeIntervalSince1970];
    NSInteger largeFileThreshold = 40 * 1024 * 1024; // 40 MB
    
    NSArray *rows = [self executeQuery:sql 
                            withParams:@[did, @(recentTimestamp), @(largeFileThreshold)] 
                                 error:nil];
    
    if (rows.count > 0) {
        NSInteger count = [rows[0][@"count"] integerValue];
        
        // Flag if user uploaded >10 large files in past hour
        if (count > 10) {
            PDS_LOG_WARNING_C(PDSLogComponentBlob,
                @"Suspicious upload pattern detected for %@: %ld large files in 1 hour",
                did, (long)count);
            return YES;
        }
    }
    
    return NO;
}
```

**4. Implement Soft Deletes**

Use soft deletes to prevent immediate quota recovery abuse:

```sql
ALTER TABLE blobs ADD COLUMN deleted_at INTEGER DEFAULT NULL;

-- Mark as deleted instead of immediate removal
UPDATE blobs SET deleted_at = ? WHERE cid = ? AND did = ?;

-- Exclude deleted blobs from quota calculations
SELECT COALESCE(SUM(size), 0) as total_size 
FROM blobs 
WHERE did = ? AND deleted_at IS NULL;

-- Permanently delete after grace period (e.g., 30 days)
DELETE FROM blobs WHERE deleted_at < ? - 2592000;
```


## CLI Commands

### Quota Management Commands

**Check user quota:**

```bash
# Get quota status for specific user
kaszlak quota status --did did:plc:abc123

# Output:
# Quota Status for did:plc:abc123:
#   Limit: 1.0 GB
#   Used: 524.3 MB (51.2%)
#   Remaining: 499.7 MB
#   Blob count: 42
#   Status: OK
```

**List top users by storage:**

```bash
# Get top 20 users by storage usage
kaszlak quota top --limit 20

# Output:
# Top Users by Storage:
#   1. did:plc:user1    987.6 MB  (98.7%)
#   2. did:plc:user2    856.2 MB  (85.6%)
#   3. did:plc:user3    723.4 MB  (72.3%)
#   ...
```

**Set custom quota:**

```bash
# Set custom quota for specific user
kaszlak quota set --did did:plc:abc123 --limit 10GB

# Output:
# Quota updated for did:plc:abc123: 10.0 GB
```

**Reset quota to default:**

```bash
# Reset to default quota tier
kaszlak quota reset --did did:plc:abc123

# Output:
# Quota reset to default (1.0 GB) for did:plc:abc123
```

### Cleanup Commands

**Run garbage collection:**

```bash
# Collect orphaned blobs for specific user
kaszlak gc blobs --did did:plc:abc123

# Output:
# Collecting garbage for did:plc:abc123...
# Deleted 8 orphaned blobs (12.4 MB freed)
```

**Dry-run mode:**

```bash
# Preview what would be deleted
kaszlak gc blobs --did did:plc:abc123 --dry-run

# Output:
# Dry-run results for did:plc:abc123:
#   Total blobs: 42
#   Referenced: 34
#   Orphaned: 8
#   Reclaimable space: 12.4 MB
```

## Best Practices

### Upload Validation

1. **Validate Early** — Check size and MIME type before accepting upload
2. **Check Quota First** — Verify quota before processing large uploads
3. **Use Streaming** — Stream large uploads to avoid memory issues
4. **Verify Content** — Check magic bytes match claimed MIME type

### Quota Management

1. **Set Reasonable Defaults** — Start with conservative quotas (1-5 GB)
2. **Monitor Usage** — Track quota usage trends over time
3. **Implement Warnings** — Notify users at 80% and 95% usage
4. **Provide Cleanup Tools** — Give users tools to manage their storage

### Performance

1. **Index Properly** — Ensure indexes on `did`, `size`, and `created_at`
2. **Cache Quota Status** — Cache quota calculations for 5 minutes
3. **Use Pagination** — Paginate blob listings for large collections
4. **Optimize Queries** — Use covering indexes for statistics queries

### Security

1. **Enforce Rate Limits** — Prevent rapid-fire uploads
2. **Validate MIME Types** — Check magic bytes to prevent spoofing
3. **Monitor Patterns** — Detect and flag suspicious upload behavior
4. **Use Soft Deletes** — Prevent quota recovery abuse


## Troubleshooting

### Common Issues

**Issue: Quota exceeded but blobs deleted**

```bash
# Problem: User deleted blobs but quota still shows as full

# Solution: Run garbage collection to update statistics
kaszlak gc blobs --did did:plc:abc123

# Verify quota updated
kaszlak quota status --did did:plc:abc123
```

**Issue: Rate limit false positives**

```bash
# Problem: Rate limit triggered incorrectly

# Solution: Check rate limit window
sqlite3 data/service.db "SELECT * FROM blob_rate_limits WHERE did = 'did:plc:abc123';"

# Reset rate limit if needed
sqlite3 data/service.db "DELETE FROM blob_rate_limits WHERE did = 'did:plc:abc123';"
```

**Issue: Slow quota queries**

```sql
-- Problem: Quota queries taking too long

-- Solution: Analyze query plan
EXPLAIN QUERY PLAN 
SELECT COALESCE(SUM(size), 0) as total_size 
FROM blobs 
WHERE did = 'did:plc:abc123';

-- Ensure index is being used
-- Expected: SEARCH TABLE blobs USING INDEX idx_blobs_did (did=?)

-- Rebuild indexes if needed
REINDEX blobs;
ANALYZE blobs;
```

**Issue: Inconsistent blob counts**

```bash
# Problem: Blob count doesn't match actual files

# Solution: Verify database consistency
kaszlak verify blobs --did did:plc:abc123

# Repair if needed
kaszlak repair blobs --did did:plc:abc123
```

### Debugging Quota Issues

**Enable quota logging:**

```objc
// In PDSConfiguration.m
_logLevel = PDSLogLevelDebug;
_logComponents = PDSLogComponentBlob | PDSLogComponentDatabase;
```

**Check quota calculation:**

```sql
-- Manual quota calculation
SELECT 
    did,
    COUNT(*) as blob_count,
    SUM(size) as total_bytes,
    SUM(size) / 1024.0 / 1024.0 as total_mb,
    SUM(size) / 1024.0 / 1024.0 / 1024.0 as total_gb
FROM blobs
WHERE did = 'did:plc:abc123'
GROUP BY did;
```

**Verify blob references:**

```bash
# Check for orphaned blobs
kaszlak gc blobs --did did:plc:abc123 --dry-run --verbose

# Output shows:
# - Total blobs
# - Referenced blobs
# - Orphaned blobs
# - Detailed CID list
```

## See Also

- [Blob Lifecycle](./blob-lifecycle.md) — Upload, download, and deletion workflows
- [Blob Optimization](./blob-optimization.md) — Performance optimization techniques
- [Blob Garbage Collection](./blob-garbage-collection.md) — Orphan detection and cleanup
- [Blob Storage](./blob-storage.md) — Storage architecture and providers
- [Blob Service](../03-application-layer/blob-service.md) — Service layer API
- [Rate Limiting](../04-network-layer/rate-limiting.md) — Rate limiting strategies
- [Configuration Reference](../11-reference/config-reference.md) — Configuration options
