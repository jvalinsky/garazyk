// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebTile.h

 @abstract Web Tile validation over MASL bundle documents.

 @discussion A Web Tile is a MASL Bundle Mode document with a `name` (≤1000
 chars / ≤100 graphemes) and a `resources` map that includes a `/` root entry
 (https://dasl.ing/tiles.html). This model validates those constraints; CAR
 loading belongs with `ATProtoCARReader` + this validator.
 */

#import <Foundation/Foundation.h>

@class ATProtoMASLDocument;
@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoWebTileErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoWebTileErrorCode) {
    ATProtoWebTileErrorInvalidDocument = 1,
    ATProtoWebTileErrorMissingName = 2,
    ATProtoWebTileErrorInvalidName = 3,
    ATProtoWebTileErrorMissingRoot = 4,
};

/**
 Validated Web Tile view of a MASL bundle document.
 */
@interface ATProtoWebTile : NSObject

@property (nonatomic, strong, readonly) ATProtoMASLDocument *document;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, strong, readonly, nullable) ATProtoCID *rootResourceCID;

/** Validates a MASL document as a Web Tile. */
+ (nullable instancetype)tileWithMASLDocument:(ATProtoMASLDocument *)document
                                        error:(NSError **)error;

/** Decodes DRISL bytes, validates MASL, then validates as a Web Tile. */
+ (nullable instancetype)tileWithDRISLData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
