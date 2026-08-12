// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Live handles for rebuilding @c JelczAdminSnapshot on each admin poll.
 */
@interface GZJelczAdminEmbedContext : NSObject

@property (nonatomic, strong, nullable) id worker;
@property (nonatomic, strong, nullable) id jobStore;
@property (nonatomic, copy) NSDictionary<NSString *, id> *config;
@property (nonatomic, strong) NSDate *startTime;

- (instancetype)initWithWorker:(nullable id)worker
                      jobStore:(nullable id)jobStore
                        config:(NSDictionary<NSString *, id> *)config
                     startTime:(NSDate *)startTime;

- (NSTimeInterval)uptimeSeconds;

@end

NS_ASSUME_NONNULL_END
