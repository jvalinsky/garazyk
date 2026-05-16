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
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcRoutePackServices.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"

@interface ChatRuntime ()
@property (nonatomic, strong, readwrite) ChatConfiguration *configuration;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) ChatService *chatService;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation ChatRuntime

+ (instancetype)sharedRuntime {
    static ChatRuntime *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ChatRuntime alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _configuration = [ChatConfiguration defaultConfiguration];
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
    NSString *schemaSQL = [[ChatSchemaManager sharedManager] chatSchemaSQL];
    if (![self.db executeParameterizedUpdate:schemaSQL params:@[] error:error]) {
        return NO;
    }
    
    // 3. Initialize Services
    self.chatService = [[ChatService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
    
    // 4. Initialize Networking
    self.dispatcher = [[XrpcDispatcher alloc] init];
    
    // Create services bag for route packs
    // NOTE: Standalone chat uses its own configuration and database
    XrpcRoutePackServiceBag *bag =
 [[XrpcRoutePackServiceBag alloc] initWithDispatcher:self.dispatcher
                                                                             jwtMinter:nil
                                                                       adminController:nil
                                                                          configuration:nil
                                                                            adminSecret:self.configuration.adminSecret
                                                                      serviceDatabases:nil
                                                                      userDatabasePool:nil
                                                                            rateLimiter:nil];
    bag.appViewDatabase = (id<PDSQueryDatabase>)self.db;

    // Register Handlers
    [XrpcChatBskyActorPack registerWithDispatcher:self.dispatcher services:bag];
    [XrpcChatBskyConvoPack registerWithDispatcher:self.dispatcher services:bag];
    [XrpcChatBskyGroupPack registerWithDispatcher:self.dispatcher services:bag];

    self.httpServer = [HttpServer serverWithHost:@"0.0.0.0" port:self.configuration.httpPort]; // Bind to all interfaces for Docker support

    // Configure auth manager with PDS URL and service DID for JWT verification
    if (self.configuration.pdsUrl.length > 0) {
        [ChatAuthManager sharedManager].pdsUrl = self.configuration.pdsUrl;
    }
    // Set the service DID for audience validation in service auth JWTs.
    // The aud claim must match this service's DID (with #bsky_chat fragment).
    [ChatAuthManager sharedManager].serviceDID = self.configuration.serviceDID;

    // Add health endpoint
    [self.httpServer addRoute:@"GET"
                        path:@"/_health"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                         response.statusCode = 200;
                         [response setBodyString:@"ok"];
                     }];

    // Root endpoint - display ASCII art
    [self.httpServer addRoute:@"GET"
                        path:@"/"
                     handler:^(HttpRequest *request, HttpResponse *response) {
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
                     handler:^(HttpRequest *request, HttpResponse *response) {
                         ChatConfiguration *c = self.configuration;
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
    [self.httpServer addRoute:@"*" path:@"/xrpc/*" handler:^(HttpRequest *request, HttpResponse *response) {
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
