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

/**
 * @abstract Applies allow and deny lists to relay events before forwarding.
 */
@interface RelayEventFilter : NSObject

/** Collection NSIDs that may be forwarded, or nil to allow all collections. */
@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *allowedCollections;
/** Repository DIDs that may be forwarded, or nil to allow all repositories. */
@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *allowedRepos;
/** Actor DIDs that must not be forwarded. */
@property (nonatomic, strong, readonly, nullable) NSSet<NSString *> *blockedActors;

/**
 * @abstract Initializes a relay filter with optional allow and deny lists.
 */
- (instancetype)initWithAllowedCollections:(nullable NSArray<NSString *> *)collections
                          allowedRepos:(nullable NSArray<NSString *> *)repos
                          blockedActors:(nullable NSArray<NSString *> *)actors NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/** Replaces the collection allow list. Passing nil allows every collection. */
- (void)setAllowedCollections:(nullable NSArray<NSString *> *)collections;
/** Replaces the repository allow list. Passing nil allows every repository. */
- (void)setAllowedRepos:(nullable NSArray<NSString *> *)repos;
/** Replaces the actor deny list. Passing nil blocks no actors. */
- (void)setBlockedActors:(nullable NSArray<NSString *> *)actors;
/** Clears all filters so every valid event may be forwarded. */
- (void)clearFilters;

/** Returns whether events for the collection pass the configured allow list. */
- (BOOL)shouldForwardCollection:(NSString *)collection;
/** Returns whether events for the repository pass the configured allow list. */
- (BOOL)shouldForwardRepo:(NSString *)repoDID;
/** Returns whether events from the actor are not blocked. */
- (BOOL)shouldForwardActor:(NSString *)actorDID;

/**
 * @abstract Evaluates all configured filters for one relay event.
 * @param repoDID Repository DID associated with the event.
 * @param collection Optional collection NSID associated with the event.
 * @param actorDID Optional actor DID associated with the event.
 * @return YES when the event should be forwarded downstream.
 */
- (BOOL)shouldForwardEventWithRepo:(NSString *)repoDID
                      andCollection:(nullable NSString *)collection
                         andActor:(nullable NSString *)actorDID;

@end

NS_ASSUME_NONNULL_END
