// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLURL.h

 @abstract Parser for `rasl://` URLs (https://dasl.ing/rasl.html).

 @discussion RASL ("Retrievable As Self-describing Location") turns a bare CID
 into a URL: `rasl://<cid>/?hint=<host>&hint=<host2>`. The authority is a DASL
 CID string (not a domain); the path is empty or `/` and carries no meaning;
 zero or more repeated `hint` query parameters name HTTPS hosts a client may
 try when resolving the CID to bytes. This file only parses the URL — it does
 not fetch anything and does not perform SSRF validation; that belongs to
 `ATProtoRASLClient` (Transport) at actual-fetch time, reusing the existing
 pinned-egress `ATProtoSafeHTTPClient` (ADR 0016) rather than duplicating it.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class CID;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ATProtoRASLURLErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoRASLURLErrorCode) {
    /** The string is not a `rasl://` URL at all (wrong or missing scheme). */
    ATProtoRASLURLErrorInvalidScheme = 1,
    /** The authority component is empty. */
    ATProtoRASLURLErrorMissingCID = 2,
    /** The authority component is not a valid DASL CID. */
    ATProtoRASLURLErrorInvalidCID = 3,
};

/**
 * @abstract A parsed `rasl://` URL: a CID plus zero or more retrieval hints.
 */
@interface ATProtoRASLURL : NSObject

/** The CID being located. Always DASL-conformant (base or Big DASL profile). */
@property (nonatomic, strong, readonly) CID *cid;

/**
 Syntactically valid HTTPS hint hosts, in the order they appeared in the URL,
 with duplicates removed. May be empty. Per spec, individual `hint` values
 that are not valid HTTPS host syntax are dropped rather than causing parse
 failure — only the CID (authority) is load-bearing for a valid URL.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *hints;

/**
 Parses a `rasl://` URL string.

 @param string The URL, e.g. `rasl://bafybei.../?hint=example.com`.
 @param error On failure, describes why (bad scheme, missing/invalid CID).
 @return A parsed URL, or nil on failure.
 */
+ (nullable instancetype)raslURLFromString:(NSString *)string error:(NSError **)error;

/**
 The `.well-known` retrieval path for this URL's CID: `/.well-known/rasl/<cid>`.
 Does not include a host — combine with a hint to form a fetchable URL.
 */
- (NSString *)wellKnownPath;

@end

/**
 The `.well-known` retrieval path for an arbitrary CID, independent of any
 parsed `ATProtoRASLURL`. Used by both the client (building fetch URLs from
 hints) and the server (registering the route).
 */
FOUNDATION_EXPORT NSString *ATProtoRASLWellKnownPathForCID(CID *cid);

NS_ASSUME_NONNULL_END
