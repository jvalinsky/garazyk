// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebTile+CAR.h

 @abstract Load a Web Tile from a DASL CAR / `.tile` archive.
 */

#import "Core/ATProtoWebTile.h"

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoWebTile (CAR)

/**
 Reads a CAR (optionally strict DASL), validates header MASL as a Web Tile,
 and confirms the `/` resource CID is present in the archive body.
 Retains the CAR reader so `-responseForPath:error:` can resolve arbitrary
 declared resource paths to `{status, headers, body}`.
 */
+ (nullable instancetype)tileWithCARData:(NSData *)carData
                                  strict:(BOOL)strict
                                   error:(NSError **)error;

/**
 Resolves a MASL resource path against the retained CAR body.

 Query/fragment are stripped by MASL path resolution. Undeclared paths and
 missing blocks return status 404 with an empty body (no throw). Returns nil
 only when the tile was not loaded from CAR or MASL lookup fails for a
 non-path reason.
 */
- (nullable NSDictionary<NSString *, id> *)responseForPath:(NSString *)path
                                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
