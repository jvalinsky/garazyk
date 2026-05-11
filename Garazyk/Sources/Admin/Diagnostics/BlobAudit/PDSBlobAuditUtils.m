// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditUtils.h"
#import "Core/CID.h"

NSString *_Nullable PDSBlobAuditCIDStringFromRawBytes(NSData *_Nullable rawCID) {
    if (rawCID.length == 0) {
        return nil;
    }

    CID *cid = [CID cidFromBytes:rawCID];
    return cid.stringValue;
}

NSString *_Nullable PDSBlobAuditCursorFromRawBytes(NSData *_Nullable rawCID) {
    if (rawCID.length == 0) {
        return nil;
    }
    return [rawCID base64EncodedStringWithOptions:0];
}

NSArray<NSString *> *PDSBlobAuditSortedStrings(NSSet<NSString *> *strings) {
    return [[strings allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

static void PDSBlobAuditCollectBlobReferenceCIDs(id json, NSMutableSet<NSString *> *results) {
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)json;
        if ([dict[@"$type"] isEqualToString:@"blob"]) {
            id ref = dict[@"ref"];
            NSString *candidate = nil;
            if ([ref isKindOfClass:[NSString class]]) {
                candidate = ref;
            } else if ([ref isKindOfClass:[NSDictionary class]]) {
                id link = ((NSDictionary *)ref)[@"$link"];
                if ([link isKindOfClass:[NSString class]]) {
                    candidate = link;
                }
            }

            CID *cid = candidate.length > 0 ? [CID cidFromString:candidate] : nil;
            if (cid.stringValue.length > 0) {
                [results addObject:cid.stringValue];
            }
        }

        for (id key in dict) {
            PDSBlobAuditCollectBlobReferenceCIDs(dict[key], results);
        }
    } else if ([json isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)json) {
            PDSBlobAuditCollectBlobReferenceCIDs(item, results);
        }
    }
}

NSSet<NSString *> *PDSBlobAuditBlobReferenceCIDsFromJSONObject(id _Nullable json) {
    NSMutableSet<NSString *> *results = [NSMutableSet set];
    PDSBlobAuditCollectBlobReferenceCIDs(json, results);
    return [results copy];
}
