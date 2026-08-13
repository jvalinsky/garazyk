// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Repository/ATProtoWebTile+CAR.h"
#import "Repository/CAR.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import <objc/runtime.h>

static const void *kATProtoWebTileCARReaderKey = &kATProtoWebTileCARReaderKey;

@implementation ATProtoWebTile (CAR)

+ (nullable instancetype)tileWithCARData:(NSData *)carData
                                  strict:(BOOL)strict
                                   error:(NSError **)error {
    ATProtoCARReader *reader = [ATProtoCARReader readFromData:carData strict:strict error:error];
    if (!reader) return nil;
    ATProtoMASLDocument *masl = reader.maslDocument;
    if (!masl) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoWebTileErrorDomain
                                         code:ATProtoWebTileErrorInvalidDocument
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"CAR header is not a valid MASL document"}];
        }
        return nil;
    }
    if (![masl validateForCARWithError:error]) return nil;
    ATProtoWebTile *tile = [self tileWithMASLDocument:masl error:error];
    if (!tile) return nil;
    if (![reader blockWithCID:tile.rootResourceCID]) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoWebTileErrorDomain
                                         code:ATProtoWebTileErrorMissingRoot
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Web Tile / resource CID is missing from CAR body"}];
        }
        return nil;
    }
    objc_setAssociatedObject(tile, kATProtoWebTileCARReaderKey, reader,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return tile;
}

- (nullable NSDictionary<NSString *, id> *)responseForPath:(NSString *)path
                                                     error:(NSError **)error {
    ATProtoCARReader *reader = objc_getAssociatedObject(self, kATProtoWebTileCARReaderKey);
    if (!reader) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoWebTileErrorDomain
                                         code:ATProtoWebTileErrorInvalidDocument
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Web Tile has no CAR body for path resolution"}];
        }
        return nil;
    }

    NSError *pathError = nil;
    ATProtoCID *cid = [self.document resourceCIDForPath:path error:&pathError];
    if (!cid) {
        // Undeclared path → mothership-style 404 without body.
        if ([pathError.domain isEqualToString:ATProtoMASLErrorDomain] &&
            pathError.code == ATProtoMASLErrorInvalidResourcePath) {
            return @{ @"status": @404, @"headers": @{}, @"body": [NSData data] };
        }
        if (error) *error = pathError;
        return nil;
    }

    NSError *headerError = nil;
    NSDictionary *headers = [self.document httpHeadersForPath:path error:&headerError] ?: @{};
    if (!headers && headerError) {
        if (error) *error = headerError;
        return nil;
    }

    ATProtoCARBlock *block = [reader blockWithCID:cid];
    if (!block) {
        return @{ @"status": @404, @"headers": headers ?: @{}, @"body": [NSData data] };
    }
    return @{
        @"status": @200,
        @"headers": headers ?: @{},
        @"body": block.data ?: [NSData data],
    };
}

@end
