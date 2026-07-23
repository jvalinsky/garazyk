// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRepoPack+Describe.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSAccountService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabaseAccount.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcRepoPack (Describe)

+ (void)registerDescribeRoutesWithDispatcher:(XrpcDispatcher *)dispatcher
                                   services:(id<XrpcRoutePackServices>)services {
    PDSRecordService *recordService = services.recordService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;

#pragma mark - com.atproto.repo.describeRepo
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_describeRepo handler:^(HttpRequest *request, HttpResponse *response) {
        // Per lexicon: does not require auth.
        NSString *identifier = [request queryParamForKey:@"repo"] ?: @"";
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo"}];
            return;
        }

        NSString *did = nil;
        PDSDatabaseAccount *localAccount = nil;
        if ([identifier hasPrefix:@"did:"]) {
            did = identifier;
            localAccount = [serviceDatabases getAccountByDid:did error:nil];
        } else {
            NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:identifier];
            localAccount = [serviceDatabases getAccountByHandle:normalizedHandle error:nil];
            did = localAccount.did;
        }

        if (!localAccount) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
            return;
        }

        NSDictionary *stats = [recordService getRepoStatsForDid:did error:nil];

        // Resolve full DID document (required by lexicon).
        DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:nil];
        NSDictionary *didDocJson = nil;

        if (doc) {
            didDocJson = doc.jsonDictionary ?: @{};
        } else {
            // Fallback: construct a minimal DID document for local accounts
            // when PLC resolution is unavailable (e.g. PDS_PLC_URL=skip)
            NSString *accountHandle = localAccount.handle.length > 0 ? [localAccount.handle lowercaseString] : @"handle.invalid";
            didDocJson = @{
                @"id": did,
                @"alsoKnownAs": accountHandle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", accountHandle]] : @[]
            };
        }

        NSString *handleFromDidDoc = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
        NSString *accountHandle = localAccount.handle.length > 0 ? [localAccount.handle lowercaseString] : @"handle.invalid";
        BOOL handleIsCorrect = (handleFromDidDoc.length > 0 && [handleFromDidDoc isEqualToString:accountHandle]) || (doc == nil && localAccount.handle.length > 0);

        NSMutableArray *collections = [NSMutableArray array];
        NSMutableArray *collectionStats = [NSMutableArray array];
        if ([stats[@"collections"] isKindOfClass:[NSArray class]]) {
            for (NSDictionary *col in stats[@"collections"]) {
                if ([col isKindOfClass:[NSDictionary class]] && [col[@"collection"] isKindOfClass:[NSString class]]) {
                    [collections addObject:col[@"collection"]];
                    [collectionStats addObject:@{
                        @"name": col[@"collection"],
                        @"count": col[@"count"] ?: @(0)
                    }];
                }
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": accountHandle,
            @"did": did,
            @"didDoc": didDocJson,
            @"collections": collections,
            @"collectionStats": collectionStats,
            @"handleIsCorrect": @(handleIsCorrect)
        }];
    }];
}

@end
