// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Core/DID.h"
#import "AppView/Server/WriteProxy/AppViewWriteProxy.h"
#import "Database/PDSQueryDatabase.h"

@implementation AppViewXRpcRoutePack (Identity)

- (void)handleResolveHandle:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *handle = [request queryParamForKey:@"handle"];
    if (!handle || handle.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"handle parameter is required" }];
        return;
    }

    DIDResolver *resolver = [[DIDResolver alloc] init];
    NSError *error = nil;
    NSString *did = [resolver resolveHandleSync:handle error:&error];

    if (!did)
    {
        response.statusCode = 404;
        [response setJsonBody:@{ @"error": @"HandleNotFound", @"message": [NSString stringWithFormat:@"Handle not found: %@", handle] }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"did": did }];
}

- (void)handleGetRecord:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Invalid AT URI format" }];
        return;
    }

    NSString *did = components[2];
    NSString *collection = components[3];
    NSString *rkey = components[4];

    if (!self.database)
    {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Database not available" }];
        return;
    }

    NSString *query = @"SELECT cid, value FROM records WHERE did = ? AND collection = ? AND rkey = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, collection, rkey] error:nil];

    if (!rows || rows.count == 0)
    {
        response.statusCode = 404;
        [response setJsonBody:@{ @"error": @"RecordNotFound", @"message": @"Record not found" }];
        return;
    }

    NSDictionary *row = rows.firstObject;
    NSString *cid = row[@"cid"];
    id valueObj = row[@"value"];

    NSData *data = nil;
    if ([valueObj isKindOfClass:[NSData class]]) {
        data = valueObj;
    } else if ([valueObj isKindOfClass:[NSString class]]) {
        data = [(NSString *)valueObj dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSDictionary *record = nil;
    if (data && data.length > 0)
    {
        record = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }

    response.statusCode = 200;
    [response setJsonBody:@{
        @"uri": uri,
        @"cid": cid ?: @"",
        @"value": record ?: @{},
        @"did": did,
        @"collection": collection,
        @"rkey": rkey
    }];
}

- (void)handleQueryLabels:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uris parameter is required" }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];

    NSMutableArray *labels = [NSMutableArray array];
    if (self.database)
    {
        for (NSString *uri in uris)
        {
            NSString *query = @"SELECT src, uri, cid, val, neg, created_at FROM labels WHERE uri = ?";
            NSArray *rows = [self.database executeParameterizedQuery:query params:@[uri] error:nil];
            for (NSDictionary *row in rows)
            {
                [labels addObject:@{
                    @"src": row[@"src"] ?: @"",
                    @"uri": row[@"uri"] ?: uri,
                    @"cid": row[@"cid"] ?: @"",
                    @"val": row[@"val"] ?: @"",
                    @"neg": row[@"neg"] ? @([row[@"neg"] boolValue]) : @(NO),
                    @"cts": row[@"created_at"] ?: @""
                }];
            }
        }
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"labels": labels }];
}

- (void)handleGetAccountInfos:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *didsParam = [request queryParamForKey:@"dids"];
    if (!didsParam || didsParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"dids parameter is required" }];
        return;
    }

    NSArray<NSString *> *dids = [didsParam componentsSeparatedByString:@","];
    NSMutableArray *accounts = [NSMutableArray array];

    if (self.database)
    {
        for (NSString *did in dids)
        {
            NSString *query = @"SELECT did, handle, email, created_at FROM accounts WHERE did = ?";
            NSArray *rows = [self.database executeParameterizedQuery:query params:@[did] error:nil];
            if (rows && rows.count > 0)
            {
                NSDictionary *row = rows.firstObject;
                [accounts addObject:@{
                    @"did": row[@"did"] ?: did,
                    @"handle": row[@"handle"] ?: @"",
                    @"email": row[@"email"] ?: @"",
                    @"createdAt": row[@"created_at"] ?: @""
                }];
            }
        }
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"infos": accounts }];
}

- (void)handleGetSubjectStatus:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *did = [request queryParamForKey:@"did"];
    NSString *uri = [request queryParamForKey:@"uri"];

    if ((!did || did.length == 0) && (!uri || uri.length == 0))
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"did or uri parameter is required" }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{
        @"subject": did ? @{ @"did": did } : @{ @"uri": uri },
        @"takedown": @{ @"applied": @(NO) },
        @"review": @{ @"state": @"none" }
    }];
}

- (void)handleProxyWrite:(HttpRequest *)request response:(HttpResponse *)response nsid:(NSString *)nsid
{
    NSString *callerDID = [self requireAuth:request response:response];
    if (!callerDID) return;

    [self.writeProxy proxyWriteRequest:request response:response nsid:nsid callerDID:callerDID];
}

@end