// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

@interface PDSSpaceOplogPruner : NSObject

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                retentionRevisions:(NSUInteger)retentionRevisions
      intervalInSeconds:(NSTimeInterval)interval;

- (void)start;
- (void)stop;
- (void)pruneNow;

@end

NS_ASSUME_NONNULL_END
