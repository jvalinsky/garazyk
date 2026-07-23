// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class UIServiceConfig;
@class ATProtoSafeHTTPClient;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Calls backend admin services on behalf of the Admin UI.
 */
@interface UIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration
                           httpClient:(nullable ATProtoSafeHTTPClient *)httpClient;

@end

NS_ASSUME_NONNULL_END

#import "AdminUIServer/UIBackendClient+PDS.h"
#import "AdminUIServer/UIBackendClient+AppView.h"
#import "AdminUIServer/UIBackendClient+Relay.h"
#import "AdminUIServer/UIBackendClient+PLC.h"
#import "AdminUIServer/UIBackendClient+DataExplorer.h"
#import "AdminUIServer/UIBackendClient+Chat.h"
#import "AdminUIServer/UIBackendClient+Video.h"
#import "AdminUIServer/UIBackendClient+Ozone.h"
#import "AdminUIServer/UIBackendClient+Security.h"
#import "AdminUIServer/UIBackendClient+MST.h"
