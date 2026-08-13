// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczPeerProviderIndex.h

 @abstract WS16 Phase 2: parse origin records → ranked HTTPS provider bases.

 @discussion Control-plane only (no iroh). Operator env peers always apply.
 Origin records are auto-added only when the consent allowlist matches.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** One discovered peer / origin (HTTPS and optional future iroh ticket). */
@interface GZJelczPeerProviderEntry : NSObject
@property (nonatomic, copy, nullable) NSString *httpsBase;
@property (nonatomic, copy, nullable) NSString *serverDID;
@property (nonatomic, copy, nullable) NSString *streamerDID;
@property (nonatomic, copy, nullable) NSString *broadcasterDID;
@property (nonatomic, copy, nullable) NSString *irohTicket;
@property (nonatomic, copy, nullable) NSString *manifestCID;
@property (nonatomic, copy, nullable) NSDate *updatedAt;
@property (nonatomic, copy) NSString *source; // env | broadcast.origin | video.origin | media.origin
- (NSDictionary *)allowlistedDictionary;
@end

@interface GZJelczPeerProviderIndex : NSObject

/** Parse comma-separated DIDs; @"*" means allow-all. Empty → deny auto-ingest. */
+ (NSSet<NSString *> *)allowlistSetFromCSV:(nullable NSString *)csv;

+ (BOOL)isDID:(NSString *)did allowedBy:(NSSet<NSString *> *)allowlist;

/**
 Consent for auto-adding a record-derived entry.
 If both allowlists are empty, returns NO (env peers only).
 */
+ (BOOL)allowsStreamer:(nullable NSString *)streamer
           broadcaster:(nullable NSString *)broadcaster
      allowedStreamers:(NSSet<NSString *> *)allowedStreamers
   allowedBroadcasters:(NSSet<NSString *> *)allowedBroadcasters;

+ (nullable GZJelczPeerProviderEntry *)entryFromBroadcastOriginRecord:(NSDictionary *)record;

+ (nullable GZJelczPeerProviderEntry *)entryFromGarazykVideoOriginRecord:(NSDictionary *)record;

+ (nullable GZJelczPeerProviderEntry *)entryFromMediaOriginRecord:(NSDictionary *)record
                                              configuredBaseURL:(nullable NSString *)configuredBaseURL;

/** Newest @c updatedAt first; entries without dates sort last. */
+ (NSArray<GZJelczPeerProviderEntry *> *)rankEntries:(NSArray<GZJelczPeerProviderEntry *> *)entries;

/**
 Build deduped HTTPS bases: bootstrap first, then env peers, then consented
 ranked origin entries that have an httpsBase.
 */
+ (NSArray<NSString *> *)httpsProviderBasesWithBootstrap:(nullable NSString *)bootstrap
                                           envPeerBases:(nullable NSArray<NSString *> *)envPeerBases
                                          originEntries:(nullable NSArray<GZJelczPeerProviderEntry *> *)originEntries
                                       allowedStreamers:(NSSet<NSString *> *)allowedStreamers
                                    allowedBroadcasters:(NSSet<NSString *> *)allowedBroadcasters;

/**
 Parse a JSON array (or @{@"origins":[...]}) of mixed origin records into entries.
 Unknown shapes are skipped.
 */
+ (NSArray<GZJelczPeerProviderEntry *> *)entriesFromOriginsJSONObject:(id)json
                                                   configuredBaseURL:(nullable NSString *)configuredBaseURL;

+ (nullable NSArray<NSString *> *)parseCSVBases:(nullable NSString *)csv;

@end

NS_ASSUME_NONNULL_END
