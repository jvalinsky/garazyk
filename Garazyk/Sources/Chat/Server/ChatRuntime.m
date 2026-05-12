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
    
    // Register Handlers
    // NOTE: Passing nil for dependencies that are PDS-specific for now.
    // STANDALONE CHAT will need its own Auth validation logic in Phase 3.
    [XrpcChatBskyActorPack registerWithDispatcher:self.dispatcher];

    [XrpcChatBskyConvoPack registerWithDispatcher:self.dispatcher
                                   appViewDatabase:(id<PDSQueryDatabase>)self.db
                                 serviceDatabase:nil
                                        jwtMinter:nil
                                  adminController:nil
                                     adminSecret:self.configuration.adminSecret];

    [XrpcChatBskyGroupPack registerWithDispatcher:self.dispatcher
                                   appViewDatabase:(id<PDSQueryDatabase>)self.db
                                        jwtMinter:nil
                                  adminController:nil];

    self.httpServer = [HttpServer serverWithHost:@"0.0.0.0" port:self.configuration.httpPort]; // Bind to all interfaces for Docker support

    // Configure auth manager with PDS URL for JWT signature verification
    if (self.configuration.pdsUrl.length > 0) {
        [ChatAuthManager sharedManager].pdsUrl = self.configuration.pdsUrl;
    }

    // Add health endpoint
    [self.httpServer addRoute:@"GET"
                        path:@"/_health"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                         response.statusCode = 200;
                         [response setBodyString:@"ok"];
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
