// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"

@class RelayConfiguration;
@class RelayUpstreamManager;
@class RelayMetrics;
@class RelayRepoStateManager;
@class RelayEventBuffer;

NS_ASSUME_NONNULL_BEGIN

@interface PDSCLIRelayCommand : PDSBaseCommand

@property (nonatomic, strong, nullable) RelayConfiguration *configuration;
@property (nonatomic, strong, nullable) RelayUpstreamManager *upstreamManager;
@property (nonatomic, strong, nullable) RelayMetrics *metrics;
@property (nonatomic, strong, nullable) RelayRepoStateManager *repoStateManager;
@property (nonatomic, strong, nullable) RelayEventBuffer *eventBuffer;

@end

NS_ASSUME_NONNULL_END
