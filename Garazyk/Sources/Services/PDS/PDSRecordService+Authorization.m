// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+Authorization.h"
#import "PDSRecordService+Validation.h"
#import "Database/PDSDatabase.h"
#import "Core/Repositories/PDSRecordRepository.h"

@implementation PDSRecordService (Authorization)

#pragma mark - Authorization

- (BOOL)checkAuthorizationForDid:(NSString *)targetDid actorDid:(NSString *)actorDid error:(NSError **)error {
    if (!actorDid || !targetDid) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                          code:PDSRecordServiceErrorUnauthorized
                                      userInfo:@{NSLocalizedDescriptionKey: @"Authorization required: missing actor or target DID"}];
        }
        return NO;
    }
    
    if (![actorDid isEqualToString:targetDid]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                          code:PDSRecordServiceErrorUnauthorized
                                      userInfo:@{NSLocalizedDescriptionKey: @"Cannot modify another user's repository"}];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - Threadgate Validation

- (nullable NSDictionary *)threadgateRecordForPostURI:(NSString *)postURI
                                            authorDID:(NSString *)authorDID
                                                error:(NSError **)error {
    NSArray<PDSDatabaseRecord *> *threadgates =
        [self.recordRepository recordsForDid:authorDID
                                  collection:@"app.bsky.feed.threadgate"
                                       error:error];
    for (PDSDatabaseRecord *threadgate in threadgates) {
        NSDictionary *value = PDSRecordServiceJSONObjectFromRecordValue(threadgate.value);
        if ([value[@"post"] isEqualToString:postURI]) {
            return value;
        }
    }
    return nil;
}

- (BOOL)authorDID:(NSString *)authorDID hasFollowForDID:(NSString *)targetDID error:(NSError **)error {
    NSArray<PDSDatabaseRecord *> *follows =
        [self.recordRepository recordsForDid:authorDID
                                  collection:@"app.bsky.graph.follow"
                                       error:error];
    for (PDSDatabaseRecord *follow in follows) {
        NSDictionary *value = PDSRecordServiceJSONObjectFromRecordValue(follow.value);
        id subject = value[@"subject"];
        if ([subject isKindOfClass:[NSString class]] && [subject isEqualToString:targetDID]) {
            return YES;
        }
        if ([subject isKindOfClass:[NSDictionary class]] && [subject[@"did"] isEqualToString:targetDID]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)validateThreadgateForReplyRecord:(NSDictionary *)record
                              collection:(NSString *)collection
                               authorDID:(NSString *)authorDID
                                   error:(NSError **)error {
    if (![collection isEqualToString:@"app.bsky.feed.post"]) {
        return YES;
    }

    NSDictionary *reply = record[@"reply"];
    if (![reply isKindOfClass:[NSDictionary class]]) {
        return YES;
    }
    NSDictionary *parent = reply[@"parent"];
    NSString *parentURI = [parent isKindOfClass:[NSDictionary class]] ? parent[@"uri"] : nil;
    NSString *rootAuthorDID = PDSRecordServiceDIDFromATURI(parentURI);
    if (!rootAuthorDID) {
        return YES;
    }

    NSDictionary *threadgate = [self threadgateRecordForPostURI:parentURI
                                                      authorDID:rootAuthorDID
                                                          error:error];
    if (!threadgate) {
        return YES;
    }

    NSArray *allow = threadgate[@"allow"];
    if (![allow isKindOfClass:[NSArray class]] || allow.count == 0) {
        if (error) *error = PDSRecordServiceReplyNotAllowedError();
        return NO;
    }

    for (NSDictionary *rule in allow) {
        if (![rule isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = rule[@"$type"];
        if ([type isEqualToString:@"app.bsky.feed.threadgate#followerRule"]) {
            if ([self authorDID:authorDID hasFollowForDID:rootAuthorDID error:nil]) {
                return YES;
            }
        } else if ([type isEqualToString:@"app.bsky.feed.threadgate#mentionRule"]) {
            PDSDatabaseRecord *parentRecord = [self.recordRepository recordForUri:parentURI error:nil];
            NSDictionary *parentValue = PDSRecordServiceJSONObjectFromRecordValue(parentRecord.value);
            if (PDSRecordServiceRecordMentionsDID(parentValue, authorDID)) {
                return YES;
            }
        }
    }

    if (error) *error = PDSRecordServiceReplyNotAllowedError();
    return NO;
}

@end
