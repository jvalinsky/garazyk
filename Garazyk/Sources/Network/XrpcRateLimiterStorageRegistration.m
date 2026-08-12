// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// Registers ATProtoRateLimiter's (Transport) storage factory with the concrete
// Storage classes it needs (ATProtoConnectionManagerSerial,
// ATProtoDatabaseQueryRunner), at process load time. This file lives in the
// XRPC module specifically because XRPC is the one module in the DAG that
// already legitimately depends on both Storage and Transport (workstream 08
// M4, Transport -> Storage inversion) — putting this registration in Storage
// itself would just invert the leak instead of removing it, and every
// binary that constructs a ATProtoRateLimiter (kaszlak, Mikrus, Beskid) already
// links ATProtoXRPC. Mirrors the existing GZHTTPClientRegistry /
// ATProtoSafeHTTPClient self-registration pattern from workstream 08 M2.
#import "Network/RateLimiter.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"

@interface ATProtoXrpcRateLimiterStorageRegistration : NSObject
@end

@implementation ATProtoXrpcRateLimiterStorageRegistration

+ (void)load {
    RateLimiterSetStorageFactory(^ATProtoRateLimiterStorageHandle * _Nullable(NSString *path, ATProtoDBConfig config, NSError **error) {
        ATProtoConnectionManagerSerial *connectionManager =
            [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.ratelimiter.db"];
        if (![connectionManager openWithPath:path config:config error:error]) {
            return nil;
        }
        ATProtoDatabaseQueryRunner *queryRunner =
            [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:connectionManager
                                                                errorDomain:@"RateLimiterErrorDomain"];
        return [[ATProtoRateLimiterStorageHandle alloc] initWithConnectionManager:connectionManager
                                                                queryRunner:queryRunner];
    });
}

@end
