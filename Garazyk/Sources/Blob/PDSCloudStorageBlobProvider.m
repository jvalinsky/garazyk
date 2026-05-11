// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCloudStorageBlobProvider.h"
#import "Auth/CryptoUtils.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "Compat/Foundation/NSDataCompat.h"
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>

NSString * const PDSCloudStorageBlobProviderErrorDomain = @"com.atproto.pds.cloudstorageblobprovider";

@interface PDSCloudStorageBlobProvider ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSString *secretAccessKey;
@end

@implementation PDSCloudStorageBlobProvider

- (nullable instancetype)initWithBucket:(NSString *)bucket
                                 region:(NSString *)region
                               endpoint:(nullable NSString *)endpoint
                              keyPrefix:(nullable NSString *)keyPrefix
                          accessKeyId:(NSString *)accessKeyId
                       secretAccessKey:(NSString *)secretAccessKey {
    if (!bucket || bucket.length == 0 || !region || region.length == 0 ||
        !accessKeyId || accessKeyId.length == 0 ||
        !secretAccessKey || secretAccessKey.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _bucket = [bucket copy];
        _region = [region copy];
        _endpoint = [endpoint copy];
        _keyPrefix = [keyPrefix copy];
        _accessKeyId = [accessKeyId copy];
        _secretAccessKey = [secretAccessKey copy];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 300.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - PDSBlobProvider Protocol

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    if (!data || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid blob data"}];
        }
        return NO;
    }

    if (!cid || ![cid stringValue]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID"}];
        }
        return NO;
    }

    NSString *objectKey = [self objectKeyForCID:cid];
    NSURL *requestURL = [self s3URLForKey:objectKey];

    // Prepare request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = @"PUT";
    request.HTTPBody = data;

    // Set headers
    [request setValue:@(data.length).stringValue forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    // Sign request with AWS Signature V4
    [self signRequest:request
             method:@"PUT"
              body:data];

    // Execute request synchronously (for simplicity; async pattern could be added)
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    __block NSError *responseError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable responseData, NSURLResponse *_Nullable response, NSError *_Nullable taskError) {
            if (taskError) {
                responseError = taskError;
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
                if (!success) {
                    responseError = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                                        code:httpResponse.statusCode
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:@"S3 upload failed: %ld", (long)httpResponse.statusCode]}];
                }
            }
            dispatch_semaphore_signal(semaphore);
        }];

    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (responseError && error) {
        *error = responseError;
    }

    return success;
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    if (!cid || ![cid stringValue]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID"}];
        }
        return nil;
    }

    NSString *objectKey = [self objectKeyForCID:cid];
    NSURL *requestURL = [self s3URLForKey:objectKey];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = @"GET";

    // Sign request
    [self signRequest:request
             method:@"GET"
              body:nil];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSError *responseError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable taskError) {
            if (taskError) {
                responseError = taskError;
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode == 200) {
                    responseData = [data copy];
                } else if (httpResponse.statusCode == 404) {
                    responseError = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                                        code:3
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
                } else {
                    responseError = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                                        code:httpResponse.statusCode
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:@"S3 download failed: %ld", (long)httpResponse.statusCode]}];
                }
            }
            dispatch_semaphore_signal(semaphore);
        }];

    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (responseError && error) {
        *error = responseError;
    }

    return responseData;
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    if (!cid || ![cid stringValue]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID"}];
        }
        return NO;
    }

    NSString *objectKey = [self objectKeyForCID:cid];
    NSURL *requestURL = [self s3URLForKey:objectKey];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = @"DELETE";

    // Sign request
    [self signRequest:request
             method:@"DELETE"
              body:nil];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    __block NSError *responseError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable taskError) {
            if (taskError) {
                responseError = taskError;
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                // S3 DELETE is idempotent and returns 204 No Content on success
                success = (httpResponse.statusCode == 204 || httpResponse.statusCode == 200 || httpResponse.statusCode == 404);
                if (!success) {
                    responseError = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                                        code:httpResponse.statusCode
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:@"S3 delete failed: %ld", (long)httpResponse.statusCode]}];
                }
            }
            dispatch_semaphore_signal(semaphore);
        }];

    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (responseError && error) {
        *error = responseError;
    }

    return success;
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    if (!cid || ![cid stringValue]) {
        return NO;
    }

    NSString *objectKey = [self objectKeyForCID:cid];
    NSURL *requestURL = [self s3URLForKey:objectKey];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = @"HEAD";

    [self signRequest:request
             method:@"HEAD"
              body:nil];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL exists = NO;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable taskError) {
            if (!taskError) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                exists = (httpResponse.statusCode == 200);
            }
            dispatch_semaphore_signal(semaphore);
        }];

    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return exists;
}

