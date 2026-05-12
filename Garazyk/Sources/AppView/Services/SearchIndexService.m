// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "SearchIndexService.h"
#import "Database/PDSQueryDatabase.h"
#import "Debug/GZLogger.h"

NSString *const SearchIndexServiceErrorDomain = @"SearchIndexService";

@interface SearchIndexService ()
@property (nonatomic, strong, readwrite) id<PDSQueryDatabase> database;
@end

@implementation SearchIndexService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    if (self = [super init]) {
        _database = database;
    }
    return self;
}

#pragma mark - Query Sanitization

- (NSString *)sanitizeFTSQuery:(NSString *)query {
    if (!query || query.length == 0) return nil;

    // Split on whitespace, join with OR for broad matching, append * for prefix
    NSMutableArray *tokens = [NSMutableArray array];
    [query enumerateSubstringsInRange:NSMakeRange(0, query.length)
                               options:(NSStringEnumerationByWords | NSStringEnumerationLocalized)
                            usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        // Remove FTS5 special characters
        NSString *clean = [[substring componentsSeparatedByCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"\"'(){}[]^:~!@#$%&*+=|\\<>;,"]]
                           componentsJoinedByString:@""];
        if (clean.length > 0) {
            [tokens addObject:[NSString stringWithFormat:@"%@*", clean]];
        }
    }];

    if (tokens.count == 0) return nil;
    return [tokens componentsJoinedByString:@" OR "];
}

#pragma mark - Search

- (nullable NSDictionary *)searchActors:(NSString *)query
                                   limit:(NSInteger)limit
                                  cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    NSString *ftsQuery = [self sanitizeFTSQuery:query];
    if (!ftsQuery) {
        if (error) {
            *error = [NSError errorWithDomain:SearchIndexServiceErrorDomain
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid search query"}];
        }
        return nil;
    }

    limit = MIN(MAX(limit, 1), 100);
    NSInteger offset = cursor ? [cursor integerValue] : 0;

    // Get total hits
    NSString *countSQL = @"SELECT count(*) as cnt FROM fts_actors WHERE fts_actors MATCH ?";
    NSArray *countRows = [self.database executeParameterizedQuery:countSQL params:@[ftsQuery] error:nil];
    NSInteger hitsTotal = 0;
    if (countRows.count > 0) {
        hitsTotal = [countRows[0][@"cnt"] integerValue];
    }

    // Get results
    NSString *sql = @"SELECT did FROM fts_actors WHERE fts_actors MATCH ? ORDER BY bm25(fts_actors) LIMIT ? OFFSET ?";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[ftsQuery, @(limit + 1), @(offset)] error:error];
    if (!rows) return nil;

    BOOL hasMore = rows.count > limit;
    NSArray *resultRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, limit)] : rows;

    NSMutableArray *actors = [NSMutableArray array];
    for (NSDictionary *row in resultRows) {
        [actors addObject:@{@"did": row[@"did"] ?: @""}];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"actors"] = actors;
    result[@"hitsTotal"] = @(hitsTotal);
    if (hasMore) {
        result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + limit)];
    } else {
        result[@"cursor"] = [NSNull null];
    }

    return [result copy];
}

- (nullable NSDictionary *)searchPosts:(NSString *)query
                                  limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error {
    NSString *ftsQuery = [self sanitizeFTSQuery:query];
    if (!ftsQuery) {
        if (error) {
            *error = [NSError errorWithDomain:SearchIndexServiceErrorDomain
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid search query"}];
        }
        return nil;
    }

    limit = MIN(MAX(limit, 1), 100);
    NSInteger offset = cursor ? [cursor integerValue] : 0;

    NSString *countSQL = @"SELECT count(*) as cnt FROM fts_posts WHERE fts_posts MATCH ?";
    NSArray *countRows = [self.database executeParameterizedQuery:countSQL params:@[ftsQuery] error:nil];
    NSInteger hitsTotal = 0;
    if (countRows.count > 0) {
        hitsTotal = [countRows[0][@"cnt"] integerValue];
    }

    NSString *sql = @"SELECT uri FROM fts_posts WHERE fts_posts MATCH ? ORDER BY bm25(fts_posts) LIMIT ? OFFSET ?";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[ftsQuery, @(limit + 1), @(offset)] error:error];
    if (!rows) return nil;

    BOOL hasMore = rows.count > limit;
    NSArray *resultRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, limit)] : rows;

    NSMutableArray *posts = [NSMutableArray array];
    for (NSDictionary *row in resultRows) {
        [posts addObject:@{@"uri": row[@"uri"] ?: @""}];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"posts"] = posts;
    result[@"hitsTotal"] = @(hitsTotal);
    if (hasMore) {
        result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + limit)];
    } else {
        result[@"cursor"] = [NSNull null];
    }

    return [result copy];
}

