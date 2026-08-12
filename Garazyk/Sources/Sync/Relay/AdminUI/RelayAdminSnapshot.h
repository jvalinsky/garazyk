// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class ATProtoRelayMetrics;
@class ATProtoRelayUpstreamManager;

NS_ASSUME_NONNULL_BEGIN

/** Reads a newline-terminated systemd/NixOS credential without exposing it in errors. */
FOUNDATION_EXPORT NSString * _Nullable GZRelayAdminPasswordFromFile(NSString *path,
                                                                     NSError * _Nullable * _Nullable error);

/** Bounded, synchronized Relay operations view for the embedded Admin UI. */
@interface GZRelayAdminSnapshot : NSObject
- (instancetype)initWithMetrics:(ATProtoRelayMetrics *)metrics
                 upstreamManager:(ATProtoRelayUpstreamManager *)upstreamManager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSDictionary<NSString *, id> *)snapshot;
- (NSDictionary<NSString *, id> *)performAction:(NSString *)action
                                      hostname:(nullable NSString *)hostname;
@end

NS_ASSUME_NONNULL_END
