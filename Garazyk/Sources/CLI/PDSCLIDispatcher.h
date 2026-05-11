// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Provides testing hooks for the CLI dispatcher.
 */
@interface PDSCLIDispatcher (Testing)

/**
 * @brief Reset the registered command set to the default built-in commands.
 */
- (void)resetCommandsToDefaults;

@end

/**
 * @class PDSCLIServiceStub
 *
 * @brief Lightweight stub that represents service state for CLI tests.
 *
 * This stub is intentionally minimal: it provides a placeholder DID/host
 * and a canned payload generator so tests can reason about service auth
 * arguments without depending on the full server stack.
 */
typedef NSDictionary<NSString *, id> *_Nullable (^PDSCLIServicePayloadProvider)(NSString *audience, NSString *method, NSTimeInterval expiry);

@interface PDSCLIServiceStub : NSObject

@property (nonatomic, copy) NSString *serviceDid;
@property (nonatomic, copy) NSString *serviceHost;
@property (nonatomic, copy, nullable) PDSCLIServicePayloadProvider payloadProvider;

/**
 * @brief Returns the singleton stub instance.
 */
+ (instancetype)sharedStub;

/**
 * @brief Builds a lightweight payload used when service auth is required.
 *
 * @param audience The required audience DID string.
 * @param method   Optional NSID for the requested RPC.
 * @param expiry   Timestamp (seconds since epoch) when the token should expire.
 */
- (NSDictionary *)payloadForAudience:(NSString *)audience method:(nullable NSString *)method expiry:(NSTimeInterval)expiry;

@end

NS_ASSUME_NONNULL_END