- (nullable NSDictionary *)searchStarterPacks:(NSString *)query
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error {
    NSString *ftsQuery = [self sanitizeFTSQuery:query];
    if (!ftsQuery) {
        if (error) {
            *error = [NSError errorWithDomain:SearchIndexServiceErrorDomain
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid search query"}];
        }
        return nil;
    }

    limit = MIN(MAX(limit, 1), 100);
    NSInteger offset = cursor ? [cursor integerValue] : 0;

    NSString *countSQL = @"SELECT count(*) as cnt FROM fts_starter_packs WHERE fts_starter_packs MATCH ?";
    NSArray *countRows = [self.database executeParameterizedQuery:countSQL params:@[ftsQuery] error:nil];
    NSInteger hitsTotal = 0;
    if (countRows.count > 0) {
        hitsTotal = [countRows[0][@"cnt"] integerValue];
    }

    NSString *sql = @"SELECT uri FROM fts_starter_packs WHERE fts_starter_packs MATCH ? ORDER BY bm25(fts_starter_packs) LIMIT ? OFFSET ?";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[ftsQuery, @(limit + 1), @(offset)] error:error];
    if (!rows) return nil;

    BOOL hasMore = rows.count > limit;
    NSArray *resultRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, limit)] : rows;

    NSMutableArray *starterPacks = [NSMutableArray array];
    for (NSDictionary *row in resultRows) {
        [starterPacks addObject:@{@"uri": row[@"uri"] ?: @""}];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"starterPacks"] = starterPacks;
    result[@"hitsTotal"] = @(hitsTotal);
    if (hasMore) {
        result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + limit)];
    } else {
        result[@"cursor"] = [NSNull null];
    }

    return [result copy];
}

#pragma mark - AppViewIndexHook

- (NSString *)hookIdentifier {
    return @"search-index-internal";
}

- (nullable NSArray<NSString *> *)collections {
    return @[@"app.bsky.actor.profile", @"app.bsky.feed.post", @"app.bsky.graph.starterpack"];
}

- (void)didIndexRecord:(NSDictionary *)record
                   uri:(NSString *)uri
                    did:(NSString *)did
            collection:(NSString *)collection {
    [self indexRecord:record uri:uri did:did collection:collection error:nil];
}

- (void)didDeleteRecordWithURI:(NSString *)uri
                           did:(NSString *)did
                    collection:(NSString *)collection {
    [self unindexRecordWithURI:uri collection:collection error:nil];
}

#pragma mark - Incremental Indexing

- (BOOL)indexRecord:(NSDictionary *)record
                uri:(NSString *)uri
                 did:(NSString *)did
         collection:(NSString *)collection
              error:(NSError **)error {
    if ([collection isEqualToString:@"app.bsky.actor.profile"]) {
        NSString *sql = @"INSERT OR REPLACE INTO search_actors(did, display_name, handle, description) VALUES (?, ?, ?, ?)";
        NSString *handle = [self.database executeParameterizedQuery:@"SELECT handle FROM accounts WHERE did = ?" params:@[did] error:nil].firstObject[@"handle"];
        return [self.database executeParameterizedUpdate:sql
                                                   params:@[did, record[@"displayName"] ?: [NSNull null], handle ?: [NSNull null], record[@"description"] ?: [NSNull null]]
                                                    error:error];
    } else if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        NSString *sql = @"INSERT OR REPLACE INTO search_posts(uri, did, text) VALUES (?, ?, ?)";
        return [self.database executeParameterizedUpdate:sql
                                                   params:@[uri, did, record[@"text"] ?: [NSNull null]]
                                                    error:error];
    } else if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
        NSString *sql = @"INSERT OR REPLACE INTO search_starter_packs(uri, did, name) VALUES (?, ?, ?)";
        return [self.database executeParameterizedUpdate:sql
                                                   params:@[uri, did, record[@"name"] ?: [NSNull null]]
                                                    error:error];
    }
    return YES;
}

