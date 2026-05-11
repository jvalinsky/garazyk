// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayRepoStateManager.h

 @abstract Tracks repository state for the relay.

 @discussion
    RelayRepoStateManager tracks:
    - Current root CID for each repo
    - Last sequence number for each repo
    - Repo status (active, desynchronized, etc.)
    
    Sync v1.1 account statuses:
    - desynchronized: out-of-sync with current revision
    - in-progress: actively synchronizing
    - throttled: temporary failure

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RelayRepoStatus) {
    RelayRepoStatusActive,
    RelayRepoStatusDesynchronized,
    RelayRepoStatusInProgress,
    RelayRepoStatusThrottled,
    RelayRepoStatusTombstoned
};

@interface RelayRepoStateManager : NSObject

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)handleCommitForRepo:(NSString *)repoDID
                       root:(NSString *)rootCID
                         rev:(NSString *)rev
                         seq:(int64_t)seq;

- (void)handleIdentityEventForRepo:(NSString *)repoDID;
- (void)handleAccountEventForRepo:(NSString *)repoDID status:(RelayRepoStatus)status;
- (void)handleTombstoneForRepo:(NSString *)repoDID;

- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID;
- (nullable NSString *)revForRepo:(NSString *)repoDID;
- (int64_t)cursorForRepo:(NSString *)repoDID;
- (RelayRepoStatus)statusForRepo:(NSString *)repoDID;

- (NSArray<NSString *> *)allRepos;
- (NSUInteger)repoCount;

- (void)persistState;
- (BOOL)loadState:(NSError **)error;

@end

NS_ASSUME_NONNULL_END