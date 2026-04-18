#import "Admin/AdminPartialHandler.h"
#import "Admin/PDSAdminHandler.h"
#import "Admin/AdminUI/Handlers/AdminUIHandler.h"
#import "Debug/PDSLogger.h"

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
                NSDictionary *itemContext;
                if ([item isKindOfClass:[NSDictionary class]]) {
                    itemContext = item;
                } else {
                    itemContext = @{@".": item};
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

- (nullable NSString *)handlePartialNamed:(NSString *)partialName
                                 headers:(NSDictionary<NSString *, NSString *> *)headers
                                    body:(nullable NSData *)body
                            adminHandler:(PDSAdminHandler *)adminHandler
                                  params:(NSDictionary *)params {
    if ([partialName isEqualToString:@"users"]) {
        return [self renderUsersPartial:adminHandler headers:headers body:body];
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
    if ([partialName isEqualToString:@"chat/convos"]) {
        return [self renderChatConvosPartial:adminHandler headers:headers body:body params:params];
    }
    if ([partialName isEqualToString:@"chat/messages"]) {
        return [self renderChatMessagesPartial:adminHandler headers:headers body:body params:params];
    }

    NSInteger statusCode = 200;
    NSString *contentType = nil;
    NSString *result = [[AdminUIHandler sharedHandler] handleRequestWithMethod:AdminUIHTTPMethodGET
                                                                           path:[@"/admin/partials/" stringByAppendingString:partialName]
                                                                        headers:headers
                                                                           body:body
                                                                     statusCode:&statusCode
                                                                    contentType:&contentType];
    if (result) {
        return result;
    }

    PDS_LOG_WARN(@"Unknown partial: %@", partialName);
    return nil;
}

- (NSDictionary *)dictionaryFromPacket:(id)packet {
    if (![packet isKindOfClass:[NSDictionary class]]) return nil;
    
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
    // Standard PDS admin fetch
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                               path:@"/xrpc/chat.bsky.convo.listConvos"
                                                            headers:headers
                                                               body:body];
    if (!jsonResponse) return nil;

    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:[jsonResponse dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Chat Conversations";
    context[@"section"] = @"chat";

    return [self renderPartialWithTemplate:@"chat_convos" context:context];
}

- (nullable NSString *)renderChatMessagesPartial:(PDSAdminHandler *)adminHandler
                                        headers:(NSDictionary *)headers
                                           body:(nullable NSData *)body
                                         params:(NSDictionary *)params {
    NSString *convoId = params[@"convoId"];
    NSString *path = @"/xrpc/chat.bsky.convo.getMessages";
    if (convoId) {
        path = [path stringByAppendingFormat:@"?convoId=%@", [convoId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }

    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                               path:path
                                                            headers:headers
                                                               body:body];
    if (!jsonResponse) return nil;

    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:[jsonResponse dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (!data) return nil;

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Chat Messages";
    context[@"section"] = @"chat";
    context[@"convoId"] = convoId ?: @"";

    return [self renderPartialWithTemplate:@"chat_messages" context:context];
}

@end
