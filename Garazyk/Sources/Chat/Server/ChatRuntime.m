// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ChatRuntime.h"
#import "Config/ChatConfiguration.h"
#import "Config/ChatSchemaManager.h"
#import "Database/PDSDatabase.h"
#import "Chat/Server/Services/ChatService.h"
#import "Chat/Server/Services/ChatModerationService.h"
#import "Chat/Server/ChatAuthManager.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcRoutePackServices.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Core/DID.h"
#import "Debug/GZLogger.h"

@interface GZChatRuntime ()
@property (nonatomic, strong, readwrite) PDSChatConfiguration *configuration;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) PDSChatService *chatService;
@property (nonatomic, strong) ATProtoHttpServer *httpServer;
@property (nonatomic, strong) ATProtoXrpcDispatcher *dispatcher;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation GZChatRuntime

+ (instancetype)sharedRuntime {
    static GZChatRuntime *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GZChatRuntime alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _configuration = [PDSChatConfiguration defaultConfiguration];
    }
    return self;
}

- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error {
    return [self.configuration loadFromFile:path error:error];
}

- (void)loadConfigurationFromEnvironment {
    [self.configuration loadFromEnvironment];
}

- (BOOL)startWithError:(NSError **)error {
    GZ_LOG_INFO(@"Starting Chat service...");
    
    // 1. Initialize Data Directory
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.configuration.dataDirectory]) {
        [fm createDirectoryAtPath:self.configuration.dataDirectory withIntermediateDirectories:YES attributes:nil error:error];
    }
    
    // 2. Initialize Database
    NSString *dbPath = [self.configuration.dataDirectory stringByAppendingPathComponent:@"chat.db"];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![self.db openWithError:error]) return NO;
    
    // Initialize Schema
    NSString *schemaSQL = [[PDSChatSchemaManager sharedManager] chatSchemaSQL];
    if (![self.db executeParameterizedUpdate:schemaSQL params:@[] error:error]) {
        return NO;
    }
    
    // 3. Initialize Services
    self.chatService = [[PDSChatService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
    
    // 4. Initialize Networking
    self.dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    
    // Create services bag for route packs
    // NOTE: Standalone chat uses its own configuration and database
    ATProtoXrpcRoutePackServiceBag *bag =
 [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:self.dispatcher
                                                                             jwtMinter:nil
                                                                       adminController:nil
                                                                          configuration:nil
                                                                            adminSecret:self.configuration.adminSecret
                                                                      serviceDatabases:nil
                                                                      userDatabasePool:nil
                                                                            rateLimiter:nil];
    bag.appViewDatabase = (id<PDSQueryDatabase>)self.db;

    // Register Handlers
    [ATProtoXrpcChatBskyActorPack registerWithDispatcher:self.dispatcher services:bag];
    [ATProtoXrpcChatBskyConvoPack registerWithDispatcher:self.dispatcher services:bag];
    [ATProtoXrpcChatBskyGroupPack registerWithDispatcher:self.dispatcher services:bag];

    self.httpServer = [ATProtoHttpServer serverWithHost:@"0.0.0.0" port:self.configuration.httpPort]; // Bind to all interfaces for Docker support

    // Configure auth manager with PDS URL and service DID for ATProtoJWT verification
    if (self.configuration.pdsUrl.length > 0) {
        [PDSChatAuthManager sharedManager].pdsUrl = self.configuration.pdsUrl;
    }
    
    // Propagate PLC URL to the shared DID resolver
    if (self.configuration.plcUrl.length > 0) {
        [ATProtoDIDResolver sharedResolver].plcURL = self.configuration.plcUrl;
    }
    
    // Set the service DID for audience validation in service auth JWTs.
    // The aud claim must match this service's DID (with #bsky_chat fragment).
    [PDSChatAuthManager sharedManager].serviceDID = self.configuration.serviceDID;

    // Add health endpoint
    [self.httpServer addRoute:@"GET"
                        path:@"/_health"
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         response.statusCode = 200;
                         [response setBodyString:@"ok"];
                     }];

    // Admin: list conversations (privacy-safe metadata only)
    [self.httpServer addRoute:@"GET"
                        path:@"/_admin/convos"
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *err = nil;
        NSArray *convos = [self.chatService listAllConversationsWithLimit:25 cursor:cursor error:&err];
        if (convos) {
            // Privacy-safe: strip message bodies from lastMessage
            NSMutableArray *safe = [NSMutableArray arrayWithCapacity:convos.count];
            for (NSDictionary *c in convos) {
                NSMutableDictionary *mc = [c mutableCopy];
                id lastMsg = mc[@"lastMessage"];
                if ([lastMsg isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *safeMsg = [(NSDictionary *)lastMsg mutableCopy];
                    [safeMsg removeObjectForKey:@"text"];
                    [safeMsg removeObjectForKey:@"ciphertext"];
                    mc[@"lastMessage"] = safeMsg;
                }
                [safe addObject:mc];
            }
            response.statusCode = 200;
            [response setJsonBody:@{@"convos": safe, @"cursor": cursor ?: @""}];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"convos_failed", @"message": err.localizedDescription ?: @"unknown"}];
        }
    }];

    // Admin: get messages for a conversation (privacy-safe: metadata only)
    [self.httpServer addRoute:@"GET"
                        path:@"/_admin/messages"
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *convoID = [request queryParamForKey:@"convoId"];
        if (convoID.length == 0) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"convo_id_required"}];
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *err = nil;
        NSArray *msgs = [self.chatService getMessagesForConversation:convoID limit:50 cursor:cursor error:&err];
        if (msgs) {
            // Privacy-safe: strip text/ciphertext, keep only metadata
            NSMutableArray *safe = [NSMutableArray arrayWithCapacity:msgs.count];
            for (NSDictionary *m in msgs) {
                NSMutableDictionary *mm = [m mutableCopy];
                [mm removeObjectForKey:@"text"];
                [mm removeObjectForKey:@"ciphertext"];
                [safe addObject:mm];
            }
            response.statusCode = 200;
            [response setJsonBody:@{@"messages": safe, @"cursor": cursor ?: @""}];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"messages_failed", @"message": err.localizedDescription ?: @"unknown"}];
        }
    }];

    // Root endpoint - display ASCII art
    [self.httpServer addRoute:@"GET"
                        path:@"/"
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         response.statusCode = 200;
                         response.contentType = @"text/plain; charset=utf-8";
                         [response setBodyString:@".|'''.|                                            '         '||                .   \n"
                                                  " ||..  '  .... ... ... ..    ....  .. ...    ....       ....   || ..    ....   .||.  \n"
                                                  "  ''|||.   '|.  |   ||' '' .|...||  ||  ||  '' .||    .|   ''  ||' ||  '' .||   ||   \n"
                                                  ".     '||   '|.|    ||     ||       ||  ||  .|' ||    ||       ||  ||  .|' ||   ||   \n"
                                                  "|'....|'     '|    .||.     '|...' .||. ||. '|..'|'    '|...' .||. ||. '|..'|'  '|.' \n"
                                                  "          .. |                                                                       \n"
                                                  "           ''                                                                        "];
                     }];

    // DID document endpoint (did:web support)
    [self.httpServer addRoute:@"GET"
                        path:@"/.well-known/did.json"
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                         PDSChatConfiguration *c = self.configuration;
                         NSString *did = c.serviceDID;
                         NSString *scheme = [c.serviceDomain containsString:@":"] ? @"http" : @"https";
                         NSString *endpoint = c.serviceDomain
                             ? [NSString stringWithFormat:@"%@://%@", scheme, c.serviceDomain]
                             : [NSString stringWithFormat:@"http://localhost:%lu", (unsigned long)c.httpPort];
                         NSDictionary *doc = @{
                             @"@context": @[@"https://www.w3.org/ns/did/v1"],
                             @"id": did,
                             @"service": @[@{
                                 @"id": @"#bsky_chat",
                                 @"type": @"BskyChatService",
                                 @"serviceEndpoint": endpoint
                             }]
                         };
                         response.statusCode = 200;
                         [response setJsonBody:doc];
                     }];

    // Add XRPC Route
    __weak typeof(self) weakSelf = self;
    [self.httpServer addRoute:@"*" path:@"/xrpc/:method" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf.dispatcher handleRequest:request response:response];
    }];
    
    if (![self.httpServer startWithError:error]) return NO;
    
    self.isRunning = YES;
    GZ_LOG_INFO(@"Chat service started on port %lu", (unsigned long)self.httpPort);
    return YES;
}

- (NSUInteger)httpPort {
    return self.configuration.httpPort;
}

- (void)stop {
    GZ_LOG_INFO(@"Stopping Chat service...");
    [self.httpServer stop];
    [self.db close];
    self.isRunning = NO;
}

@end
