// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"

@implementation GZAdminUIPDSPack

+ (NSString *)packIdentifier {
    return @"pds";
}

+ (NSString *)displayName {
    return @"PDS";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    // Populated when the shell is made composable (WS11 M2 slice 4).
    return @[];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerPDSRoutes];
}

@end
