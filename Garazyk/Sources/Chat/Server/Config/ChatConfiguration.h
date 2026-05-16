// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ChatConfiguration.h
 @brief Configuration for the standalone Chat service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChatConfiguration : NSObject

/**
 * @abstract Filesystem directory used for chat service data.
 */
@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, assign) NSUInteger httpPort;
@property (nonatomic, copy) NSString *adminSecret;
@property (nonatomic, copy) NSString *pdsUrl;

@property (nonatomic, copy) NSString *serviceDomain;
@property (nonatomic, readonly) NSString *serviceDID;

/**
 * @abstract Default configuration.
 * @return An initialized instance.
 */
+ (instancetype)defaultConfiguration;
- (BOOL)loadFromFile:(NSString *)path error:(NSError **)error;
- (void)loadFromEnvironment;

@end

NS_ASSUME_NONNULL_END
