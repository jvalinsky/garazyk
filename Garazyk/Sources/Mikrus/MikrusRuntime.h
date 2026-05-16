// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file MikrusRuntime.h

 @abstract Top-level coordinator for the Mikrus link index service.
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Ingest/AppViewIngestEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class MikrusConfiguration;
@class MikrusDatabase;

@interface MikrusRuntime : NSObject <AppViewIngestEngineDelegate>

@property (nonatomic, strong, readonly) MikrusConfiguration *configuration;
@property (nonatomic, strong, readonly) MikrusDatabase *database;
@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedRuntime;
- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error;
- (void)loadConfigurationFromEnvironment;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
