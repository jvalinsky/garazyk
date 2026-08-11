// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIDefaultPacks.h"

#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"
#import "AdminUIServer/Packs/GZAdminUIAppViewPack.h"
#import "AdminUIServer/Packs/GZAdminUIDataExplorerPack.h"
#import "AdminUIServer/Packs/GZAdminUILabPack.h"
#import "AdminUIServer/Packs/GZAdminUIOzonePack.h"
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"
#import "AdminUIServer/Packs/GZAdminUIChatPack.h"
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"
#import "AdminUIServer/Packs/GZAdminUIMSTPack.h"

NSArray<Class> *GZAdminUIDefaultPacks(void) {
    return @[
        GZAdminUIPDSPack.class,
        GZAdminUIAppViewPack.class,
        GZAdminUIDataExplorerPack.class,
        GZAdminUILabPack.class,
        GZAdminUIOzonePack.class,
        GZAdminUISecurityPack.class,
        GZAdminUIMSTPack.class,
        GZAdminUIChatPack.class,
        GZAdminUIVideoPack.class,
    ];
}
