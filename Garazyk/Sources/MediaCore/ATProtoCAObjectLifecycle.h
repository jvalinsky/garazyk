// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAObjectLifecycle.h

 @abstract Manifest-keyed refcounting and grace-period reclaim for CA objects
 (ADR 0036 / WS12 Phase 6).

 @discussion Increments object refcounts at manifest publish and decrements at
 retract/supersede. Zero-refcount objects become reclaimable after a grace
 period matching ADR 0013's shape (default six hours, clamped to a one-hour
 minimum). Sweep is configuration-gated and defaults off so operators can leave
 objects in place (disk growth, not data loss).
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;
@class ATProtoCAObjectStore;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoCAObjectLifecycleErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoCAObjectLifecycleErrorCode) {
    ATProtoCAObjectLifecycleErrorInvalidArgument = 1,
    ATProtoCAObjectLifecycleErrorAlreadyPublished = 2,
    ATProtoCAObjectLifecycleErrorNotPublished = 3,
    ATProtoCAObjectLifecycleErrorIO = 4,
};

/**
 Tracks live manifests and reclaims orphaned CA objects after a grace period.
 */
@interface ATProtoCAObjectLifecycle : NSObject

/** Backing CA object store whose objects are deleted on sweep. */
@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;

/**
 Grace period before a zero-refcount object is eligible for delete.

 Default: 6 hours. Values below 1 hour are clamped to 1 hour (ADR 0013 shape).
 */
@property (nonatomic, assign) NSTimeInterval gracePeriodSeconds;

/**
 When NO (default), @c -sweepWithError: is a no-op that deletes nothing.
 */
@property (nonatomic, assign) BOOL sweepEnabled;

/**
 Optional clock for tests. Defaults to @c +[NSDate date].
 */
@property (nonatomic, copy, nullable) NSDate * _Nonnull (^nowProvider)(void);

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 Opens or creates @c lifecycle.db under the object store root.

 @param objectStore Store whose @c deleteCID: is used by sweep.
 @param error Receives open/migration failures.
 */
- (nullable instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                                       error:(NSError **)error NS_DESIGNATED_INITIALIZER;

/**
 Publishes a manifest and increments refcounts for each referenced object CID.

 The manifest CID itself is also tracked so retract can reclaim the DRISL blob.
 Re-publishing the same manifest CID fails with @c AlreadyPublished.
 */
- (BOOL)publishManifestCID:(ATProtoCID *)manifestCID
     referencedObjectCIDs:(NSArray<ATProtoCID *> *)objectCIDs
                    error:(NSError **)error;

/**
 Decrements refs for a previously published manifest.

 Objects that reach refcount 0 record @c zero_since for later sweep.
 */
- (BOOL)retractManifestCID:(ATProtoCID *)manifestCID error:(NSError **)error;

/** Current refcount for an object CID (0 if unknown). */
- (NSInteger)refcountForCID:(ATProtoCID *)cid error:(NSError **)error;

/**
 Deletes zero-refcount objects whose grace period has elapsed.

 Returns the number of objects deleted. When @c sweepEnabled is NO, returns 0
 without deleting.
 */
- (NSInteger)sweepWithError:(NSError **)error;

/** Clamps @c seconds to at least one hour. */
+ (NSTimeInterval)clampedGracePeriodSeconds:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
