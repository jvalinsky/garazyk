// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyGraphHelpers.h
//  ATProtoPDS
//
//  Helper functions for app.bsky.graph.* XRPC endpoint implementations.
//  Shared between XrpcAppBskyMethods and XrpcAppBskyGraphPack.
//

#import <Foundation/Foundation.h>

@class ActorService;
@class PDSDatabase;
@class PDSDatabasePool;
@class PDSServiceDatabases;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - URI Parsing

/// Parses an AT URI into components. Returns NO if invalid.
BOOL XrpcParseAtURI(NSString *uri, NSString *_Nullable *_Nullable outDid, NSString *_Nullable *_Nullable outCollection, NSString *_Nullable *_Nullable outRkey);

#pragma mark - Limit Parsing

/// Parses and validates a limit parameter. Returns YES if valid (or empty/default).
BOOL XrpcParseLimit(NSString *limitParam, NSInteger *outValue, NSInteger min, NSInteger max, HttpResponse *response);

#pragma mark - Preference Helpers

/// Preference type constant for graph mute state
extern NSString *const kXrpcGraphMuteStatePreferenceType;

/// Extracts mutable preference entries array from preferences envelope.
NSMutableArray<NSDictionary *> *XrpcMutablePreferenceEntries(NSDictionary *preferencesEnvelope);

/// Normalizes an array to unique, non-empty strings only.
NSMutableArray<NSString *> *XrpcNormalizedUniqueStringArray(id rawValue);

/// Extracts graph mute state from preferences array.
NSMutableDictionary *XrpcGraphMuteStateFromPreferences(NSArray<NSDictionary *> *preferences, NSUInteger *_Nullable outIndex);

/// Persists graph mute state back to preferences.
BOOL XrpcPersistGraphMuteState(ActorService *actorService, NSString *actorDID, NSMutableArray<NSDictionary *> *preferences, NSMutableDictionary *state, NSUInteger existingIndex, NSError **error);

/// Normalizes a list purpose string to full Lexicon URI.
NSString *_Nullable XrpcNormalizeListPurpose(NSString *purpose);

#pragma mark - Actor Resolution

/// Resolves an actor identifier (handle or DID) to DID.
NSString *_Nullable XrpcResolveActorIdentifierToDid(PDSServiceDatabases *serviceDatabases, NSString *actorIdentifier);

#pragma mark - List View Helpers

/// Loads a list item view for a specific list and subject.
NSDictionary *_Nullable XrpcLoadListItemViewForListAndSubject(PDSDatabase *appViewDatabase, ActorService *actorService, NSString *creatorDid, NSString *listURI, NSString *subjectDid);

/// Loads a list view from URI.
NSDictionary *_Nullable XrpcLoadListViewForURI(PDSDatabase *appViewDatabase, ActorService *actorService, NSString *listURI);

NS_ASSUME_NONNULL_END
