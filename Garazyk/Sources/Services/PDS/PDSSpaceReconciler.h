// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class JWTMinter;
@class PDSDatabasePool;
@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Periodically reconciles non-authority space replicas with hosts.
 * @discussion Each pass replays stored writer heads through `notifyWrite`,
 * compares remote and local revisions, then applies incremental operations, record-index
 * recovery, or a signature-verified CAR import. Synchronous network work runs
 * on a private serial queue; public controls are cross-queue safe and callbacks
 * run on that queue.
 */
@interface PDSSpaceReconciler : NSObject

/**
 * @abstract Creates a stopped reconciler.
 * @param spaceStore The store that supplies heads and receives recovered state.
 * @param userDatabasePool The actor stores used to mint service-auth tokens.
 * @param jwtMinter The minter used for authority XRPC requests.
 * @param interval The requested interval; values below 60 seconds become 60.
 */
- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                   userDatabasePool:(PDSDatabasePool *)userDatabasePool
                         jwtMinter:(JWTMinter *)jwtMinter
                intervalInSeconds:(NSTimeInterval)interval;

/** @abstract Unavailable; use `initWithSpaceStore:userDatabasePool:jwtMinter:intervalInSeconds:`. */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Starts an immediate reconciliation pass and periodic passes.
 * @discussion Calling this method while running has no effect.
 */
- (void)start;

/**
 * @abstract Stops future timer-driven reconciliation passes.
 * @discussion This method synchronously waits for the private queue. Do not
 * call it from a `reconcileOnceForSpace:author:completion:` block.
 */
- (void)stop;

/**
 * @abstract Enqueues an immediate best-effort reconciliation pass.
 * @discussion The method returns before network or store work starts. It is a
 * no-op when the reconciler is stopped; per-repository failures are logged and
 * do not prevent subsequent heads from being considered.
 */
- (void)reconcileNow;

/**
 * @abstract Reconciles one stored replica and reports the recovery path.
 * @discussion This inbound-only diagnostic calls its completion asynchronously
 * on the private serial queue. `selector` is `incremental`, `lightweight`,
 * `fullCAR`, or `unavailable`; `requests` counts XRPC calls. It is only used by
 * the binary scenario fixture and is not registered by production routes.
 * @param space The stored space URI to reconcile.
 * @param author The replica author DID to reconcile.
 * @param completion Receives the diagnostic result on the private queue.
 */
- (void)reconcileOnceForSpace:(NSString *)space
                       author:(NSString *)author
                   completion:(void (^)(NSDictionary<NSString *, id> *result))completion;

@end

NS_ASSUME_NONNULL_END
