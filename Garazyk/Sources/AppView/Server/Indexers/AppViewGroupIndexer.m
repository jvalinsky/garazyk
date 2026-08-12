// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewGroupIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewGroupIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Debug/GZLogger.h"

static NSString * const kCollectionGroupDef = @"chat.bsky.group.definition";

@interface GZAppViewGroupIndexer ()
@property (nonatomic, strong) GZAppViewDatabase *avdb;
@end

@implementation GZAppViewGroupIndexer

- (instancetype)initWithDatabase:(GZAppViewDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _avdb = database;
    return self;
}

#pragma mark - AppViewIndexer

- (BOOL)canIndexCollection:(NSString *)collection {
    return [collection isEqualToString:kCollectionGroupDef];
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    NSDictionary *groupRecord = record[@"record"] ?: record;

    NSString *name = groupRecord[@"name"];
    NSString *description = groupRecord[@"description"];
    // groups.uri is the primary key, so an empty rkey would leave the URI's last
    // segment empty and collapse every such group for a DID onto one row.
    NSString *effectiveRkey = rkey.length > 0 ? rkey : @"main";

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, effectiveRkey];
    NSString *createdAt = groupRecord[@"createdAt"] ?: groupRecord[@"indexedAt"] ?: @"";
    NSString *updatedAt = groupRecord[@"updatedAt"] ?: @"";

    NSMutableArray *args = [NSMutableArray arrayWithCapacity:10];
    [args addObject:uri];
    [args addObject:did];
    [args addObject:name ?: @""];
    [args addObject:description ?: @""];
    [args addObject:createdAt];
    [args addObject:updatedAt];
    [args addObject:cid ?: @""];

    NSString *query = @"INSERT OR REPLACE INTO groups (uri, did, name, description, created_at, updated_at, cid) VALUES (?, ?, ?, ?, ?, ?, ?)";
    BOOL ok = [self.avdb executeParameterizedUpdate:query params:args error:error];

    if (!ok) {
        GZ_LOG_WARN(@"[AppViewGroupIndexer] Failed to index group for %@: %@",
                     did, error && *error ? (*error).localizedDescription : @"unknown");
        return NO;
    }

    NSArray *members = groupRecord[@"members"];
    if ([members isKindOfClass:[NSArray class]]) {
        for (NSDictionary *member in members) {
            NSString *memberDid = member[@"did"];
            if (memberDid.length > 0) {
                NSString *memberQuery = @"INSERT OR IGNORE INTO group_members (group_uri, did, added_at) VALUES (?, ?, ?)";
                NSMutableArray *memberArgs = [NSMutableArray arrayWithCapacity:3];
                [memberArgs addObject:uri];
                [memberArgs addObject:memberDid];
                [memberArgs addObject:[NSDate date]];
                [self.avdb executeParameterizedUpdate:memberQuery params:memberArgs error:nil];
            }
        }
    }

    NSArray *roles = groupRecord[@"roles"];
    if ([roles isKindOfClass:[NSArray class]]) {
        for (NSDictionary *role in roles) {
            NSString *roleDid = role[@"did"];
            NSString *roleName = role[@"role"] ?: @"member";
            if (roleDid.length > 0) {
                NSString *roleQuery = @"INSERT OR REPLACE INTO group_members (group_uri, did, role, added_at) VALUES (?, ?, ?, ?)";
                NSMutableArray *roleArgs = [NSMutableArray arrayWithCapacity:4];
                [roleArgs addObject:uri];
                [roleArgs addObject:roleDid];
                [roleArgs addObject:roleName];
                [roleArgs addObject:[NSDate date]];
                [self.avdb executeParameterizedUpdate:roleQuery params:roleArgs error:nil];
            }
        }
    }

    GZ_LOG_DEBUG(@"[AppViewGroupIndexer] Indexed group for %@: %@", did, uri);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey
                  did:(NSString *)did
           collection:(NSString *)collection
               error:(NSError **)error {
    // Mirrors the fallback in indexRecord: so delete addresses the indexed row.
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@",
                     did, collection, rkey.length > 0 ? rkey : @"main"];

    NSString *deleteMembersQuery = @"DELETE FROM group_members WHERE group_uri = ?";
    [self.avdb executeParameterizedUpdate:deleteMembersQuery params:@[uri] error:nil];

    NSString *deleteGroupQuery = @"DELETE FROM groups WHERE uri = ?";
    BOOL ok = [self.avdb executeParameterizedUpdate:deleteGroupQuery params:@[uri] error:error];

    if (!ok) {
        GZ_LOG_WARN(@"[AppViewGroupIndexer] Failed to delete group for %@: %@",
                     did, error && *error ? (*error).localizedDescription : @"unknown");
    }
    return ok;
}

@end