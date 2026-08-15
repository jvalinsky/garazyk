// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczOriginAnnouncer.h"
#import "Video/GZJelczStreamplaceOriginHints.h"

// VideoService already uses these NSID strings in HTTP paths (cf. VideoRemoteBlobUploader).
static NSString * const kGZJelczCreateSession = @"com.atproto.server.createSession";
static NSString * const kGZJelczPutRecord = @"com.atproto.repo.putRecord";
static NSString * const kGZJelczDeleteRecord = @"com.atproto.repo.deleteRecord";

NSErrorDomain const GZJelczOriginAnnouncerErrorDomain = @"GZJelczOriginAnnouncerErrorDomain";

@interface GZJelczOriginAnnouncer ()
@property (nonatomic, strong, readwrite) id<ATProtoCAMirrorHTTPClient> httpClient;
@property (nonatomic, copy, nullable) NSString *accessJwt;
@property (nonatomic, copy, nullable) NSString *sessionDID;
@end

@implementation GZJelczOriginAnnouncer

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                        pdsBaseURL:(NSString *)pdsBaseURL
                        identifier:(NSString *)identifier
                       appPassword:(NSString *)appPassword
                         serverDID:(NSString *)serverDID {
    NSParameterAssert(httpClient);
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _pdsBaseURL = [[GZJelczStreamplaceOriginHints normalizedProviderBaseURL:pdsBaseURL] copy]
            ?: [pdsBaseURL copy];
        _identifier = [identifier copy];
        _appPassword = [appPassword copy];
        _serverDID = [serverDID copy];
        _timeout = 30.0;
    }
    return self;
}

+ (NSString *)iso8601Now:(NSDate *)now {
    static NSISO8601DateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [fmt stringFromDate:now] ?: @"";
}

+ (NSDictionary *)originRecordWithSubjectURI:(NSString *)subjectURI
                                  subjectCID:(NSString *)subjectCID
                                   serverDID:(NSString *)serverDID
                                watchBaseURL:(NSString *)watchBaseURL
                                 manifestCID:(NSString *)manifestCID
                                   httpsBase:(NSString *)httpsBase
                               irohEndpointId:(NSString *)irohEndpointId
                           irohEndpointTicket:(NSString *)irohEndpointTicket
                                         now:(NSDate *)now {
    NSString *when = [self iso8601Now:now ?: [NSDate date]];
    NSMutableDictionary *rec = [@{
        @"$type": @"tools.garazyk.video.origin",
        @"subject": @{
            @"uri": subjectURI ?: @"",
            @"cid": subjectCID ?: @"",
        },
        @"server": serverDID ?: @"",
        @"watchBaseUrl": watchBaseURL ?: @"",
        @"manifestCid": manifestCID ?: @"",
        @"createdAt": when,
        @"lastSeenAt": when,
    } mutableCopy];
    if (httpsBase.length > 0) {
        rec[@"httpsBase"] = httpsBase;
    }
    if (irohEndpointId.length > 0) {
        rec[@"irohEndpointId"] = irohEndpointId;
    }
    if (irohEndpointTicket.length > 0) {
        rec[@"irohEndpointTicket"] = irohEndpointTicket;
    }
    return [rec copy];
}

+ (NSString *)newTIDRkey {
    // Compact sortable-ish id for labs (not a full ATProto TID encoder).
    uint64_t ms = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    uint32_t rnd = arc4random_uniform(0xffffff);
    return [NSString stringWithFormat:@"%llux%06x", (unsigned long long)ms, rnd];
}

- (NSError *)errorWithCode:(GZJelczOriginAnnouncerErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:GZJelczOriginAnnouncerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

- (nullable NSData *)postJSON:(NSDictionary *)body
                         path:(NSString *)path
                  bearerToken:(nullable NSString *)token
                     response:(NSHTTPURLResponse **)outResponse
                        error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/xrpc/%@", self.pdsBaseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) *error = [self errorWithCode:GZJelczOriginAnnouncerErrorInvalidArgument message:@"bad PDS URL"];
        return nil;
    }
    NSError *jsonErr = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (!payload) {
        if (error) *error = jsonErr;
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = payload;
    req.timeoutInterval = self.timeout;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    return [self.httpClient sendSynchronousRequest:req options:nil response:outResponse error:error];
}

