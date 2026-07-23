// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+MST.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (MST)

- (NSDictionary *)fetchMSTAccounts {
    NSURL *url = [self URLByAppendingPath:@"/api/mst/accounts"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_accounts_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST accounts"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/tree/%@", did]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_tree_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST tree"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/stats/%@", did]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_stats_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST stats"};
    }
    return response ?: @{};
}

- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format {
    if (did.length == 0) {
        return nil;
    }
    NSString *formatParam = [format isEqualToString:@"dot"] ? @"dot" : [format isEqualToString:@"svg"] ? @"svg" : @"json";
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/export/%@", did]
                              queryItems:@{@"format": formatParam}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = [self performRequestWithURL:url
                                        method:@"GET"
                                          body:nil
                                   contentType:nil
                                    bearerToken:self.configuration.pdsAdminToken
                                     statusCode:&status
                                          error:&error];
    if (status < 200 || status >= 300) {
        return nil;
    }
    return data;
}

@end
