/*!
 @file AppViewLexiconEndpointGenerator.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.h"
#import "AppView/Server/Lexicon/AppViewGenericQueryHandler.h"
#import "AppView/Server/Lexicon/AppViewCustomQueryRegistry.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

NSErrorDomain const AppViewLexiconEndpointGeneratorErrorDomain =
    @"AppViewLexiconEndpointGenerator";

@interface AppViewLexiconEndpointGenerator ()

@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, strong) AppViewCustomQueryRegistry *customHandlers;
@property (nonatomic, strong) AppViewGenericQueryHandler *queryHandler;
@property (nonatomic, assign) NSUInteger registeredCount;

@end

@implementation AppViewLexiconEndpointGenerator

- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                      httpServer:(HttpServer *)httpServer
                 customHandlers:(AppViewCustomQueryRegistry *)customHandlers {
    self = [super init];
    if (self) {
        _registry = registry;
        _database = database;
        _httpServer = httpServer;
        _customHandlers = customHandlers;
        _queryHandler = [[AppViewGenericQueryHandler alloc]
            initWithRegistry:registry
                    database:database
             customHandlers:customHandlers];
        _registeredCount = 0;
    }
    return self;
}

- (BOOL)registerDynamicEndpointsWithError:(NSError **)error {
    NSArray<NSString *> *nsids = [self.registry loadedNSIDs];
    NSUInteger queryCount = 0;
    NSUInteger procedureCount = 0;
    NSUInteger recordCount = 0;
    NSUInteger skippedCount = 0;

    for (NSString *nsid in nsids) {
        ATProtoLexiconSchema *schema = [self.registry schemaForNSID:nsid];
        if (!schema) continue;

        // Skip app.bsky.* and com.atproto.* — these have domain-specific handlers
        if ([nsid hasPrefix:@"app.bsky."] ||
            [nsid hasPrefix:@"com.atproto."] ||
            [nsid hasPrefix:@"tools.ozone."]) {
            skippedCount++;
            continue;
        }

        NSError *schemaError = nil;
        if (![self registerEndpointsForSchema:schema error:&schemaError]) {
            PDS_LOG_WARN(@"[LexiconEndpointGenerator] Failed to register routes for %@: %@",
                         nsid, schemaError.localizedDescription ?: @"unknown");
            // Continue registering other schemas
        }
    }

    // Count registered types
    for (NSString *nsid in nsids) {
        if ([nsid hasPrefix:@"app.bsky."] ||
            [nsid hasPrefix:@"com.atproto."] ||
            [nsid hasPrefix:@"tools.ozone."]) continue;

        ATProtoLexiconSchema *schema = [self.registry schemaForNSID:nsid];
        if (!schema) continue;

        ATProtoLexiconDef *mainDef = [schema definitionForName:@"main"];
        if (mainDef) {
            switch (mainDef.type) {
                case ATProtoLexiconDefTypeQuery:
                    queryCount++;
                    break;
                case ATProtoLexiconDefTypeProcedure:
                    procedureCount++;
                    break;
                case ATProtoLexiconDefTypeRecord:
                    recordCount++;
                    break;
                default:
                    break;
            }
        }
    }

    PDS_LOG_INFO(@"[LexiconEndpointGenerator] Registered %lu dynamic endpoints "
                 @"(%lu queries, %lu procedures, %lu records). Skipped %lu domain-specific.",
                 (unsigned long)_registeredCount,
                 (unsigned long)queryCount,
                 (unsigned long)procedureCount,
                 (unsigned long)recordCount,
                 (unsigned long)skippedCount);

    return YES;
}

- (BOOL)registerEndpointsForSchema:(ATProtoLexiconSchema *)schema
                             error:(NSError **)error {
    if (!schema || !schema.nsid) {
        if (error) {
            *error = [NSError errorWithDomain:AppViewLexiconEndpointGeneratorErrorDomain
                                         code:400
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Schema or NSID is nil"
            }];
        }
        return NO;
    }

    NSString *nsid = schema.nsid;
    BOOL registeredAny = NO;

    // Check all definitions in the schema for query/procedure types
    for (NSString *defName in schema.defs) {
        ATProtoLexiconDef *def = schema.defs[defName];

        if (def.type == ATProtoLexiconDefTypeQuery) {
            NSString *endpointNSID = [defName isEqualToString:@"main"]
                ? nsid
                : [NSString stringWithFormat:@"%@#%@", nsid, defName];

            [self registerQueryRouteForNSID:endpointNSID];
            registeredAny = YES;
        }

        if (def.type == ATProtoLexiconDefTypeProcedure) {
            NSString *endpointNSID = [defName isEqualToString:@"main"]
                ? nsid
                : [NSString stringWithFormat:@"%@#%@", nsid, defName];

            [self registerProcedureRouteForNSID:endpointNSID];
            registeredAny = YES;
        }
    }

    return registeredAny;
}

- (void)registerQueryRouteForNSID:(NSString *)nsid {
    NSString *path = [NSString stringWithFormat:@"/xrpc/%@", nsid];
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"GET"
                        path:path
                     handler:^(HttpRequest *request, HttpResponse *response) {
        AppViewLexiconEndpointGenerator *strongSelf = weakSelf;
        if (!strongSelf) {
            response.statusCode = 500;
            [response setJsonBody:@{
                @"error": @"InternalError",
                @"message": @"Endpoint generator deallocated"
            }];
            return;
        }
        [strongSelf.queryHandler handleQuery:request
                                    response:response
                                       nsid:nsid];
    }];

    self.registeredCount++;
    PDS_LOG_DEBUG(@"[LexiconEndpointGenerator] Registered GET %@", path);
}

- (void)registerProcedureRouteForNSID:(NSString *)nsid {
    NSString *path = [NSString stringWithFormat:@"/xrpc/%@", nsid];
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"POST"
                        path:path
                     handler:^(HttpRequest *request, HttpResponse *response) {
        AppViewLexiconEndpointGenerator *strongSelf = weakSelf;
        if (!strongSelf) {
            response.statusCode = 500;
            [response setJsonBody:@{
                @"error": @"InternalError",
                @"message": @"Endpoint generator deallocated"
            }];
            return;
        }
        [strongSelf.queryHandler handleProcedure:request
                                       response:response
                                          nsid:nsid];
    }];

    self.registeredCount++;
    PDS_LOG_DEBUG(@"[LexiconEndpointGenerator] Registered POST %@", path);
}

- (NSUInteger)registeredEndpointCount {
    return _registeredCount;
}

- (AppViewGenericQueryHandler *)queryHandler {
    return _queryHandler;
}

@end