- (BOOL)unindexRecordWithURI:(NSString *)uri
                  collection:(NSString *)collection
                       error:(NSError **)error {
    if ([collection isEqualToString:@"app.bsky.actor.profile"]) {
        // We use DID as primary key for actor search, so resolve URI to DID if needed, 
        // or just delete by DID from URI.
        // For profile, uri is at://did/app.bsky.actor.profile/self
        NSRange didRange = [uri rangeOfString:@"at://"];
        if (didRange.location != NSNotFound) {
            NSString *didPath = [uri substringFromIndex:didRange.length];
            NSRange slashRange = [didPath rangeOfString:@"/"];
            if (slashRange.location != NSNotFound) {
                NSString *did = [didPath substringToIndex:slashRange.location];
                return [self.database executeParameterizedUpdate:@"DELETE FROM search_actors WHERE did = ?" params:@[did] error:error];
            }
        }
    } else if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        return [self.database executeParameterizedUpdate:@"DELETE FROM search_posts WHERE uri = ?" params:@[uri] error:error];
    } else if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
        return [self.database executeParameterizedUpdate:@"DELETE FROM search_starter_packs WHERE uri = ?" params:@[uri] error:error];
    }
    return YES;
}

#pragma mark - Index Management

- (BOOL)rebuildIndexWithError:(NSError **)error {
    GZ_LOG_CORE_INFO(@"SearchIndexService: rebuilding search index from records...");

    // Clear content tables
    [self.database executeParameterizedUpdate:@"DELETE FROM search_actors" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DELETE FROM search_posts" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DELETE FROM search_starter_packs" params:@[] error:nil];

    // Populate search_actors from records + accounts
    NSString *actorsSQL = @"INSERT INTO search_actors(did, display_name, handle, description) "
                          @"SELECT r.did, json_extract(r.value, '$.displayName'), a.handle, json_extract(r.value, '$.description') "
                          @"FROM records r "
                          @"JOIN accounts a ON r.did = a.did "
                          @"WHERE r.collection = 'app.bsky.actor.profile'";
    BOOL ok = [self.database executeParameterizedUpdate:actorsSQL params:@[] error:error];
    if (!ok) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to populate search_actors: %@", error ? *error : @"unknown");
        return NO;
    }

    // Populate search_posts from records
    NSString *postsSQL = @"INSERT INTO search_posts(uri, did, text) "
                         @"SELECT 'at://' || r.did || '/app.bsky.feed.post/' || r.rkey, r.did, json_extract(r.value, '$.text') "
                         @"FROM records r "
                         @"WHERE r.collection = 'app.bsky.feed.post'";
    ok = [self.database executeParameterizedUpdate:postsSQL params:@[] error:error];
    if (!ok) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to populate search_posts: %@", error ? *error : @"unknown");
        return NO;
    }

    // Populate search_starter_packs from records
    NSString *packsSQL = @"INSERT INTO search_starter_packs(uri, did, name) "
                         @"SELECT 'at://' || r.did || '/app.bsky.graph.starterpack/' || r.rkey, r.did, json_extract(r.value, '$.name') "
                         @"FROM records r "
                         @"WHERE r.collection = 'app.bsky.graph.starterpack'";
    ok = [self.database executeParameterizedUpdate:packsSQL params:@[] error:error];
    if (!ok) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to populate search_starter_packs: %@", error ? *error : @"unknown");
        return NO;
    }

    // Rebuild FTS indexes from content tables
    NSError *rebuildError = nil;
    BOOL rebuildOk = [self.database executeParameterizedUpdate:@"INSERT INTO fts_actors(fts_actors) VALUES('rebuild')" params:@[] error:&rebuildError];
    if (!rebuildOk) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to rebuild fts_actors: %@", rebuildError);
    }
    rebuildOk = [self.database executeParameterizedUpdate:@"INSERT INTO fts_posts(fts_posts) VALUES('rebuild')" params:@[] error:&rebuildError];
    if (!rebuildOk) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to rebuild fts_posts: %@", rebuildError);
    }
    rebuildOk = [self.database executeParameterizedUpdate:@"INSERT INTO fts_starter_packs(fts_starter_packs) VALUES('rebuild')" params:@[] error:&rebuildError];
    if (!rebuildOk) {
        GZ_LOG_CORE_ERROR(@"SearchIndexService: failed to rebuild fts_starter_packs: %@", rebuildError);
    }

    GZ_LOG_CORE_INFO(@"SearchIndexService: search index rebuilt successfully");
    return YES;
}

- (BOOL)populateIndexIfEmptyWithError:(NSError **)error {
    // Check if search_actors has any rows
    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT count(*) as cnt FROM search_actors" params:@[] error:nil];
    if (rows.count > 0 && [rows[0][@"cnt"] integerValue] > 0) {
        GZ_LOG_CORE_INFO(@"SearchIndexService: search index already populated, skipping rebuild");
        return YES;
    }

    return [self rebuildIndexWithError:error];
}

@end
