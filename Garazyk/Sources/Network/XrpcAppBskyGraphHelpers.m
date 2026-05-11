// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "AppView/Services/ActorService.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Identity/ATProtoHandleValidator.h"

#pragma mark - Constants

NSString *const kXrpcGraphMuteStatePreferenceType = @"com.atproto.pds.app.bsky.graph.muteState";

#pragma mark - URI Parsing

BOOL XrpcParseAtURI(NSString *uri, NSString **outDid, NSString **outCollection, NSString **outRkey) {
    if (![uri isKindOfClass:[NSString class]] || uri.length == 0) {
        return NO;
    }

    NSArray<NSString *> *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5 || ![components[0] isEqualToString:@"at:"]) {
        return NO;
    }

    NSString *did = components[2];
    NSString *collection = components[3];
    NSString *rkey = components[4];
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
        return NO;
    }

    if (outDid) *outDid = did;
    if (outCollection) *outCollection = collection;
    if (outRkey) *outRkey = rkey;
    return YES;
}

#pragma mark - Limit Parsing

BOOL XrpcParseLimit(NSString *limitParam, NSInteger *outValue, NSInteger min, NSInteger max, HttpResponse *response) {
    if (!limitParam || limitParam.length == 0) {
        return YES; // Use default
    }

    NSScanner *scanner = [NSScanner scannerWithString:limitParam];
    NSInteger limit = 0;
    if (![scanner scanInteger:&limit] || !scanner.isAtEnd) {
        [XrpcErrorHelper setValidationError:response message:@"Invalid limit parameter"];
        return NO;
    }

    if (limit < min || limit > max) {
        NSString *message = [NSString stringWithFormat:@"Limit must be between %ld and %ld", (long)min, (long)max];
        [XrpcErrorHelper setValidationError:response message:message];
        return NO;
    }

    if (outValue) *outValue = limit;
    return YES;
}

#pragma mark - Preference Helpers

NSMutableArray<NSDictionary *> *XrpcMutablePreferenceEntries(NSDictionary *preferencesEnvelope) {
    id rawPreferences = [preferencesEnvelope isKindOfClass:[NSDictionary class]] ? preferencesEnvelope[@"preferences"] : nil;
    NSArray *source = [rawPreferences isKindOfClass:[NSArray class]] ? rawPreferences : @[];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:source.count];
    for (id entry in source) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [entries addObject:[(NSDictionary *)entry mutableCopy]];
        }
    }
    return entries;
}

NSMutableArray<NSString *> *XrpcNormalizedUniqueStringArray(id rawValue) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    if (![rawValue isKindOfClass:[NSArray class]]) {
        return values;
    }

    for (id item in (NSArray *)rawValue) {
        if (![item isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *value = (NSString *)item;
        if (value.length == 0 || [seen containsObject:value]) {
            continue;
        }
        [seen addObject:value];
        [values addObject:value];
    }

    return values;
}

NSMutableDictionary *XrpcGraphMuteStateFromPreferences(NSArray<NSDictionary *> *preferences, NSUInteger *outIndex) {
    NSUInteger foundIndex = NSNotFound;
    NSMutableDictionary *state = [@{@"mutedLists": @[], @"mutedThreads": @[]} mutableCopy];

    for (NSUInteger index = 0; index < preferences.count; index++) {
        NSDictionary *entry = preferences[index];
        if (![entry[@"$type"] isEqualToString:kXrpcGraphMuteStatePreferenceType]) {
            continue;
        }
        foundIndex = index;
        state[@"mutedLists"] = XrpcNormalizedUniqueStringArray(entry[@"mutedLists"]);
        state[@"mutedThreads"] = XrpcNormalizedUniqueStringArray(entry[@"mutedThreads"]);
        break;
    }

    if (outIndex) {
        *outIndex = foundIndex;
    }
    return state;
}

BOOL XrpcPersistGraphMuteState(ActorService *actorService, NSString *actorDID, NSMutableArray<NSDictionary *> *preferences, NSMutableDictionary *state, NSUInteger existingIndex, NSError **error) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"$type"] = kXrpcGraphMuteStatePreferenceType;
    entry[@"mutedLists"] = XrpcNormalizedUniqueStringArray(state[@"mutedLists"]);
    entry[@"mutedThreads"] = XrpcNormalizedUniqueStringArray(state[@"mutedThreads"]);

    if (existingIndex != NSNotFound && existingIndex < preferences.count) {
        preferences[existingIndex] = entry;
    } else {
        [preferences addObject:entry];
    }

    return [actorService putPreferencesForActor:actorDID preferences:preferences error:error];
}

