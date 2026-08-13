// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczOriginAnnouncer.h

 @abstract WS16 Phase 3: publish tools.garazyk.video.origin via remote PDS write (ADR 0038).
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GZJelczOriginAnnouncerErrorDomain;

typedef NS_ENUM(NSInteger, GZJelczOriginAnnouncerErrorCode) {
    GZJelczOriginAnnouncerErrorInvalidArgument = 1,
    GZJelczOriginAnnouncerErrorSessionFailed = 2,
    GZJelczOriginAnnouncerErrorPutFailed = 3,
    GZJelczOriginAnnouncerErrorDeleteFailed = 4,
};

@interface GZJelczOriginAnnouncer : NSObject

@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
@property (nonatomic, copy) NSString *pdsBaseURL;
@property (nonatomic, copy) NSString *identifier; // handle or DID
@property (nonatomic, copy) NSString *appPassword;
@property (nonatomic, copy) NSString *serverDID;
@property (nonatomic, copy, nullable) NSString *httpsBase;
@property (nonatomic, copy, nullable) NSString *irohTicket;
@property (nonatomic, assign) NSTimeInterval timeout;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                        pdsBaseURL:(NSString *)pdsBaseURL
                        identifier:(NSString *)identifier
                       appPassword:(NSString *)appPassword
                         serverDID:(NSString *)serverDID
    NS_DESIGNATED_INITIALIZER;

/** Build a tools.garazyk.video.origin record dictionary (not published). */
+ (NSDictionary *)originRecordWithSubjectURI:(NSString *)subjectURI
                                  subjectCID:(NSString *)subjectCID
                                   serverDID:(NSString *)serverDID
                                watchBaseURL:(NSString *)watchBaseURL
                                 manifestCID:(NSString *)manifestCID
                                   httpsBase:(nullable NSString *)httpsBase
                                  irohTicket:(nullable NSString *)irohTicket
                                        now:(NSDate *)now;

/**
 createSession + putRecord. Returns @{ @"uri", @"cid", @"rkey" } on success.
 Uses collection tools.garazyk.video.origin and a TID-like rkey when @c rkey is nil.
 */
- (nullable NSDictionary *)publishOriginRecord:(NSDictionary *)record
                                          rkey:(nullable NSString *)rkey
                                         error:(NSError * _Nullable * _Nullable)error;

/** deleteRecord for a previously published rkey. */
- (BOOL)retractOriginWithRkey:(NSString *)rkey error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
