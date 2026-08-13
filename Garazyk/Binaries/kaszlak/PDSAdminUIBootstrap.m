// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CLI/PDSAdminUIBootstrap.h"

#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"
#import "AdminUIServer/Packs/GZAdminUIOzonePack.h"
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"
#import "AdminUIServer/Packs/GZAdminUIDataExplorerPack.h"
#import "AdminUIServer/Packs/GZAdminUIMSTPack.h"
#import "AdminUIServer/Packs/GZAdminUILabPack.h"
#import "Debug/GZLogger.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * _Nullable PDSAdminUIEnv(NSString *name) {
    const char *raw = getenv(name.UTF8String);
    if (!raw || raw[0] == '\0') {
        return nil;
    }
    return [[NSString stringWithUTF8String:raw]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString * _Nullable PDSAdminUIReadPasswordFile(NSString *path) {
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (!contents) {
        GZ_LOG_CORE_WARN(@"Failed to read admin UI password file %@: %@", path,
                         error.localizedDescription);
        return nil;
    }
    return [contents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString * _Nullable PDSAdminUIResolvePassword(void) {
    NSString *uiPassword = PDSAdminUIEnv(@"PDS_ADMIN_UI_PASSWORD");
    if (uiPassword.length > 0) {
        return uiPassword;
    }
    NSString *uiFile = PDSAdminUIEnv(@"PDS_ADMIN_UI_PASSWORD_FILE");
    if (uiFile.length > 0) {
        NSString *fromFile = PDSAdminUIReadPasswordFile(uiFile);
        if (fromFile.length > 0) {
            return fromFile;
        }
    }
    // Reuse the PDS protocol admin password so one secret covers UI + /admin/login.
    NSString *file = PDSAdminUIEnv(@"PDS_ADMIN_PASSWORD_FILE");
    if (file.length > 0) {
        NSString *fromFile = PDSAdminUIReadPasswordFile(file);
        if (fromFile.length > 0) {
            return fromFile;
        }
    }
    return PDSAdminUIEnv(@"PDS_ADMIN_PASSWORD");
}

GZAdminUIHost * _Nullable PDSAdminUIStartHost(
    NSUInteger protocolPort,
    id<GZAdminUIPDSOverviewSnapshot> _Nullable overviewSnapshot,
    NSError * _Nullable * _Nullable error) {
    NSString *password = PDSAdminUIResolvePassword();
    if (password.length == 0) {
        GZ_LOG_CORE_WARN(@"PDS admin UI disabled: set PDS_ADMIN_PASSWORD "
                         @"(or PDS_ADMIN_UI_PASSWORD / *_FILE)");
        return nil;
    }

    NSString *host = PDSAdminUIEnv(@"PDS_ADMIN_UI_HOST") ?: @"127.0.0.1";
    NSString *portValue = PDSAdminUIEnv(@"PDS_ADMIN_UI_PORT");
    NSInteger parsedPort = portValue.integerValue;
    NSUInteger port = 2590;
    if (portValue.length > 0) {
        if (parsedPort <= 0 || parsedPort > 65535) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.garazyk.pds.admin-ui"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey :
                                                        @"PDS_ADMIN_UI_PORT must be 1–65535"}];
            }
            return nil;
        }
        port = (NSUInteger)parsedPort;
    }

    GZAdminUIServiceConfig *adminConfig = [[GZAdminUIServiceConfig alloc] init];
    adminConfig.host = host;
    adminConfig.port = port;
    adminConfig.adminPassword = password;
    adminConfig.serviceIdentifier = @"pds";
    adminConfig.pdsBaseURL =
        [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu",
                                                        (unsigned long)protocolPort]];
    adminConfig.pdsAdminPassword = password;
    // UIServiceConfig -init already probes Assets/ next to the executable.
    // Allow an explicit override for packaged layouts (systemd cwd ≠ bin dir).
    NSString *assetsOverride = PDSAdminUIEnv(@"GARAZYK_ADMIN_UI_ASSETS_DIR")
        ?: PDSAdminUIEnv(@"PDS_ADMIN_UI_ASSETS_DIR");
    if (assetsOverride.length > 0) {
        adminConfig.assetsDirectory = assetsOverride;
    } else if (adminConfig.assetsDirectory.length == 0) {
        NSString *cwdAssets = [[[NSFileManager defaultManager] currentDirectoryPath]
            stringByAppendingPathComponent:@"build-linux/bin/Assets"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:cwdAssets]) {
            adminConfig.assetsDirectory = cwdAssets;
        }
    }

    // Plain configured sibling links only — no polling or health claims.
    GZAdminUIServiceConfig *envPeers = [GZAdminUIServiceConfig configurationFromEnvironment];
    adminConfig.peerLinks = envPeers.peerLinks;

    NSArray<Class> *packs = @[
        GZAdminUIPDSPack.class,
        GZAdminUIOzonePack.class,
        GZAdminUISecurityPack.class,
        GZAdminUIDataExplorerPack.class,
        GZAdminUIMSTPack.class,
        GZAdminUILabPack.class,
    ];

    GZAdminUIHost *adminHost =
        [[GZAdminUIHost alloc] initWithConfiguration:adminConfig packs:packs];
    if (![adminHost startWithError:error]) {
        return nil;
    }

    if (overviewSnapshot) {
        [GZAdminUIPDSPack configureHost:adminHost snapshot:overviewSnapshot];
    }

    GZ_LOG_CORE_INFO(@"PDS admin UI listening on http://%@:%lu/admin", host,
                     (unsigned long)port);
    return adminHost;
}

NS_ASSUME_NONNULL_END
