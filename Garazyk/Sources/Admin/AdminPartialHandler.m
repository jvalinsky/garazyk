#import "Admin/AdminPartialHandler.h"
#import "Admin/PDSAdminHandler.h"
#import "Admin/AdminUI/Handlers/AdminUIHandler.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"

@implementation AdminPartialHandler

+ (instancetype)sharedHandler {
    static AdminPartialHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AdminPartialHandler alloc] init];
    });
    return shared;
}

- (nullable NSString *)renderPartialWithTemplate:(NSString *)templateName
                                          context:(NSDictionary *)context {
    NSString *templatePath = [self templatePathForName:templateName];
    if (!templatePath) {
        PDS_LOG_WARN(@"Template not found: %@", templateName);
        return nil;
    }

    NSError *error = nil;
    NSString *template = [NSString stringWithContentsOfFile:templatePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (!template) {
        PDS_LOG_WARN(@"Failed to read template %@: %@", templateName, error);
        return nil;
    }

    // Handle loops with {{#each items}}...{{/each}}
    template = [self processLoops:template context:context];

    // Handle conditionals with {{#if key}}...{{else}}...{{/if}}
    template = [self processConditionals:template context:context];

    // Replace {{key.path}} with context values
    template = [self renderPartialContent:template context:context];

    // Clean up unreplaced placeholders
    template = [template stringByReplacingOccurrencesOfString:@"{{[^}]+}}"
                                                   withString:@""
                                                      options:NSRegularExpressionSearch
                                                        range:NSMakeRange(0, template.length)];

    return template;
}

- (id)valueForKeyPath:(NSString *)keyPath inContext:(NSDictionary *)context {
    if ([keyPath isEqualToString:@"."]) {
        return context;
    }
    
    NSArray *parts = [keyPath componentsSeparatedByString:@"."];
    id current = context;
    
    for (NSString *part in parts) {
        if ([current isKindOfClass:[NSDictionary class]]) {
            current = current[part];
        } else {
            return nil;
        }
        
        if (!current || current == [NSNull null]) {
            return nil;
        }
    }
    
    return current;
}

- (NSString *)stringFromValue:(id)value {
    if (!value || value == [NSNull null]) {
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *arr = value;
        return [arr componentsJoinedByString:@", "];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                       options:0
                                                         error:&error];
        if (data) {
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    return [value description] ?: @"";
}

- (NSString *)processLoops:(NSString *)template context:(NSDictionary *)context {
    NSError *error = nil;
    // Regex to match INNERMOST loops first
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\{#each\\s+([\\w.]+)\\}\\}((?:(?!\\{\\{#each)[\\s\\S])*?)\\{\\{/each\\}\\}"
                               options:0
                                 error:&error];

    BOOL found = YES;
    while (found) {
        NSArray *matches = [regex matchesInString:template options:0
                                             range:NSMakeRange(0, template.length)];
        if (matches.count == 0) {
            found = NO;
            break;
        }

        // Process only the first match to keep it simple and handle nested loops correctly in the loop
        NSTextCheckingResult *match = matches[0];
        NSString *listKey = [template substringWithRange:[match rangeAtIndex:1]];
        NSString *loopBody = [template substringWithRange:[match rangeAtIndex:2]];

        id listValue = [self valueForKeyPath:listKey inContext:context];
        NSMutableString *result = [NSMutableString string];

        if ([listValue isKindOfClass:[NSArray class]]) {
            NSArray *items = listValue;
            for (NSUInteger i = 0; i < items.count; i++) {
                id item = items[i];
                NSMutableDictionary *itemContext = [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [itemContext addEntriesFromDictionary:item];
                    itemContext[@"."] = item;
                } else {
                    itemContext[@"."] = item;
                }
                
                NSString *renderedItem = [self renderPartialContent:loopBody context:itemContext];
                [result appendString:renderedItem];
            }
        }

        template = [template stringByReplacingCharactersInRange:match.range
                                                     withString:result];
    }

    return template;
}

- (NSString *)renderPartialContent:(NSString *)content context:(NSDictionary *)context {
    NSError *error = nil;
    NSRegularExpression *placeholderRegex = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\{([\\w.]+)\\}\\}"
                               options:0
                                 error:&error];
    
    NSArray *matches = [placeholderRegex matchesInString:content options:0
                                                   range:NSMakeRange(0, content.length)];
    
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *keyPath = [content substringWithRange:[match rangeAtIndex:1]];
        id value = [self valueForKeyPath:keyPath inContext:context];
        NSString *stringValue = [self stringFromValue:value];
        content = [content stringByReplacingCharactersInRange:match.range
                                                   withString:stringValue];
    }
    
    return content;
}

