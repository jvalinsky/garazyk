// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoWebTile.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"

NSString * const ATProtoWebTileErrorDomain = @"com.atproto.webtile";

static NSError *WebTileError(ATProtoWebTileErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoWebTileErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void WebTileSetError(NSError **error, ATProtoWebTileErrorCode code, NSString *message) {
    if (error) *error = WebTileError(code, message);
}

static NSUInteger WebTileGraphemeCount(NSString *string) {
    // Prefer composed-character stepping over enumerateSubstringsInRange:
    // GNUstep raises NSRangeException ("Invalid location.") for
    // NSStringEnumerationByComposedCharacterSequences.
    NSUInteger length = string.length;
    if (length == 0) return 0;
    NSUInteger count = 0;
    NSUInteger index = 0;
    while (index < length) {
        NSRange range = [string rangeOfComposedCharacterSequenceAtIndex:index];
        if (range.length == 0 || range.location != index) {
            // Fallback: treat remaining UTF-16 units as graphemes.
            return count + (length - index);
        }
        count++;
        index = NSMaxRange(range);
    }
    return count;
}

@implementation ATProtoWebTile

+ (nullable instancetype)tileWithMASLDocument:(ATProtoMASLDocument *)document
                                        error:(NSError **)error {
    if (![document isKindOfClass:[ATProtoMASLDocument class]] || !document.isBundle) {
        WebTileSetError(error, ATProtoWebTileErrorInvalidDocument,
                        @"Web Tile requires a MASL bundle document");
        return nil;
    }
    id nameValue = document.object[@"name"];
    if (![nameValue isKindOfClass:[NSString class]] || [(NSString *)nameValue length] == 0) {
        WebTileSetError(error, ATProtoWebTileErrorMissingName,
                        @"Web Tile requires a non-empty name");
        return nil;
    }
    NSString *name = (NSString *)nameValue;
    if (name.length > 1000 || WebTileGraphemeCount(name) > 100) {
        WebTileSetError(error, ATProtoWebTileErrorInvalidName,
                        @"Web Tile name exceeds 1000 characters or 100 graphemes");
        return nil;
    }
    if (![document.resources isKindOfClass:[NSDictionary class]] ||
        document.resources[@"/"] == nil) {
        WebTileSetError(error, ATProtoWebTileErrorMissingRoot,
                        @"Web Tile resources must include a / root entry");
        return nil;
    }
    NSError *rootError = nil;
    ATProtoCID *rootCID = [document resourceCIDForPath:@"/" error:&rootError];
    if (!rootCID) {
        WebTileSetError(error, ATProtoWebTileErrorMissingRoot,
                        rootError.localizedDescription ?: @"Web Tile / entry requires a src CID");
        return nil;
    }

    ATProtoWebTile *tile = [[ATProtoWebTile alloc] init];
    tile->_document = document;
    tile->_name = [name copy];
    tile->_rootResourceCID = rootCID;
    return tile;
}

+ (nullable instancetype)tileWithDRISLData:(NSData *)data error:(NSError **)error {
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithDRISLData:data error:error];
    if (!document) return nil;
    return [self tileWithMASLDocument:document error:error];
}

@end
