// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRASLResolver.h

 @abstract Resolves a ATProtoCID to bytes for the RASL `.well-known` route.

 @discussion Garazyk repository blocks and blobs are stored per-actor (one
 SQLite shard per DID — `PDSActorStore`; blob metadata + on-disk bytes are
 also DID-scoped through `PDSBlobService`). RASL's well-known endpoint
 (`GET /.well-known/rasl/{cid}`) is host-wide and carries no DID, so there is
 no direct index from a bare ATProtoCID to the store that holds it.

 This resolver's interim strategy is a bounded scan: try each locally known
 account DID's block store, then its blob store, until one has the ATProtoCID or the
 scan is exhausted. This is O(active accounts) per request, not O(1) — a
 defensible bound for the single/small-tenant PDS deployments this codebase
 targets, but the wrong shape for a large multi-tenant host. Building a
 dedicated ATProtoCID → DID index (maintained on every block/blob write) would make
 this O(1) and is out of scope for this phase; flagged as workstream 10 Phase
 5 follow-up rather than built speculatively here.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;
@class PDSDatabasePool;
@class PDSBlobService;
@protocol PDSAccountService;

NS_ASSUME_NONNULL_BEGIN

@interface PDSRASLResolver : NSObject

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool
                          blobService:(PDSBlobService *)blobService
                        accountService:(id<PDSAccountService>)accountService NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 Scans locally known accounts for a block or blob matching `cid`.

 @param cid The ATProtoCID to resolve. Only its raw bytes are used for lookup; the
 resolver does not re-verify the returned bytes hash to this ATProtoCID — callers
 serving this over HTTP should not skip that check just because storage is
 trusted, since a bug in either store's write path would otherwise silently
 mislabel content. (The route handler that wraps this class does re-verify;
 see `ATProtoHttpWellKnownRoutePack`.)
 @param maxAccountsToScan Upper bound on the scan, so a host with many
 accounts fails a miss quickly instead of scanning unboundedly.
 @return The stored bytes, or nil if no local account has this ATProtoCID.
 */
- (nullable NSData *)dataForCID:(ATProtoCID *)cid maxAccountsToScan:(NSUInteger)maxAccountsToScan;

@end

NS_ASSUME_NONNULL_END