- (NSString *)processConditionals:(NSString *)template context:(NSDictionary *)context {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\{#if\\s+([\\w.]+)\\}\\}([\\s\\S]*?)\\{\\{/if\\}\\}"
                               options:0
                                 error:&error];

    NSArray *matches = [regex matchesInString:template options:0
                                         range:NSMakeRange(0, template.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *condKey = [template substringWithRange:[match rangeAtIndex:1]];
        NSString *condBody = [template substringWithRange:[match rangeAtIndex:2]];

        id condValue = [self valueForKeyPath:condKey inContext:context];
        BOOL isTruthy = NO;

        if ([condValue isKindOfClass:[NSNumber class]]) {
            isTruthy = [condValue boolValue];
        } else if ([condValue isKindOfClass:[NSString class]]) {
            isTruthy = [(NSString *)condValue length] > 0;
        } else if ([condValue isKindOfClass:[NSArray class]]) {
            isTruthy = [(NSArray *)condValue count] > 0;
        } else if (condValue && condValue != [NSNull null]) {
            isTruthy = YES;
        }

        NSString *resultContent = @"";
        NSRange elseRange = [condBody rangeOfString:@"{{else}}"];
        
        if (elseRange.location != NSNotFound) {
            NSString *ifContent = [condBody substringToIndex:elseRange.location];
            NSString *elseContent = [condBody substringFromIndex:elseRange.location + elseRange.length];
            resultContent = isTruthy ? ifContent : elseContent;
        } else {
            resultContent = isTruthy ? condBody : @"";
        }

        template = [template stringByReplacingCharactersInRange:match.range
                                                     withString:resultContent];
    }

    return template;
}

- (nullable NSString *)templatePathForName:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *candidates = @[
        [[[NSBundle mainBundle] resourcePath]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"AdminUI/Templates/%@.html", name]],
        [[NSBundle bundleForClass:[self class]].resourcePath
            stringByAppendingPathComponent:[NSString stringWithFormat:@"AdminUI/Templates/%@.html", name]],
        [[fm currentDirectoryPath]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"Garazyk/Sources/Admin/AdminUI/Templates/%@.html", name]],
        [[[fm currentDirectoryPath]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"../Garazyk/Sources/Admin/AdminUI/Templates/%@.html", name]]
            stringByStandardizingPath]
    ];

    for (NSString *candidate in candidates) {
        if ([fm fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (nullable NSString *)handlePartialRequestWithPath:(NSString *)path
                                           headers:(NSDictionary<NSString *, NSString *> *)headers
                                               body:(nullable NSData *)body {
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

    if ([path hasPrefix:@"/admin/partials/"]) {
        NSString *partialPath = [path substringFromIndex:@"/admin/partials/".length];
        
        // Split partial name and query string
        NSString *partialName = partialPath;
        NSDictionary *params = @{};
        NSRange queryRange = [partialPath rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            partialName = [partialPath substringToIndex:queryRange.location];
            params = [self parseQueryString:partialPath];
        }

        return [self handlePartialNamed:partialName headers:headers body:body adminHandler:adminHandler params:params];
    }

    return nil;
}

- (NSDictionary *)parseQueryString:(NSString *)url {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSRange queryStart = [url rangeOfString:@"?"];

    if (queryStart.location != NSNotFound) {
        NSString *queryString = [url substringWithRange:NSMakeRange(queryStart.location + 1, url.length - queryStart.location - 1)];
        NSArray *pairs = [queryString componentsSeparatedByString:@"&"];

        for (NSString *pair in pairs) {
            NSArray *components = [pair componentsSeparatedByString:@"="];
            if (components.count == 2) {
                NSString *key = [components[0] stringByRemovingPercentEncoding];
                NSString *value = [components[1] stringByRemovingPercentEncoding];
                params[key] = value;
            }
        }
    }

    return [params copy];
}

- (nullable NSDictionary *)dispatchXrpcPath:(NSString *)path
                                     method:(HttpMethod)method
                                    headers:(NSDictionary<NSString *, NSString *> *)headers
                                       body:(nullable NSData *)body {
    NSString *requestPath = path ?: @"";
    NSString *queryString = @"";
    NSRange queryRange = [requestPath rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        queryString = [requestPath substringFromIndex:queryRange.location + 1];
        requestPath = [requestPath substringToIndex:queryRange.location];
    }

    NSString *methodString = @"GET";
    switch (method) {
        case HttpMethodGET: methodString = @"GET"; break;
        case HttpMethodPOST: methodString = @"POST"; break;
        case HttpMethodPUT: methodString = @"PUT"; break;
        case HttpMethodDELETE: methodString = @"DELETE"; break;
        case HttpMethodPATCH: methodString = @"PATCH"; break;
        case HttpMethodOPTIONS: methodString = @"OPTIONS"; break;
        case HttpMethodHEAD: methodString = @"HEAD"; break;
        case HttpMethodUnknown: methodString = @"GET"; break;
    }

    NSDictionary *queryParams = queryString.length > 0 ? [self parseQueryString:[@"?" stringByAppendingString:queryString]] : @{};
    NSMutableDictionary<NSString *, NSString *> *requestHeaders = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    NSString *authorization = requestHeaders[@"authorization"] ?: requestHeaders[@"Authorization"];
    if (authorization.length == 0) {
        NSString *adminToken = requestHeaders[@"x-admin-token"] ?: requestHeaders[@"X-Admin-Token"];
        if (adminToken.length > 0) {
            requestHeaders[@"authorization"] = [NSString stringWithFormat:@"Bearer %@", adminToken];
        }
    }
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:method
                                                   methodString:methodString
                                                           path:requestPath
                                                    queryString:queryString
                                                     queryParams:queryParams
                                                         version:@"HTTP/1.1"
                                                         headers:requestHeaders
                                                            body:body ?: [NSData data]
                                                   remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];
    [[XrpcDispatcher sharedDispatcher] handleRequest:request response:response];
    if (response.statusCode >= 400) {
        PDS_LOG_WARN(@"XRPC call failed for %@ (%ld)", path, (long)response.statusCode);
    }

    if (response.body.length == 0) {
        return @{};
    }

    NSError *parseError = nil;
    id payload = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&parseError];
    if (parseError || ![payload isKindOfClass:[NSDictionary class]]) {
        PDS_LOG_WARN(@"XRPC response was not a dictionary for %@: %@", path, parseError);
        return nil;
    }
    return payload;
}

- (nullable NSString *)handlePartialNamed:(NSString *)partialName
                                 headers:(NSDictionary<NSString *, NSString *> *)headers
                                    body:(nullable NSData *)body
                            adminHandler:(PDSAdminHandler *)adminHandler
                                  params:(NSDictionary *)params {
    if ([partialName isEqualToString:@"users"]) {
        return [self renderUsersPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"users/search"]) {
        return [self renderUsersSearchPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"users/detail"]) {
        return [self renderUsersDetailPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"users/usage"]) {
        return [self renderUsersUsagePartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"invites"]) {
        return [self renderInvitesPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"health"]) {
        return [self renderHealthPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"stats"]) {
        return [self renderStatsPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"blobs"]) {
        return [self renderBlobsPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"identity"]) {
        return [self renderIdentityPartial:adminHandler headers:headers body:body];
    }
    if ([partialName isEqualToString:@"plc/lookup"]) {
        return [self renderPartialWithTemplate:@"plc/did-lookup" context:@{}];
    }
    if ([partialName isEqualToString:@"plc/export"]) {
        return [self renderPartialWithTemplate:@"plc/export" context:@{}];
    }
    if ([partialName isEqualToString:@"plc/metrics"]) {
        return [self renderPartialWithTemplate:@"plc/metrics" context:@{}];
    }
    if ([partialName isEqualToString:@"plc/operations"]) {
        return [self renderPartialWithTemplate:@"plc/operations" context:@{}];
    }
    if ([partialName isEqualToString:@"relay/operators"]) {
        return [self renderPartialWithTemplate:@"relay/operators" context:@{}];
    }
    if ([partialName isEqualToString:@"chat/convos"]) {
        return [self renderChatConvosPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/convos/search"]) {
        return [self renderChatConvosPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/messages"]) {
        return [self renderChatMessagesPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/groups"]) {
        return [self renderPartialWithTemplate:@"chat_groups" context:@{}];
    }
    if ([partialName isEqualToString:@"chat/groups/list"]) {
        return [self renderChatGroupsListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/groups/search"]) {
        return [self renderChatGroupsListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/groups/detail"]) {
        return [self renderChatGroupDataPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/invite-links"]) {
        return [self renderPartialWithTemplate:@"chat_invite_links" context:@{}];
    }
    if ([partialName isEqualToString:@"chat/invite-links/list"]) {
        return [self renderChatInviteLinksListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/invite-links/search"]) {
        return [self renderChatInviteLinksListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/groups/data"]) {
        return [self renderChatGroupDataPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/events"]) {
        return [self renderPartialWithTemplate:@"ozone_events" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/events/list"]) {
        return [self renderOzoneEventsListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/statuses"]) {
        return [self renderPartialWithTemplate:@"ozone_statuses" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/statuses/list"]) {
        return [self renderOzoneStatusesListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/team"]) {
        return [self renderPartialWithTemplate:@"ozone_team" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/team/list"]) {
        return [self renderOzoneTeamListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/templates"]) {
        return [self renderPartialWithTemplate:@"ozone_templates" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/templates/list"]) {
        return [self renderOzoneTemplatesListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/sets"]) {
        return [self renderPartialWithTemplate:@"ozone_sets" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/sets/list"]) {
        return [self renderOzoneSetsListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/verification"]) {
        return [self renderPartialWithTemplate:@"ozone_verification" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/verification/list"]) {
        return [self renderOzoneVerificationListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/safelinks"]) {
        return [self renderPartialWithTemplate:@"ozone_safelinks" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/safelinks/list"]) {
        return [self renderOzoneSafelinksListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/scheduled"]) {
        return [self renderPartialWithTemplate:@"ozone_scheduled" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/scheduled/list"]) {
        return [self renderOzoneScheduledListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"ozone/config"]) {
        return [self renderPartialWithTemplate:@"ozone_config" context:@{}];
    }
    if ([partialName isEqualToString:@"ozone/config/data"]) {
        return [self renderOzoneConfigDataPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"security/sessions/list"]) {
        return [self renderSecuritySessionsListPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"security/app-passwords/list"]) {
        return [self renderSecurityAppPasswordsListPartial:adminHandler headers:headers body:body params:params];
    }

    PDS_LOG_WARN(@"Partial not handled by template handler: %@", partialName);
    return nil;
}

- (NSDictionary *)dictionaryFromPacket:(id)packet {
    if (![packet isKindOfClass:[NSDictionary class]]) return nil;
    
    if (!packet[@"body"]) {
        return packet;
    }

    id data = packet[@"body"];
    if ([data isKindOfClass:[NSDictionary class]]) {
        return data;
    }
    
    if ([data isKindOfClass:[NSString class]]) {
        NSData *jsonData = [data dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (!error && [dict isKindOfClass:[NSDictionary class]]) {
            return dict;
        }
    }
    
    return nil;
}

- (nullable NSString *)renderUsersPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getUsersData]];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Users";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"users" context:context];
}

- (nullable NSString *)renderUsersSearchPartial:(PDSAdminHandler *)adminHandler
                                        headers:(NSDictionary *)headers
                                           body:(nullable NSData *)body
                                         params:(NSDictionary *)params {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getUsersData]];
    if (!data) return nil;

    NSString *query = [[params[@"q"] ?: @"" description] lowercaseString];
    NSArray *users = data[@"users"];
    if (![users isKindOfClass:[NSArray class]]) {
        users = @[];
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *user in users) {
        if (![user isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *did = [user[@"did"] isKindOfClass:[NSString class]] ? user[@"did"] : @"";
        NSString *handle = [user[@"handle"] isKindOfClass:[NSString class]] ? user[@"handle"] : @"";
        NSString *email = [user[@"email"] isKindOfClass:[NSString class]] ? user[@"email"] : @"";
        NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@", did, handle, email] lowercaseString];
        if (query.length > 0 && [haystack rangeOfString:query].location == NSNotFound) {
            continue;
        }

        NSMutableDictionary *mapped = [NSMutableDictionary dictionary];
        mapped[@"did"] = did;
        mapped[@"handle"] = handle;
        mapped[@"email"] = email;
        mapped[@"active"] = @(![user[@"deactivated"] boolValue]);
        mapped[@"createdAt"] = [user[@"created_at"] isKindOfClass:[NSString class]] ? user[@"created_at"] : @"";
        [rows addObject:mapped];
    }

    NSDictionary *context = @{@"users": rows};
    return [self renderPartialWithTemplate:@"partials/users-search-response" context:context];
}

- (nullable NSString *)renderUsersDetailPartial:(PDSAdminHandler *)adminHandler
                                        headers:(NSDictionary *)headers
                                           body:(nullable NSData *)body
                                         params:(NSDictionary *)params {
    NSString *did = params[@"did"];
    if (did.length == 0) {
        return @"<p class=\"text-destructive\">Missing DID</p>";
    }
    NSDictionary *userDetail = [adminHandler getUserDetailDataForDid:did];
    if (!userDetail) {
        return @"<p class=\"text-destructive\">User not found</p>";
    }
    return [self renderPartialWithTemplate:@"partials/users-detail" context:userDetail];
}

- (nullable NSString *)renderUsersUsagePartial:(PDSAdminHandler *)adminHandler
                                       headers:(NSDictionary *)headers
                                          body:(nullable NSData *)body
                                        params:(NSDictionary *)params {
    NSString *did = params[@"did"];
    if (did.length == 0) {
        return @"<p class=\"text-destructive\">Missing DID</p>";
    }

    // Call the XRPC endpoint to get account usage
    NSDictionary *usageResult = [adminHandler dispatchXrpcJSONMethod:@"com.atproto.admin.getAccountUsage"
                                                          httpMethod:HttpMethodGET
                                                             headers:headers
                                                            jsonBody:@{@"did": did}];

    if (!usageResult) {
        return @"<p class=\"text-secondary\">Usage data unavailable</p>";
    }

    // Format byte values for display
    unsigned long long blobBytes = [usageResult[@"blobBytes"] unsignedLongLongValue];
    unsigned long long repoBytes = [usageResult[@"repoBytes"] unsignedLongLongValue];
    NSString *blobBytesFormatted = [self formatByteCount:blobBytes];
    NSString *repoBytesFormatted = [self formatByteCount:repoBytes];

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:usageResult];
    context[@"blobBytesFormatted"] = blobBytesFormatted;
    context[@"repoBytesFormatted"] = repoBytesFormatted;

    return [self renderPartialWithTemplate:@"partials/users-usage" context:context];
}

- (NSString *)formatByteCount:(unsigned long long)bytes {
    if (bytes == 0) return @"0 B";
    const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int unitIndex = 0;
    double value = (double)bytes;
    while (value >= 1024.0 && unitIndex < 4) {
        value /= 1024.0;
        unitIndex++;
    }
    return [NSString stringWithFormat:@"%.1f %s", value, units[unitIndex]];
}

- (nullable NSString *)renderInvitesPartial:(PDSAdminHandler *)adminHandler
                                     headers:(NSDictionary *)headers
                                        body:(nullable NSData *)body {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getInvitesData]];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Invite Codes";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"invites" context:context];
}

- (nullable NSString *)renderHealthPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getHealthData]];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Server Health";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"health" context:context];
}

- (nullable NSString *)renderStatsPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getStatsData]];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Server Statistics";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"stats" context:context];
}

- (nullable NSString *)renderBlobsPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSDictionary *data = [self dictionaryFromPacket:[adminHandler getBlobsData]];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Blob Storage";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"blobs" context:context];
}

- (nullable NSString *)renderIdentityPartial:(PDSAdminHandler *)adminHandler
                                     headers:(NSDictionary *)headers
                                        body:(nullable NSData *)body {
    NSMutableDictionary *context = [NSMutableDictionary dictionary];
    context[@"title"] = @"Identity";
    context[@"section"] = @"pds";
    context[@"recent_ops"] = @[];

    return [self renderPartialWithTemplate:@"identity" context:context];
}

- (nullable NSString *)renderChatConvosPartial:(PDSAdminHandler *)adminHandler
                                      headers:(NSDictionary *)headers
                                         body:(nullable NSData *)body
                                       params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/chat.bsky.convo.listConvos"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    NSString *query = [[params[@"q"] ?: @"" description] lowercaseString];
    if (query.length > 0 && [context[@"convos"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *convo in context[@"convos"]) {
            if (![convo isKindOfClass:[NSDictionary class]]) continue;
            NSString *haystack = [[convo description] lowercaseString];
            if ([haystack rangeOfString:query].location != NSNotFound) {
                [filtered addObject:convo];
            }
        }
        context[@"convos"] = filtered;
    }
    context[@"title"] = @"Chat Conversations";
    context[@"section"] = @"chat";

    return [self renderPartialWithTemplate:@"chat_convos" context:context];
}

- (nullable NSString *)renderChatMessagesPartial:(PDSAdminHandler *)adminHandler
                                        headers:(NSDictionary *)headers
                                           body:(nullable NSData *)body
                                         params:(NSDictionary *)params {
    (void)adminHandler;
    NSString *convoId = params[@"convoId"];
    NSString *path = @"/xrpc/chat.bsky.convo.getMessages";
    if (convoId) {
        path = [path stringByAppendingFormat:@"?convoId=%@", [convoId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }

    NSDictionary *data = [self dispatchXrpcPath:path
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Chat Messages";
    context[@"section"] = @"chat";
    context[@"convoId"] = convoId ?: @"";
    NSArray *messages = [context[@"messages"] isKindOfClass:[NSArray class]] ? context[@"messages"] : @[];
    context[@"has_messages"] = @(messages.count > 0);

    return [self renderPartialWithTemplate:@"chat_messages" context:context];
}

- (nullable NSString *)renderChatGroupsListPartial:(PDSAdminHandler *)adminHandler
                                          headers:(NSDictionary *)headers
                                             body:(nullable NSData *)body
                                           params:(NSDictionary *)params {
    (void)adminHandler;
    NSString *query = params[@"q"];
    NSString *path = @"/xrpc/chat.bsky.group.listGroups";
    if (query) {
        path = [path stringByAppendingFormat:@"?q=%@", [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }
    
    NSDictionary *data = [self dispatchXrpcPath:path
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"section"] = @"chat";

    return [self renderPartialWithTemplate:@"chat_groups_list" context:context];
}

- (nullable NSString *)renderChatInviteLinksListPartial:(PDSAdminHandler *)adminHandler
                                              headers:(NSDictionary *)headers
                                                 body:(nullable NSData *)body
                                               params:(NSDictionary *)params {
    (void)adminHandler;
    NSString *query = params[@"q"];
    NSString *path = @"/xrpc/chat.bsky.group.listInviteLinks";
    if (query) {
        path = [path stringByAppendingFormat:@"?q=%@", [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }

    NSDictionary *data = [self dispatchXrpcPath:path
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"section"] = @"chat";

    return [self renderPartialWithTemplate:@"chat_invite_links_list" context:context];
}

- (nullable NSString *)renderChatGroupDataPartial:(PDSAdminHandler *)adminHandler
                                         headers:(NSDictionary *)headers
                                            body:(nullable NSData *)body
                                          params:(NSDictionary *)params {
    (void)adminHandler;
    NSString *groupUri = params[@"groupUri"];
    if (!groupUri) return nil;

    NSString *path = [NSString stringWithFormat:@"/xrpc/chat.bsky.group.getGroupPublicInfo?groupUri=%@", [groupUri stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    NSDictionary *packet = [self dispatchXrpcPath:path
                                           method:HttpMethodGET
                                          headers:headers
                                             body:body];
    NSDictionary *group = packet[@"group"];
    if (!group) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:group];
    
    // Fetch members too
    NSString *memberPath = [NSString stringWithFormat:@"/xrpc/chat.bsky.group.listMembers?groupUri=%@", [groupUri stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSDictionary *memberPacket = [self dispatchXrpcPath:memberPath
                                                 method:HttpMethodGET
                                                headers:headers
                                                   body:body];
    if (memberPacket) {
        NSMutableArray *members = [NSMutableArray array];
        for (NSDictionary *member in memberPacket[@"members"] ?: @[]) {
            if (![member isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSMutableDictionary *mutableMember = [member mutableCopy];
            mutableMember[@"uri"] = groupUri;
            [members addObject:mutableMember];
        }
        context[@"members"] = members;
    }

    return [self renderPartialWithTemplate:@"chat_group_detail" context:context];
}

- (nullable NSString *)renderOzoneEventsListPartial:(PDSAdminHandler *)adminHandler
                                           headers:(NSDictionary *)headers
                                              body:(nullable NSData *)body
                                            params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.moderation.queryEvents"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    return [self renderPartialWithTemplate:@"ozone_events_list" context:data ?: @{}];
}

- (nullable NSString *)renderOzoneStatusesListPartial:(PDSAdminHandler *)adminHandler
                                             headers:(NSDictionary *)headers
                                                body:(nullable NSData *)body
                                              params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    return [self renderPartialWithTemplate:@"ozone_statuses_list" context:data ?: @{}];
}

- (nullable NSString *)renderOzoneTeamListPartial:(PDSAdminHandler *)adminHandler
                                         headers:(NSDictionary *)headers
                                            body:(nullable NSData *)body
                                          params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.team.listMembers"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    return [self renderPartialWithTemplate:@"ozone_team_list" context:data ?: @{}];
}

- (nullable NSString *)renderOzoneTemplatesListPartial:(PDSAdminHandler *)adminHandler
                                              headers:(NSDictionary *)headers
                                                 body:(nullable NSData *)body
                                               params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.communication.listTemplates"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    return [self renderPartialWithTemplate:@"ozone_templates_list" context:data ?: @{}];
}

- (nullable NSString *)renderOzoneSetsListPartial:(PDSAdminHandler *)adminHandler
                                         headers:(NSDictionary *)headers
                                            body:(nullable NSData *)body
                                          params:(NSDictionary *)params {
    (void)adminHandler;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.set.list"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    return [self renderPartialWithTemplate:@"ozone_sets_list" context:data ?: @{}];
}

- (nullable NSString *)renderOzoneVerificationListPartial:(PDSAdminHandler *)adminHandler
                                                  headers:(NSDictionary *)headers
                                                     body:(nullable NSData *)body
                                                   params:(NSDictionary *)params {
    (void)adminHandler;
    (void)params;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.verification.listVerifications"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    NSArray *items = [data[@"verifications"] isKindOfClass:[NSArray class]] ? data[@"verifications"] : @[];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in items) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *did = entry[@"did"] ?: entry[@"subjectDid"] ?: entry[@"subject"] ?: @"";
        NSString *verifiedAt = entry[@"verified_at"] ?: entry[@"createdAt"] ?: entry[@"created_at"] ?: @"";
        NSString *grantedBy = entry[@"granted_by"] ?: entry[@"createdBy"] ?: @"";
        [rows addObject:@{
            @"did": did,
            @"verified_at": verifiedAt,
            @"granted_by": grantedBy
        }];
    }

    return [self renderPartialWithTemplate:@"ozone_verification_list"
                                   context:@{
                                       @"verifications": rows,
                                       @"has_verifications": @(rows.count > 0)
                                   }];
}

- (nullable NSString *)renderOzoneSafelinksListPartial:(PDSAdminHandler *)adminHandler
                                               headers:(NSDictionary *)headers
                                                  body:(nullable NSData *)body
                                                params:(NSDictionary *)params {
    (void)adminHandler;
    (void)params;
    NSDictionary *rulesData = [self dispatchXrpcPath:@"/xrpc/tools.ozone.safelink.queryRules"
                                              method:HttpMethodGET
                                             headers:headers
                                                body:body];
    NSDictionary *eventsData = [self dispatchXrpcPath:@"/xrpc/tools.ozone.safelink.queryEvents"
                                               method:HttpMethodGET
                                              headers:headers
                                                 body:body];

    NSArray *rulesRaw = [rulesData[@"rules"] isKindOfClass:[NSArray class]] ? rulesData[@"rules"] : @[];
    NSMutableArray *rules = [NSMutableArray array];
    for (NSDictionary *entry in rulesRaw) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *ruleId = entry[@"id"] ?: @"";
        NSString *url = entry[@"url"] ?: entry[@"pattern"] ?: @"";
        NSString *action = entry[@"action"] ?: entry[@"ruleAction"] ?: @"";
        NSString *updatedAt = entry[@"updated_at"] ?: entry[@"updatedAt"] ?: entry[@"created_at"] ?: @"";
        [rules addObject:@{
            @"id": ruleId,
            @"url": url,
            @"action": action,
            @"updated_at": updatedAt
        }];
    }

    NSArray *eventsRaw = [eventsData[@"events"] isKindOfClass:[NSArray class]] ? eventsData[@"events"] : @[];
    NSMutableArray *events = [NSMutableArray array];
    for (NSDictionary *entry in eventsRaw) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        [events addObject:@{
            @"id": entry[@"id"] ?: @"",
            @"url": entry[@"url"] ?: @"",
            @"action": entry[@"action"] ?: @"",
            @"created_at": entry[@"created_at"] ?: entry[@"createdAt"] ?: @""
        }];
    }

    return [self renderPartialWithTemplate:@"ozone_safelinks_list"
                                   context:@{
                                       @"rules": rules,
                                       @"events": events,
                                       @"has_rules": @(rules.count > 0),
                                       @"has_events": @(events.count > 0)
                                   }];
}

- (nullable NSString *)renderOzoneScheduledListPartial:(PDSAdminHandler *)adminHandler
                                               headers:(NSDictionary *)headers
                                                  body:(nullable NSData *)body
                                                params:(NSDictionary *)params {
    (void)adminHandler;
    (void)params;
    NSDictionary *data = [self dispatchXrpcPath:@"/xrpc/tools.ozone.moderation.listScheduledActions"
                                         method:HttpMethodGET
                                        headers:headers
                                           body:body];
    NSArray *raw = [data[@"actions"] isKindOfClass:[NSArray class]] ? data[@"actions"] : @[];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *entry in raw) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *actionId = entry[@"id"] ?: @"";
        NSString *subject = entry[@"subject"] ?: entry[@"did"] ?: entry[@"uri"] ?: @"";
        NSString *action = entry[@"action"] ?: entry[@"type"] ?: @"";
        NSString *scheduledAt = entry[@"scheduled_at"] ?: entry[@"scheduledAt"] ?: entry[@"created_at"] ?: @"";
        NSString *createdBy = entry[@"created_by"] ?: entry[@"createdBy"] ?: @"";
        [actions addObject:@{
            @"id": actionId,
            @"subject": subject,
            @"action": action,
            @"scheduled_at": scheduledAt,
            @"created_by": createdBy
        }];
    }
    return [self renderPartialWithTemplate:@"ozone_scheduled_list"
                                   context:@{
                                       @"actions": actions,
                                       @"has_actions": @(actions.count > 0)
                                   }];
}

- (nullable NSString *)renderOzoneConfigDataPartial:(PDSAdminHandler *)adminHandler
                                            headers:(NSDictionary *)headers
                                               body:(nullable NSData *)body
                                             params:(NSDictionary *)params {
    (void)adminHandler;
    (void)params;
    NSDictionary *configData = [self dispatchXrpcPath:@"/xrpc/tools.ozone.server.getConfig"
                                               method:HttpMethodGET
                                              headers:headers
                                                 body:body] ?: @{};
    NSDictionary *optionsData = [self dispatchXrpcPath:@"/xrpc/tools.ozone.setting.listOptions"
                                                method:HttpMethodGET
                                               headers:headers
                                                  body:body] ?: @{};
    NSArray *rawOptions = [optionsData[@"options"] isKindOfClass:[NSArray class]] ? optionsData[@"options"] : @[];
    NSMutableArray *options = [NSMutableArray array];
    for (NSDictionary *entry in rawOptions) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        [options addObject:@{
            @"key": entry[@"key"] ?: @"",
            @"value": [self stringFromValue:entry[@"value"]] ?: @"",
            @"scope": entry[@"scope"] ?: @"global"
        }];
    }

    NSString *configPretty = [self stringFromValue:configData] ?: @"{}";
    return [self renderPartialWithTemplate:@"ozone_config_data"
                                   context:@{
                                       @"config_pretty": configPretty,
                                       @"options": options,
                                       @"has_options": @(options.count > 0)
                                   }];
}

- (nullable NSString *)renderSecuritySessionsListPartial:(PDSAdminHandler *)adminHandler
                                                headers:(NSDictionary *)headers
                                                   body:(nullable NSData *)body
                                                 params:(NSDictionary *)params {
    NSString *did = params[@"did"];
    if (!did) return nil;

    NSString *path = [NSString stringWithFormat:@"/admin/security/sessions?did=%@", [did stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                               path:path
                                                            headers:headers
                                                               body:body];
    if (!jsonResponse) return nil;
    
    NSDictionary *packet = [NSJSONSerialization JSONObjectWithData:[jsonResponse dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary *data = [self dictionaryFromPacket:packet];
    
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data ?: @{}];
    context[@"did"] = did;
    
    return [self renderPartialWithTemplate:@"security_sessions_list" context:context];
}

- (nullable NSString *)renderSecurityAppPasswordsListPartial:(PDSAdminHandler *)adminHandler
                                                     headers:(NSDictionary *)headers
                                                        body:(nullable NSData *)body
                                                      params:(NSDictionary *)params {
    NSString *did = params[@"did"];
    if (!did) return nil;

    NSString *path = [NSString stringWithFormat:@"/admin/security/app-passwords?did=%@", [did stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                               path:path
                                                            headers:headers
                                                               body:body];
    if (!jsonResponse) return nil;
    
    NSDictionary *packet = [NSJSONSerialization JSONObjectWithData:[jsonResponse dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary *data = [self dictionaryFromPacket:packet];
    
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data ?: @{}];
    context[@"did"] = did;
    
    return [self renderPartialWithTemplate:@"security_app_passwords_list" context:context];
}

#pragma mark - Data Access Methods

- (nullable NSDictionary *)getUserDetailForDid:(NSString *)did {
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];
    return [adminHandler getUserDetailDataForDid:did];
}

- (nullable NSArray *)getModerationReports {
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];
    return [adminHandler getModerationReportsData];
}

@end
