#import "GermRuntime.h"
#import "Germ/Server/Config/GermMailboxSchemaManager.h"
#import "Germ/Server/Services/GermMailboxService.h"
#import "Germ/Server/Identity/GermIdentityService.h"
#import "Germ/Server/XrpcGermMailboxPack.h"
#import "Germ/Server/XrpcGermIdentityPack.h"
#import "Chat/Server/ChatAuthManager.h"
#import "Database/PDSDatabase.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Debug/PDSLogger.h"

static const uint16_t kGermDefaultPort = 8082;

@interface GermRuntime ()
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) GermMailboxService *mailboxService;
@property (nonatomic, strong) GermIdentityService *identityService;
@property (nonatomic, strong) ChatAuthManager *authManager;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation GermRuntime

+ (instancetype)sharedRuntime {
    static GermRuntime *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GermRuntime alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isRunning = NO;
    }
    return self;
}

- (BOOL)startWithDataDirectory:(NSString *)dataDirectory
                      port:(uint16_t)port
                     error:(NSError **)error {
    PDS_LOG_INFO(@"Starting Germ E2EE mailbox service...");

    // 1. Ensure data directory exists
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dataDirectory]) {
        [fm createDirectoryAtPath:dataDirectory
     withIntermediateDirectories:YES
                      attributes:nil
                           error:error];
        if (*error) return NO;
    }

    // 2. Initialize database
    NSString *dbPath = [dataDirectory stringByAppendingPathComponent:@"germ-mailbox.db"];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![self.db openWithError:error]) return NO;

    // Apply schema
    NSString *schemaSQL = [[GermMailboxSchemaManager sharedManager] mailboxSchemaSQL];
    if (![self.db executeRawSQL:schemaSQL error:error]) {
        return NO;
    }

    // 3. Initialize services
    self.mailboxService = [[GermMailboxService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
    self.identityService = [[GermIdentityService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
    self.authManager = [ChatAuthManager sharedManager];

    // 4. Initialize networking
    self.dispatcher = [[XrpcDispatcher alloc] init];

    // Register XRPC handlers
    XrpcGermMailboxPack *mailboxPack = [[XrpcGermMailboxPack alloc]
        initWithMailboxService:self.mailboxService
                   authManager:self.authManager];
    [mailboxPack registerHandlersWithDispatcher:self.dispatcher];

    XrpcGermIdentityPack *identityPack = [[XrpcGermIdentityPack alloc]
        initWithIdentityService:self.identityService
                   authManager:self.authManager];
    [identityPack registerHandlersWithDispatcher:self.dispatcher];

    // 5. Start HTTP server (bind to localhost — Germ mailbox must be
    //    accessed through PDS proxy, not directly exposed)
    if (port == 0) port = kGermDefaultPort;
    self.httpServer = [HttpServer serverWithHost:@"127.0.0.1" port:port];

    // Health endpoint
    [self.httpServer addRoute:@"GET"
                        path:@"/_health"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        [response setBodyString:@"ok"];
    }];

    // XRPC route
    __weak typeof(self) weakSelf = self;
    [self.httpServer addRoute:@"*"
                        path:@"/xrpc/*"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        [weakSelf.dispatcher handleRequest:request response:response];
    }];

    if (![self.httpServer startWithError:error]) {
        PDS_LOG_ERROR(@"Failed to start Germ HTTP server on port %d: %@", port, *error ?: @"unknown");
        return NO;
    }

    self.isRunning = YES;
    PDS_LOG_INFO(@"Germ E2EE mailbox service started on port %d", port);
    return YES;
}

- (void)stop {
    if (!self.isRunning) return;

    [self.httpServer stop];
    [self.db close];

    self.isRunning = NO;
    PDS_LOG_INFO(@"Germ E2EE mailbox service stopped");
}

@end
