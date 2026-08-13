// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAMediaDenylist.h

 @abstract Local moderation denylist for CA media serving (WS12 Phase 5).
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

/**
 Checks whether a CID (or optional record URI) is denied for byte serving.
 */
@protocol ATProtoCAMediaDenylist <NSObject>
- (BOOL)isDeniedCID:(ATProtoCID *)cid;
- (BOOL)isDeniedRecordURI:(nullable NSString *)recordURI;
@end

/** In-memory denylist suitable for tests and single-process jelcz. */
@interface ATProtoCAMediaDenylistMemory : NSObject <ATProtoCAMediaDenylist>

- (void)denyCID:(ATProtoCID *)cid;
- (void)allowCID:(ATProtoCID *)cid;
- (void)denyRecordURI:(NSString *)recordURI;
- (void)allowRecordURI:(NSString *)recordURI;

@end

NS_ASSUME_NONNULL_END
