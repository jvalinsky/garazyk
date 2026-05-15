// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ConstellationConfiguration.h

 @abstract Runtime configuration for the Constellation link-index service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConstellationConfiguration : NSObject

@property (nonatomic, strong) NSArray<NSString *> *relayURLs;
@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, assign) NSUInteger httpPort;
@property (nonatomic, assign) NSUInteger cursorCheckpointIntervalMs;
@property (nonatomic, assign) BOOL ingestEnabled;

+ (instancetype)defaultConfiguration;
+ (instancetype)configurationFromEnvironment;
- (void)loadFromDictionary:(NSDictionary *)dictionary;
- (BOOL)validate:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