#pragma mark - Private Helpers

- (NSString *)objectKeyForCID:(CID *)cid {
    NSString *cidString = [cid stringValue];
    NSString *key = cidString;

    if (self.keyPrefix && self.keyPrefix.length > 0) {
        key = [NSString stringWithFormat:@"%@%@", self.keyPrefix, cidString];
    }

    return key;
}

- (NSURL *)s3URLForKey:(NSString *)key {
    NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"]];

    NSString *urlString;
    if (self.endpoint) {
        // S3-compatible endpoint (MinIO, R2, B2, etc): use path-style
        // https://endpoint.example.com/bucket/key
        urlString = [NSString stringWithFormat:@"%@/%@/%@", self.endpoint, self.bucket, encodedKey];
    } else {
        // AWS S3: use virtual-hosted style
        // https://bucket.s3.region.amazonaws.com/key
        urlString = [NSString stringWithFormat:@"https://%@.s3.%@.amazonaws.com/%@",
                     self.bucket, self.region, encodedKey];
    }
    return [NSURL URLWithString:urlString];
}

#pragma mark - AWS Signature V4

- (void)signRequest:(NSMutableURLRequest *)request
              method:(NSString *)method
               body:(nullable NSData *)body {
    NSDate *now = [NSDate date];
    NSString *timestamp = [self iso8601Timestamp:now];
    NSString *dateStamp = [self dateStamp:now];

    // Add x-amz-date header
    [request setValue:timestamp forHTTPHeaderField:@"x-amz-date"];
    [request setValue:[self hostHeaderForURL:request.URL] forHTTPHeaderField:@"Host"];

    // Calculate body hash
    NSString *bodyHash = [self sha256HexString:body ?: [NSData data]];
    [request setValue:bodyHash forHTTPHeaderField:@"x-amz-content-sha256"];

    // Build canonical request
    NSString *canonicalRequest = [self buildCanonicalRequest:method
                                                         URL:request.URL
                                                     headers:request.allHTTPHeaderFields
                                                   bodyHash:bodyHash];

    // Create string to sign
    NSString *credentialScope = [NSString stringWithFormat:@"%@/%@/s3/aws4_request", dateStamp, self.region];
    NSString *canonicalRequestHash = [self sha256HexString:[canonicalRequest dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *stringToSign = [NSString stringWithFormat:@"AWS4-HMAC-SHA256\n%@\n%@\n%@",
                              timestamp, credentialScope, canonicalRequestHash];

    // Calculate signature
    NSString *signature = [self calculateSignature:stringToSign
                                         dateStamp:dateStamp
                                    credentialScope:credentialScope];

    // Add Authorization header
    NSString *authHeader = [NSString stringWithFormat:@"AWS4-HMAC-SHA256 Credential=%@/%@, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=%@",
                           self.accessKeyId, credentialScope, signature];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];
}

- (NSString *)buildCanonicalRequest:(NSString *)method
                                URL:(NSURL *)url
                            headers:(NSDictionary *)headers
                           bodyHash:(NSString *)bodyHash {
    // Canonical request format for AWS Signature V4
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:method];

    // Canonical URI
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *uri = components.percentEncodedPath.length > 0 ? components.percentEncodedPath : @"/";
    [lines addObject:uri];

    // Canonical query string
    NSString *query = components.percentEncodedQuery ?: @"";
    [lines addObject:query.length > 0 ? query : @""];

    // Canonical headers (sorted)
    NSMutableDictionary *canonicalHeaders = [NSMutableDictionary dictionary];
    for (NSString *key in headers) {
        NSString *lowerKey = [key lowercaseString];
        if ([lowerKey isEqualToString:@"host"] ||
            [lowerKey isEqualToString:@"x-amz-date"] ||
            [lowerKey isEqualToString:@"x-amz-content-sha256"]) {
            canonicalHeaders[lowerKey] = [headers[key] stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
        }
    }

    canonicalHeaders[@"host"] = [self hostHeaderForURL:url];

    NSArray *sortedKeys = [canonicalHeaders.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        [lines addObject:[NSString stringWithFormat:@"%@:%@", key, canonicalHeaders[key]]];
    }

    [lines addObject:@""]; // blank line after headers

    // Signed headers
    [lines addObject:[sortedKeys componentsJoinedByString:@";"]];

    // Payload hash
    [lines addObject:bodyHash];

    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)calculateSignature:(NSString *)stringToSign
                       dateStamp:(NSString *)dateStamp
                  credentialScope:(NSString *)credentialScope {
    // kSecret = HMAC-SHA256("AWS4" + secretAccessKey, Date)
    NSString *kSecret = [NSString stringWithFormat:@"AWS4%@", self.secretAccessKey];
    NSData *kDate = [self hmacSha256:kSecret.UTF8String
                            length:strlen(kSecret.UTF8String)
                              data:dateStamp.UTF8String
                          dataLen:strlen(dateStamp.UTF8String)];

    // kRegion = HMAC-SHA256(kDate, Region)
    NSData *kRegion = [self hmacSha256:(const char *)kDate.bytes
                               length:(int)kDate.length
                                 data:self.region.UTF8String
                             dataLen:strlen(self.region.UTF8String)];

    // kService = HMAC-SHA256(kRegion, "s3")
    NSData *kService = [self hmacSha256:(const char *)kRegion.bytes
                                length:(int)kRegion.length
                                  data:"s3"
                              dataLen:2];

    // kSigning = HMAC-SHA256(kService, "aws4_request")
    NSData *kSigning = [self hmacSha256:(const char *)kService.bytes
                               length:(int)kService.length
                                 data:"aws4_request"
                             dataLen:12];

    // signature = HMAC-SHA256(kSigning, stringToSign)
    NSData *signature = [self hmacSha256:(const char *)kSigning.bytes
                                length:(int)kSigning.length
                                  data:stringToSign.UTF8String
                              dataLen:strlen(stringToSign.UTF8String)];

    return [CryptoUtils hexStringFromData:signature];
}

#pragma mark - Crypto Helpers

- (NSData *)hmacSha256:(const char *)key length:(int)keyLen data:(const char *)data dataLen:(int)dataLen {
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key, keyLen, data, dataLen, result);
    return [NSData dataWithBytes:result length:CC_SHA256_DIGEST_LENGTH];
}

