/*!
 @file AppViewGenericQueryHandler.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Lexicon/AppViewGenericQueryHandler.h"
#import "AppView/Server/Lexicon/AppViewCustomQueryRegistry.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"

NSErrorDomain const AppViewGenericQueryHandlerErrorDomain = @"AppViewGenericQueryHandler";

static NSInteger const kDefaultLimit = 50;
static NSInteger const kMaxLimit = 100;

@interface AppViewGenericQueryHandler ()

@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) AppViewCustomQueryRegistry *customHandlers;

@end

@implementation AppViewGenericQueryHandler

- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                  customHandlers:(AppViewCustomQueryRegistry *)customHandlers {
    self = [super init];
    if (self) {
        _registry = registry;
        _database = database;
        _customHandlers = customHandlers;
    }
    return self;
}

#pragma mark - Query Handler (GET)

- (void)handleQuery:(HttpRequest *)request
            response:(HttpResponse *)response
               nsid:(NSString *)nsid {
    // 1. Check custom handler registry
    id<AppViewLexiconQueryHandler> customHandler =
        [self.customHandlers handlerForNSID:nsid];
    if (customHandler) {
        [self dispatchToCustomHandler:customHandler
                              request:request
                             response:response
                                 nsid:nsid
                               isPost:NO];
        return;
    }

    // 2. Look up schema
    ATProtoLexiconSchema *schema = [self.registry schemaForNSID:nsid];
    if (!schema) {
        response.statusCode = 501;
        [response setJsonBody:@{
            @"error": @"NotImplemented",
            @"message": [NSString stringWithFormat:
                @"No lexicon schema loaded for %@", nsid]
        }];
        return;
    }

    // 3. Validate this is a query definition
    ATProtoLexiconDef *queryDef = [schema definitionForName:@"main"];
    if (!queryDef || queryDef.type != ATProtoLexiconDefTypeQuery) {
        // Check if there's a query definition elsewhere in the schema
        for (NSString *name in schema.defs) {
            ATProtoLexiconDef *def = schema.defs[name];
            if (def.type == ATProtoLexiconDefTypeQuery) {
                queryDef = def;
                break;
            }
        }
        if (!queryDef) {
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": [NSString stringWithFormat:
                    @"Lexicon %@ does not define a query method", nsid]
            }];
            return;
        }
    }

    // 4. Parse and validate query parameters
    NSDictionary<NSString *, NSString *> *params =
        [self parseQueryParamsFromRequest:request];

    // 5. Determine query type and execute
    NSString *uri = params[@"uri"];
    if (uri.length > 0) {
        [self handleSingleRecordQuery:uri response:response];
        return;
    }

    NSString *collection = params[@"collection"] ?: nsid;
    NSString *did = params[@"did"] ?: params[@"actor"];
    NSString *cursor = params[@"cursor"];
    NSInteger limit = [self parseLimitFromParams:params];

    [self handlePaginatedQuery:collection
                           did:did
                         limit:limit
                        cursor:cursor
                      response:response];
}

#pragma mark - Procedure Handler (POST)

- (void)handleProcedure:(HttpRequest *)request
                response:(HttpResponse *)response
                   nsid:(NSString *)nsid {
    // 1. Check custom handler registry
    id<AppViewLexiconQueryHandler> customHandler =
        [self.customHandlers handlerForNSID:nsid];
    if (customHandler) {
        [self dispatchToCustomHandler:customHandler
                              request:request
                             response:response
                                 nsid:nsid
                               isPost:YES];
        return;
    }

    // 2. Look up schema
    ATProtoLexiconSchema *schema = [self.registry schemaForNSID:nsid];
    if (!schema) {
        response.statusCode = 501;
        [response setJsonBody:@{
            @"error": @"NotImplemented",
            @"message": [NSString stringWithFormat:
                @"No lexicon schema loaded for %@", nsid]
        }];
        return;
    }

    // 3. Validate this is a procedure definition
    ATProtoLexiconDef *procDef = [schema definitionForName:@"main"];
    if (!procDef || procDef.type != ATProtoLexiconDefTypeProcedure) {
        for (NSString *name in schema.defs) {
            ATProtoLexiconDef *def = schema.defs[name];
            if (def.type == ATProtoLexiconDefTypeProcedure) {
                procDef = def;
                break;
            }
        }
        if (!procDef) {
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": [NSString stringWithFormat:
                    @"Lexicon %@ does not define a procedure method", nsid]
            }];
            return;
        }
    }

    // 4. Parse input body
    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Request body required for procedure"
        }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:bodyData
                                                         options:0
                                                           error:&jsonError];
    if (![input isKindOfClass:[NSDictionary class]]) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid JSON body"
        }];
        return;
    }

    // 5. For now, procedure endpoints without a custom handler return 501
    // Write proxying (Feature 3) will handle write procedures
    // Read procedures can be handled by custom handlers
    response.statusCode = 501;
    [response setJsonBody:@{
        @"error": @"NotImplemented",
        @"message": [NSString stringWithFormat:
            @"Procedure %@ requires a custom handler or write proxy", nsid]
    }];
}

#pragma mark - Custom Handler Dispatch

- (void)dispatchToCustomHandler:(id<AppViewLexiconQueryHandler>)handler
                        request:(HttpRequest *)request
                       response:(HttpResponse *)response
                           nsid:(NSString *)nsid
                         isPost:(BOOL)isPost {
    NSDictionary<NSString *, NSString *> *params =
        [self parseQueryParamsFromRequest:request];

    NSDictionary *input = nil;
    if (isPost) {
        NSData *bodyData = request.body;
        if (bodyData && bodyData.length > 0) {
            input = [NSJSONSerialization JSONObjectWithData:bodyData
                                                   options:0
                                                     error:nil];
            if (![input isKindOfClass:[NSDictionary class]]) {
                input = nil;
            }
        }
    }

    NSString *callerDID = nil;
    if ([handler respondsToSelector:@selector(requiresAuth)] &&
        [handler requiresAuth]) {
        callerDID = [self extractCallerDIDFromRequest:request];
        if (!callerDID) {
            response.statusCode = 401;
            [response setJsonBody:@{
                @"error": @"AuthenticationRequired",
                @"message": @"Authentication required for this endpoint"
            }];
            return;
        }
    }

    NSDictionary *result = nil;
    NSError *error = nil;
    BOOL success = [handler handleQueryWithParams:params
                                           input:input
                                        database:self.database
                                       callerDID:callerDID
                                          result:&result
                                           error:&error];

    if (!success) {
        NSInteger code = 500;
        NSString *errorName = @"InternalServerError";
        if (error) {
            if ([error.domain isEqualToString:AppViewCustomQueryRegistryErrorDomain] &&
                error.code == 404) {
                code = 404;
                errorName = @"NotFound";
            } else if (error.code == 400) {
                code = 400;
                errorName = @"InvalidRequest";
            }
        }
        response.statusCode = code;
        [response setJsonBody:@{
            @"error": errorName,
            @"message": error.localizedDescription ?: @"Handler failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

#pragma mark - Single Record Query

- (void)handleSingleRecordQuery:(NSString *)uri
                        response:(HttpResponse *)response {
    // Parse AT URI: at://<did>/<collection>/<rkey>
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid AT URI format (expected at://<did>/<collection>/<rkey>)"
        }];
        return;
    }

    NSString *did = components[2];
    NSString *collection = components[3];
    NSString *rkey = components[4];

    NSError *error = nil;
    NSDictionary *record = [self.database getRecordWithURI:uri
                                                       did:did
                                                collection:collection
                                                      rkey:rkey
                                                    error:&error];
    if (!record) {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"RecordNotFound",
            @"message": error.localizedDescription ?: @"Record not found"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:record];
}

#pragma mark - Paginated Query

- (void)handlePaginatedQuery:(NSString *)collection
                         did:(nullable NSString *)did
                       limit:(NSInteger)limit
                      cursor:(nullable NSString *)cursor
                    response:(HttpResponse *)response {
    NSError *error = nil;
    NSDictionary *result = [self.database listRecordsForCollection:collection
                                                              did:did
                                                            limit:limit
                                                           cursor:cursor
                                                            error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Query failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"records": @[] }];
}

#pragma mark - Helpers

- (NSDictionary<NSString *, NSString *> *)parseQueryParamsFromRequest:(HttpRequest *)request {
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];

    // Extract common query parameters
    NSArray<NSString *> *paramKeys = @[
        @"uri", @"collection", @"did", @"actor",
        @"cursor", @"limit", @"rkey",
        @"q", @"term"  // search parameters
    ];

    for (NSString *key in paramKeys) {
        NSString *value = [request queryParamForKey:key];
        if (value.length > 0) {
            params[key] = value;
        }
    }

    return [params copy];
}

- (NSInteger)parseLimitFromParams:(NSDictionary<NSString *, NSString *> *)params {
    NSString *limitStr = params[@"limit"];
    if (limitStr.length == 0) return kDefaultLimit;

    NSInteger limit = 0;
    [[NSScanner scannerWithString:limitStr] scanInteger:&limit];
    if (limit <= 0) return kDefaultLimit;
    return MIN(limit, kMaxLimit);
}

- (nullable NSString *)extractCallerDIDFromRequest:(HttpRequest *)request {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (![authHeader hasPrefix:@"Bearer "]) return nil;

    NSString *token = [authHeader substringFromIndex:7];
    if (token.length == 0) return nil;

    // Check if it's a direct DID (for dev/testing)
    for (NSString *prefix in @[@"did:plc:", @"did:web:"]) {
        if ([token hasPrefix:prefix]) return token;
    }

    // Attempt to parse as JWT and extract subject (DID)
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (jwt && jwt.payload.sub) {
        return jwt.payload.sub;
    }

    return nil;
}

@end
