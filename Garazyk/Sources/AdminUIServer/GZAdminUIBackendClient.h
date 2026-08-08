// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class UIServiceConfig;
@class ATProtoSafeHTTPClient;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Calls backend admin services on behalf of the Admin UI.
 */
@interface GZAdminUIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration
                           httpClient:(nullable ATProtoSafeHTTPClient *)httpClient;

@end

NS_ASSUME_NONNULL_END

#import "AdminUIServer/Packs/GZAdminUIBackendClient+PDS.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+AppView.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Relay.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+PLC.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+DataExplorer.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Chat.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Video.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Ozone.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Security.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+MST.h"
