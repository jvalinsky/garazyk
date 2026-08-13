// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileDemoPathResolver.h

 @abstract Built-in demo tile path resolver (no Repository/CAR dependency).
 */

#import <Foundation/Foundation.h>
#import "AdminUIServer/UITilePathResolver.h"

NS_ASSUME_NONNULL_BEGIN

/** Serves the bounded demo tile resource map (`/` + `/app.js`). */
@interface GZAdminUIDemoTilePathResolver : NSObject <GZAdminUITilePathResolver>
@end

NS_ASSUME_NONNULL_END
