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
    // Simple template rendering - find {{key}} and replace with values
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

    // Replace {{key}} with context values
    for (NSString *key in context) {
        NSString *placeholder = [NSString stringWithFormat:@"{{%@}}", key];
        id value = context[key];
        NSString *stringValue = [self stringFromValue:value];
        template = [template stringByReplacingOccurrencesOfString:placeholder
                                                       withString:stringValue];
    }

    // Handle loops with {{#each items}}...{{/each}}
    template = [self processLoops:template context:context];

    // Handle conditionals with {{#if key}}...{{/if}}
    template = [self processConditionals:template context:context];

    // Clean up unreplaced placeholders
    template = [template stringByReplacingOccurrencesOfString:@"{{[^}]+}}"
                                                   withString:@""
                                                      options:NSRegularExpressionSearch
                                                        range:NSMakeRange(0, template.length)];

    return template;
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
    // Simple {{#each key}}...{{/each}} loop processing
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\{#each\\s+(\\w+)\\}\\}([\\s\\S]*?)\\{\\{/each\\}\\}"
                               options:0
                                 error:&error];

    NSArray *matches = [regex matchesInString:template options:0
                                        range:NSMakeRange(0, template.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *listKey = [template substringWithRange:[match rangeAtIndex:1]];
        NSString *loopBody = [template substringWithRange:[match rangeAtIndex:2]];

        id listValue = context[listKey];
        if (![listValue isKindOfClass:[NSArray class]]) {
            // Remove the loop block entirely if not an array
            template = [template stringByReplacingCharactersInRange:match.range
                                                         withString:@""];
            continue;
        }

        NSArray *items = listValue;
        NSMutableString *result = [NSMutableString string];

        for (NSUInteger i = 0; i < items.count; i++) {
            id item = items[i];
            NSString *itemBody = loopBody;

            // Replace {{.}} with item value (for simple arrays)
            if ([item isKindOfClass:[NSString class]] || [item isKindOfClass:[NSNumber class]]) {
                itemBody = [itemBody stringByReplacingOccurrencesOfString:@"{{.}}"
                                                              withString:[self stringFromValue:item]];
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                // Replace {{key}} with item[key] for object arrays
                NSDictionary *itemDict = item;
                for (NSString *key in itemDict) {
                    NSString *placeholder = [NSString stringWithFormat:@"{{%@}}", key];
                    itemBody = [itemBody stringByReplacingOccurrencesOfString:placeholder
                                                                    withString:[self stringFromValue:itemDict[key]]];
                }
                // Replace {{@index}} with index
                itemBody = [itemBody stringByReplacingOccurrencesOfString:@"{{@index}}"
                                                              withString:[@(i) stringValue]];
            }

            [result appendString:itemBody];
        }

        template = [template stringByReplacingCharactersInRange:match.range
                                                     withString:result];
    }

    return template;
}

- (NSString *)processConditionals:(NSString *)template context:(NSDictionary *)context {
    // Simple {{#if key}}...{{/if}} conditional processing
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\{#if\\s+(\\w+)\\}\\}([\\s\\S]*?)\\{\\{/if\\}\\}"
                               options:0
                                 error:&error];

    NSArray *matches = [regex matchesInString:template options:0
                                        range:NSMakeRange(0, template.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *condKey = [template substringWithRange:[match rangeAtIndex:1]];
        NSString *condBody = [template substringWithRange:[match rangeAtIndex:2]];

        id condValue = context[condKey];
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

        template = [template stringByReplacingCharactersInRange:match.range
                                                     withString:isTruthy ? condBody : @""];
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
    // Route to appropriate partial handler based on path
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

    if ([path hasPrefix:@"/admin/partials/"]) {
        NSString *partialName = [path substringFromIndex:@"/admin/partials/".length];
        return [self handlePartialNamed:partialName headers:headers body:body adminHandler:adminHandler];
    }

    return nil;
}

- (nullable NSString *)handlePartialNamed:(NSString *)partialName
                                 headers:(NSDictionary<NSString *, NSString *> *)headers
                                    body:(nullable NSData *)body
                            adminHandler:(PDSAdminHandler *)adminHandler {
    // Map partial names to templates and data

    // Users partial
    if ([partialName isEqualToString:@"users"]) {
        return [self renderUsersPartial:adminHandler headers:headers body:body];
    }

    // Invites partial
    if ([partialName isEqualToString:@"invites"]) {
        return [self renderInvitesPartial:adminHandler headers:headers body:body];
    }

    // Health partial
    if ([partialName isEqualToString:@"health"]) {
        return [self renderHealthPartial:adminHandler headers:headers body:body];
    }

    // Stats partial
    if ([partialName isEqualToString:@"stats"]) {
        return [self renderStatsPartial:adminHandler headers:headers body:body];
    }

    // Blobs partial
    if ([partialName isEqualToString:@"blobs"]) {
        return [self renderBlobsPartial:adminHandler headers:headers body:body];
    }

    // Identity partial
    if ([partialName isEqualToString:@"identity"]) {
        return [self renderIdentityPartial:adminHandler headers:headers body:body];
    }

    // Default to delegating to AdminUIHandler if no template-based partial is found
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

- (nullable NSString *)renderUsersPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    // Get users data from admin handler
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                              path:@"/admin/users"
                                                           headers:headers
                                                              body:body];
    if (!jsonResponse) {
        return nil;
    }

    NSData *jsonData = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!data) {
        return nil;
    }

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Users";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"users" context:context];
}

- (nullable NSString *)renderInvitesPartial:(PDSAdminHandler *)adminHandler
                                     headers:(NSDictionary *)headers
                                        body:(nullable NSData *)body {
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                              path:@"/admin/invites"
                                                           headers:headers
                                                              body:body];
    if (!jsonResponse) {
        return nil;
    }

    NSData *jsonData = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!data) {
        return nil;
    }

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Invite Codes";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"invites" context:context];
}

- (nullable NSString *)renderHealthPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                              path:@"/admin/health"
                                                           headers:headers
                                                              body:body];
    if (!jsonResponse) {
        return nil;
    }

    NSData *jsonData = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!data) {
        return nil;
    }

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Server Health";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"health" context:context];
}

- (nullable NSString *)renderStatsPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                              path:@"/admin/stats"
                                                           headers:headers
                                                              body:body];
    if (!jsonResponse) {
        return nil;
    }

    NSData *jsonData = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!data) {
        return nil;
    }

    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:data];
    context[@"title"] = @"Server Statistics";
    context[@"section"] = @"pds";

    return [self renderPartialWithTemplate:@"stats" context:context];
}

- (nullable NSString *)renderBlobsPartial:(PDSAdminHandler *)adminHandler
                                   headers:(NSDictionary *)headers
                                      body:(nullable NSData *)body {
    NSString *jsonResponse = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                              path:@"/admin/blobs"
                                                           headers:headers
                                                              body:body];
    if (!jsonResponse) {
        return nil;
    }

    NSData *jsonData = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (!data) {
        return nil;
    }

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

@end
