/*!
 @file DraftService.m

 @abstract Draft storage service implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Services/DraftService.h"
#import "Core/TID.h"

@interface DraftService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@end

@implementation DraftService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)createDraftForDID:(NSString *)actorDID
                                     content:(NSDictionary *)content
                                       error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    NSString *draftID = [TID tid].stringValue;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    NSString *sql = @"INSERT INTO drafts (id, did, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:content options:0 error:&jsonError];
    if (jsonError || !jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize draft content"}];
        }
        return nil;
    }
    NSString *contentJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    BOOL success = [self.database executeParameterizedUpdate:sql
                                                      params:@[draftID, actorDID, contentJSON ?: @"{}", @((long long)now), @((long long)now)]
                                                       error:error];
    if (!success) return nil;

    return @{
        @"id": draftID,
        @"did": actorDID,
        @"content": content,
        @"createdAt": [NSString stringWithFormat:@"%.0f", now],
        @"updatedAt": [NSString stringWithFormat:@"%.0f", now]
    };
}

- (BOOL)updateDraftForDID:(NSString *)actorDID
                  draftID:(NSString *)draftID
                  content:(NSDictionary *)content
                    error:(NSError **)error {
    if (!actorDID || !draftID) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID or draft ID"}];
        }
        return NO;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:content options:0 error:&jsonError];
    if (jsonError || !jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize draft content"}];
        }
        return NO;
    }
    NSString *contentJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSString *sql = @"UPDATE drafts SET content = ?, updated_at = ? WHERE id = ? AND did = ?";
    return [self.database executeParameterizedUpdate:sql
                                              params:@[contentJSON ?: @"{}", @((long long)now), draftID, actorDID]
                                               error:error];
}

- (nullable NSArray<NSDictionary *> *)getDraftsForDID:(NSString *)actorDID
                                                error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    NSString *sql = @"SELECT id, did, content, created_at, updated_at FROM drafts WHERE did = ? ORDER BY updated_at DESC";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[actorDID] error:error];
    if (!rows) return nil;

    NSMutableArray *drafts = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *contentJSON = row[@"content"];
        NSDictionary *content = nil;
        if (contentJSON && contentJSON.length > 0) {
            NSData *data = [contentJSON dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                content = parsed;
            }
        }
        if (!content) content = @{};

        [drafts addObject:@{
            @"id": row[@"id"] ?: @"",
            @"did": row[@"did"] ?: actorDID,
            @"content": content,
            @"createdAt": [NSString stringWithFormat:@"%@", row[@"created_at"] ?: @"0"],
            @"updatedAt": [NSString stringWithFormat:@"%@", row[@"updated_at"] ?: @"0"]
        }];
    }

    return [drafts copy];
}

- (BOOL)deleteDraftForDID:(NSString *)actorDID
                  draftID:(NSString *)draftID
                    error:(NSError **)error {
    if (!actorDID || !draftID) {
        if (error) {
            *error = [NSError errorWithDomain:@"DraftService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID or draft ID"}];
        }
        return NO;
    }

    NSString *sql = @"DELETE FROM drafts WHERE id = ? AND did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[draftID, actorDID] error:error];
}

@end
