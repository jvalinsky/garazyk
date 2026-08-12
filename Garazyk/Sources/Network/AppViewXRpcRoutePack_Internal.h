// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@class ATProtoHttpRequest;
@class ATProtoHttpResponse;

@class PDSFeedService;
@class PDSActorService;
@class PDSGraphService;
@class PDSNotificationService;
@class PDSAgeAssuranceService;
@class PDSDraftService;
@class PDSBookmarkService;
@class PDSContactService;
@class PDSSearchIndexService;
@class GZAppViewWriteProxy;
/** @abstract Query interface used by AppView routes that need PDS-backed reads. */
@protocol PDSQueryDatabase;
@class ATProtoJWTMinter;

/**
 * @abstract Internal dependencies and authentication helpers for AppView XRPC handlers.
 * @discussion Handlers write the complete HTTP response synchronously. `requireAuth:response:`
 * returns the authenticated DID or writes the authentication failure response; callers must
 * return immediately when it returns nil. Service dependencies are installed at initialization
 * and are read-only for the route pack's lifetime.
 */
@interface ATProtoAppViewXRpcRoutePack ()

/** @abstract Service that resolves feeds and threads. */
@property (nonatomic, strong, readonly) PDSFeedService *feedService;
/** @abstract Service that resolves profiles, searches, and actor preferences. */
@property (nonatomic, strong, readonly) PDSActorService *actorService;
/** @abstract Optional service for graph, relationship, and list operations. */
@property (nonatomic, strong, readonly) PDSGraphService *graphService;
/** @abstract Service that reads and mutates notification state. */
@property (nonatomic, strong, readonly) PDSNotificationService *notificationService;
/** @abstract Optional service for age-assurance operations. */
@property (nonatomic, strong, readonly) PDSAgeAssuranceService *ageAssuranceService;
/** @abstract Optional service for draft operations. */
@property (nonatomic, strong, readonly) PDSDraftService *draftService;
/** @abstract Optional service for bookmark operations. */
@property (nonatomic, strong, readonly) PDSBookmarkService *bookmarkService;
/** @abstract Optional service for phone verification and contact matching. */
@property (nonatomic, strong, readonly) PDSContactService *contactService;
/** @abstract Optional service for indexed actor and post search. */
@property (nonatomic, strong, readonly) PDSSearchIndexService *searchIndexService;
/** @abstract Optional write proxy for delegated repository writes. */
@property (nonatomic, strong, readonly) GZAppViewWriteProxy *writeProxy;
/** @abstract Optional PDS query database used by selected routes. */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;
/** @abstract Optional ATProtoJWT issuer used by authenticated AppView extensions. */
@property (nonatomic, strong, readonly) ATProtoJWTMinter *jwtMinter;

/** @abstract Authenticates the request and returns its actor DID, or writes an auth error and returns nil. */
- (NSString *)requireAuth:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Extracts and verifies the DID represented by an Authorization header for this request. */
- (NSString *)extractDIDFromAuth:(NSString *)authHeader request:(ATProtoHttpRequest *)request;

@end

/** @abstract Parses `limit`, defaulting it when absent and clamping it to the inclusive range 1...maxLimit. */
NSInteger parseLimitParam(ATProtoHttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit);
