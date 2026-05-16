// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ChatRuntime.h
 @brief Standalone runtime for the Chat service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ChatConfiguration;

/**
 * @abstract Owns startup and shutdown for the chat service runtime.
 */
@interface ChatRuntime : NSObject

@property (nonatomic, strong, readonly) ChatConfiguration *configuration;
@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedRuntime;

- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error;
/**
 * @abstract Load configuration from environment.
 */
- (void)loadConfigurationFromEnvironment;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