- (NSString *)sha256HexString:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [self bytesToHex:hash length:CC_SHA256_DIGEST_LENGTH];
}

- (NSString *)bytesToHex:(unsigned char *)bytes length:(int)length {
    NSMutableString *hexString = [NSMutableString string];
    for (int i = 0; i < length; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    return hexString;
}

- (NSString *)iso8601Timestamp:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMdd'T'HHmmss'Z'"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    });
    return [formatter stringFromDate:date];
}

- (NSString *)dateStamp:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMdd"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    });
    return [formatter stringFromDate:date];
}

- (NSString *)hostHeaderForURL:(NSURL *)url {
    if (url.port) {
        return [NSString stringWithFormat:@"%@:%@", url.host, url.port];
    }
    return url.host ?: @"";
}

- (nullable NSArray<CID *> *)listAllCIDsWithError:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                     code:501 // Not Implemented
                                 userInfo:@{NSLocalizedDescriptionKey: @"listAllCIDs is not supported for Cloud Storage"}];
    }
    return nil;
}

- (nullable NSInputStream *)retrieveBlobStreamForCID:(CID *)cid error:(NSError **)error {
    // Cloud storage does not support streaming retrieval; use retrieveBlobForCID:error: instead.
    if (error) {
        *error = [NSError errorWithDomain:PDSCloudStorageBlobProviderErrorDomain
                                     code:501 // Not Implemented
                                 userInfo:@{NSLocalizedDescriptionKey: @"retrieveBlobStreamForCID is not supported for Cloud Storage"}];
    }
    return nil;
}

@end
