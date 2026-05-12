// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewWebhookHook.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Hooks/AppViewWebhookHook.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"

@interface AppViewWebhookHook ()

@property (nonatomic, copy) NSString *webhookURL;
@property (nonatomic, copy, nullable) NSArray<NSString *> *hookCollections;

@end

@implementation AppViewWebhookHook

- (instancetype)initWithWebhookURL:(NSString *)webhookURL
                       collections:(nullable NSArray<NSString *> *)collections {
    self = [super init];
    if (self) {
        _webhookURL = [webhookURL copy];
        _hookCollections = [collections copy];
    }
    return self;
}

- (instancetype)initWithWebhookURL:(NSString *)webhookURL {
    return [self initWithWebhookURL:webhookURL collections:nil];
}

- (NSString *)hookIdentifier {
    return [NSString stringWithFormat:@"webhook-%@", self.webhookURL];
}

- (nullable NSArray<NSString *> *)collections {
    return _hookCollections;
}

- (void)didIndexRecord:(NSDictionary *)record
                   uri:(NSString *)uri
                    did:(NSString *)did
            collection:(NSString *)collection {
    NSDictionary *payload = @{
        @"event": @"index",
        @"uri": uri,
        @"did": did,
        @"collection": collection,
        @"timestamp": [[NSDate date] description]
    };

    [self postWebhookWithPayload:payload];
}

- (void)didDeleteRecordWithURI:(NSString *)uri
                           did:(NSString *)did
                    collection:(NSString *)collection {
    NSDictionary *payload = @{
        @"event": @"delete",
        @"uri": uri,
        @"did": did,
        @"collection": collection,
        @"timestamp": [[NSDate date] description]
    };

    [self postWebhookWithPayload:payload];
}

#pragma mark - Private

- (void)postWebhookWithPayload:(NSDictionary *)payload {
    if (self.webhookURL.length == 0) return;

    NSURL *url = [NSURL URLWithString:self.webhookURL];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"Garazyk-AppView/1.0" forHTTPHeaderField:@"User-Agent"];

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (body) {
        request.HTTPBody = body;
    }

    // Use ATProtoSafeHTTPClient for SSRF protection and GNUstep socket leak fix
    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.timeout = 10.0;
    options.maxResponseBytes = 0; // Don't need response body
    options.allowHTTP = YES;       // Webhooks may be internal
    options.allowPrivateHosts = YES;
    options.followRedirects = NO;

    [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                             options:options
                                                          completion:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            GZ_LOG_DEBUG(@"[WebhookHook] POST to %@ failed: %@",
                          self.webhookURL, error.localizedDescription);
        }
    }];
}

@end
