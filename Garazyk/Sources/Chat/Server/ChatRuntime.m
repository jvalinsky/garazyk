#import "ChatRuntime.h"
#import "Config/ChatConfiguration.h"
#import "Config/ChatSchemaManager.h"
#import "Database/PDSDatabase.h"
#import "AppView/Services/ChatService.h"
#import "AppView/Services/ChatModerationService.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Debug/PDSLogger.h"

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
    PDS_LOG_INFO(@"Starting Chat service...");
    
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
    if (![self.db executeRawSQL:schemaSQL error:error]) {
        return NO;
    }
    
    // 3. Initialize Services
    self.chatService = [[ChatService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
    
    // 4. Initialize Networking
    self.dispatcher = [[XrpcDispatcher alloc] init];
    
    // Register Handlers
    // NOTE: Passing nil for dependencies that are PDS-specific for now. 
    // STANDALONE CHAT will need its own Auth validation logic in Phase 3.
    [XrpcChatBskyConvoPack registerWithDispatcher:self.dispatcher
                                   appViewDatabase:(id<PDSQueryDatabase>)self.db
                                        jwtMinter:nil // To be replaced with ChatAuthManager
                                  adminController:nil];
                                  
    [XrpcChatBskyActorPack registerWithDispatcher:self.dispatcher
                             chatModerationService:nil];
                             
    [XrpcChatBskyGroupPack registerWithDispatcher:self.dispatcher
                                   appViewDatabase:(id<PDSQueryDatabase>)self.db
                                        jwtMinter:nil
                                  adminController:nil];

    self.httpServer = [HttpServer serverWithPort:self.configuration.httpPort];
    
    // Add XRPC Route
    __weak typeof(self) weakSelf = self;
    [self.httpServer addRoute:@"*" path:@"/xrpc/*" handler:^(HttpRequest *request, HttpResponse *response) {
        [weakSelf.dispatcher handleRequest:request response:response];
    }];
    
    if (![self.httpServer startWithError:error]) return NO;
    
    self.isRunning = YES;
    PDS_LOG_INFO(@"Chat service started on port %lu", (unsigned long)self.httpPort);
    return YES;
}

- (NSUInteger)httpPort {
    return self.configuration.httpPort;
}

- (void)stop {
    PDS_LOG_INFO(@"Stopping Chat service...");
    [self.httpServer stop];
    [self.db close];
    self.isRunning = NO;
}

@end
