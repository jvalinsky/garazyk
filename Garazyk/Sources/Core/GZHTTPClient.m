// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/GZHTTPClient.h"

static id<GZHTTPClient> _Nullable gSharedGZHTTPClient = nil;

@implementation GZHTTPClientRegistry

+ (nullable id<GZHTTPClient>)sharedClient {
    return gSharedGZHTTPClient;
}

+ (void)setSharedClient:(nullable id<GZHTTPClient>)client {
    gSharedGZHTTPClient = client;
}

@end
