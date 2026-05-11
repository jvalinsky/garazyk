// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayEventFilter.h

 @abstract Filter events by collection, repo, or actor for the relay.

 @discussion
    RelayEventFilter allows downstream consumers to receive filtered events.
    Filters are applied after validation, before forwarding.
    
    - Filter by collection (e.g., "app.bsky.feed.post")
    - Filter by repo DID
    - Block by actor DID

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RelayEventFilter : NSObject

@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *allowedCollections;
@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *allowedRepos;
@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *blockedActors;

- (instancetype)initWithAllowedCollections:(nullable NSArray<NSString *> *)collections
                          allowedRepos:(nullable NSArray<NSString *> *)repos
                          blockedActors:(nullable NSArray<NSString *> *)actors NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)setAllowedCollections:(nullable NSArray<NSString *> *)collections;
- (void)setAllowedRepos:(nullable NSArray<NSString *> *)repos;
- (void)setBlockedActors:(nullable NSArray<NSString *> *)actors;
- (void)clearFilters;

- (BOOL)shouldForwardCollection:(NSString *)collection;
- (BOOL)shouldForwardRepo:(NSString *)repoDID;
- (BOOL)shouldForwardActor:(NSString *)actorDID;

- (BOOL)shouldForwardEventWithRepo:(NSString *)repoDID
                      andCollection:(nullable NSString *)collection
                         andActor:(nullable NSString *)actorDID;

@end

NS_ASSUME_NONNULL_END