NSString *XrpcNormalizeListPurpose(NSString *purpose) {
    if (![purpose isKindOfClass:[NSString class]] || purpose.length == 0) {
        return nil;
    }
    if ([purpose isEqualToString:@"modlist"]) {
        return @"app.bsky.graph.defs#modlist";
    }
    if ([purpose isEqualToString:@"curatelist"]) {
        return @"app.bsky.graph.defs#curatelist";
    }
    if ([purpose isEqualToString:@"app.bsky.graph.defs#modlist"] ||
        [purpose isEqualToString:@"app.bsky.graph.defs#curatelist"]) {
        return purpose;
    }
    return nil;
}

#pragma mark - Actor Resolution

NSString *XrpcResolveActorIdentifierToDid(PDSServiceDatabases *serviceDatabases, NSString *actorIdentifier) {
    if (![actorIdentifier isKindOfClass:[NSString class]] || actorIdentifier.length == 0) {
        return nil;
    }
    if ([actorIdentifier hasPrefix:@"did:"]) {
        return actorIdentifier;
    }

    NSError *lookupError = nil;
    PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:actorIdentifier error:&lookupError];
    if (account.did.length > 0) {
        return account.did;
    }

    NSString *normalized = [ATProtoHandleValidator normalizeHandle:actorIdentifier];
    if (normalized.length > 0 && ![normalized isEqualToString:actorIdentifier]) {
        lookupError = nil;
        account = [serviceDatabases getAccountByHandle:normalized error:&lookupError];
        if (account.did.length > 0) {
            return account.did;
        }
    }

    return nil;
}

#pragma mark - List View Helpers

NSDictionary *XrpcLoadListItemViewForListAndSubject(PDSDatabase *appViewDatabase, ActorService *actorService, NSString *creatorDid, NSString *listURI, NSString *subjectDid) {
    NSError *queryError = nil;
    NSArray<NSDictionary *> *itemRows = [appViewDatabase executeParameterizedQuery:
                                         @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ? ORDER BY rkey DESC LIMIT 500"
                                                                                params:@[creatorDid, @"app.bsky.graph.listitem"]
                                                                                 error:&queryError];
    if (!itemRows) {
        return nil;
    }

    NSDictionary *subjectProfile = [actorService getProfileForActor:subjectDid error:nil] ?: @{@"did": subjectDid};
    for (NSDictionary *itemRow in itemRows) {
        NSString *cidStr = itemRow[@"cid"];
        CID *cid = [CID cidFromString:cidStr];
        if (!cid) continue;

        PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:creatorDid error:nil];
        if (!block.blockData) continue;

        NSDictionary *itemRecord = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
        if (![itemRecord isKindOfClass:[NSDictionary class]]) continue;
        if (![itemRecord[@"list"] isEqualToString:listURI]) continue;
        if (![itemRecord[@"subject"] isEqualToString:subjectDid]) continue;

        NSString *rkey = itemRow[@"rkey"];
        NSString *itemURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.listitem/%@", creatorDid, rkey ?: @""];
        return @{
            @"uri": itemURI,
            @"subject": subjectProfile
        };
    }

    return nil;
}

NSDictionary *XrpcLoadListViewForURI(PDSDatabase *appViewDatabase, ActorService *actorService, NSString *listURI) {
    NSString *did = nil;
    NSString *collection = nil;
    NSString *rkey = nil;
    if (!XrpcParseAtURI(listURI, &did, &collection, &rkey) ||
        ![collection isEqualToString:@"app.bsky.graph.list"]) {
        return nil;
    }

    NSError *error = nil;
    NSArray *rows = [appViewDatabase executeParameterizedQuery:@"SELECT cid FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1"
                                                        params:@[did, collection, rkey]
                                                         error:&error];
    if (rows.count == 0) {
        return nil;
    }

    NSString *cidStr = rows.firstObject[@"cid"];
    CID *cid = [CID cidFromString:cidStr];
    NSDictionary *record = nil;
    if (cid) {
        PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:did error:nil];
        if (block.blockData) {
            record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
        }
    }

    return @{
        @"uri": listURI,
        @"cid": cidStr ?: @"",
        @"creator": [actorService getProfileForActor:did error:nil] ?: @{@"did": did},
        @"name": record[@"name"] ?: @"",
        @"purpose": record[@"purpose"] ?: @"app.bsky.graph.defs#modlist",
        @"description": record[@"description"] ?: @"",
        @"indexedAt": record[@"createdAt"] ?: @"",
        @"viewer": @{@"muted": @NO},
        @"labels": @[]
    };
}