- (BOOL)ensureSession:(NSError **)error {
    if (self.accessJwt.length > 0 && self.sessionDID.length > 0) {
        return YES;
    }
    if (self.identifier.length == 0 || self.appPassword.length == 0) {
        if (error) {
            *error = [self errorWithCode:GZJelczOriginAnnouncerErrorInvalidArgument
                                 message:@"identifier and appPassword required"];
        }
        return NO;
    }
    NSHTTPURLResponse *resp = nil;
    NSError *reqErr = nil;
    NSData *data = [self postJSON:@{
        @"identifier": self.identifier,
        @"password": self.appPassword,
    }
                             path:kGZJelczCreateSession
                      bearerToken:nil
                         response:&resp
                            error:&reqErr];
    if (!data || resp.statusCode != 200) {
        if (error) {
            *error = reqErr ?: [self errorWithCode:GZJelczOriginAnnouncerErrorSessionFailed
                                           message:@"createSession failed"];
        }
        return NO;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [self errorWithCode:GZJelczOriginAnnouncerErrorSessionFailed message:@"bad session JSON"];
        }
        return NO;
    }
    NSDictionary *dict = (NSDictionary *)json;
    NSString *jwt = dict[@"accessJwt"];
    NSString *did = dict[@"did"];
    if (jwt.length == 0 || did.length == 0) {
        if (error) {
            *error = [self errorWithCode:GZJelczOriginAnnouncerErrorSessionFailed message:@"session missing jwt/did"];
        }
        return NO;
    }
    self.accessJwt = jwt;
    self.sessionDID = did;
    return YES;
}

- (NSDictionary *)publishOriginRecord:(NSDictionary *)record
                                 rkey:(NSString *)rkey
                                error:(NSError **)error {
    if (![self ensureSession:error]) {
        return nil;
    }
    if (self.serverDID.length == 0) {
        if (error) {
            *error = [self errorWithCode:GZJelczOriginAnnouncerErrorInvalidArgument message:@"serverDID required"];
        }
        return nil;
    }
    NSString *key = rkey.length > 0 ? rkey : [[self class] newTIDRkey];
    NSMutableDictionary *body = [@{
        @"repo": self.sessionDID,
        @"collection": @"tools.garazyk.video.origin",
        @"rkey": key,
        @"record": record ?: @{},
    } mutableCopy];
    NSHTTPURLResponse *resp = nil;
    NSError *reqErr = nil;
    NSData *data = [self postJSON:body
                             path:kGZJelczPutRecord
                      bearerToken:self.accessJwt
                         response:&resp
                            error:&reqErr];
    if (!data || (resp.statusCode != 200 && resp.statusCode != 201)) {
        if (error) {
            *error = reqErr ?: [self errorWithCode:GZJelczOriginAnnouncerErrorPutFailed
                                           message:@"putRecord failed"];
        }
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *uri = [json isKindOfClass:[NSDictionary class]] ? json[@"uri"] : nil;
    NSString *cid = [json isKindOfClass:[NSDictionary class]] ? json[@"cid"] : nil;
    return @{
        @"uri": uri ?: [NSString stringWithFormat:@"at://%@/tools.garazyk.video.origin/%@", self.sessionDID, key],
        @"cid": cid ?: [NSNull null],
        @"rkey": key,
        @"repo": self.sessionDID,
    };
}

- (BOOL)retractOriginWithRkey:(NSString *)rkey error:(NSError **)error {
    if (rkey.length == 0) {
        if (error) {
            *error = [self errorWithCode:GZJelczOriginAnnouncerErrorInvalidArgument message:@"rkey required"];
        }
        return NO;
    }
    if (![self ensureSession:error]) {
        return NO;
    }
    NSHTTPURLResponse *resp = nil;
    NSError *reqErr = nil;
    NSData *data = [self postJSON:@{
        @"repo": self.sessionDID,
        @"collection": @"tools.garazyk.video.origin",
        @"rkey": rkey,
    }
                             path:kGZJelczDeleteRecord
                      bearerToken:self.accessJwt
                         response:&resp
                            error:&reqErr];
    (void)data;
    if (resp.statusCode != 200 && resp.statusCode != 204) {
        if (error) {
            *error = reqErr ?: [self errorWithCode:GZJelczOriginAnnouncerErrorDeleteFailed
                                           message:@"deleteRecord failed"];
        }
        return NO;
    }
    return YES;
}

@end
