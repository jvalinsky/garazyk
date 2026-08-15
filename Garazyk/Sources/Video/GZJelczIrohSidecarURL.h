// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczIrohSidecarURL.h

 @abstract Loopback (default) or Docker-lab sidecar HTTP base normalization.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczIrohSidecarURL : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Default: loopback only. With @c trustLan, also allow iroh-a, iroh-b, and iroh-c. */
+ (nullable NSString *)normalizedHTTPBase:(NSString *)raw trustLan:(BOOL)trustLan;

@end

NS_ASSUME_NONNULL_END
