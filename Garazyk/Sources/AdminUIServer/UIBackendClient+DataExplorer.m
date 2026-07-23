// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+DataExplorer.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (DataExplorer)

- (NSDictionary *)describeRepo:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.describeRepo"
                              queryItems:@{@"repo": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"describe_repo_failed", @"message": error.localizedDescription ?: @"Describe repo failed"};
    }
    return response;
}

- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(NSString *)collection limit:(NSUInteger)limit cursor:(NSString *)cursor {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"repo"] = did;
    if (collection.length > 0) params[@"collection"] = collection;
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.listRecords" queryItems:params baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"list_records_failed", @"message": error.localizedDescription ?: @"List records failed"};
    }
    return response;
}

- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID, collection, and rkey required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.getRecord"
                              queryItems:@{@"repo": did, @"collection": collection, @"rkey": rkey}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"get_record_failed", @"message": error.localizedDescription ?: @"Get record failed"};
    }
    return response;
}

- (NSDictionary *)fetchBlobsForDID:(NSString *)did limit:(NSUInteger)limit cursor:(nullable NSString *)cursor {
    if (!did || did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSMutableDictionary *queryItems = [NSMutableDictionary dictionary];
    queryItems[@"did"] = did;
    if (limit > 0) {
        queryItems[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    }
    if (cursor && cursor.length > 0) {
        queryItems[@"cursor"] = cursor;
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.sync.listBlobs"
                              queryItems:queryItems
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"blob_list_failed", @"message": error.localizedDescription ?: @"Failed to fetch blobs"};
    }
    return response ?: @{@"blobs": @[]};
}

- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid {
    if (did.length == 0 || cid.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and CID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.sync.getBlob"
                              queryItems:@{@"did": did, @"cid": cid}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"blob_fetch_failed", @"message": error.localizedDescription ?: @"Blob fetch failed"};
    }
    return response;
}

@end
