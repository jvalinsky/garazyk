// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*! @file PLCAdminSnapshot.h @abstract Bounded PLC admin read model. */

#import <Foundation/Foundation.h>

@protocol PLCStore;
@class ATProtoPLCSyncEngine;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Produces a bounded, immutable read model for the PLC admin UI.
 * @discussion This is the only PLC store seam exposed to the UI pack. It keeps
 * browser-facing code out of the store and never returns an unbounded log.
 */
@interface GZPLCAdminSnapshot : NSObject

@property(nonatomic, readonly, getter=isReplica) BOOL replica;

- (instancetype)initWithStore:(id<PLCStore>)store
                    syncEngine:(nullable ATProtoPLCSyncEngine *)syncEngine NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Returns a point-in-time overview using constant-size store count queries. */
- (NSDictionary<NSString *, id> *)snapshot;
/** Looks up one DID using count and latest-operation queries only. */
- (NSDictionary<NSString *, id> *)directoryEntryForDID:(NSString *)did;
/** Performs an explicitly requested replica action. Primary mode rejects it. */
- (BOOL)performReplicaAction:(NSString *)action error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
