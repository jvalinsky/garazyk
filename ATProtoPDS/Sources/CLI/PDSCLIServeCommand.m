#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/Explore/ExploreHandler.h"
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Auth/OAuth2Handler.h"

// Forward declaration for PDSAccountManager
@interface PDSAccountManager : NSObject
+ (NSArray *)listAccountsWithContext:(PDSCLICommandContext *)context
                             filter:(NSString *)filter
                              limit:(NSInteger)limit;
@end

// Category to access HttpServer's private requestHandler property
@interface HttpServer (Private)
@property (nonatomic, copy) void (^requestHandler)(HttpRequest *, HttpResponse *);
@end

@interface PDSCLIServeCommand : PDSBaseCommand
@end

@implementation PDSCLIServeCommand : PDSBaseCommand

- (NSString *)name {
    return @"serve";
}

- (NSString *)summary {
    return @"Start the PDS server";
}

- (NSString *)usage {
    return @"pds serve [options]";
}

- (NSString *)helpText {
    return @"Start the PDS HTTP server.\n\n"
           @"Options:\n"
           @"  --port <port>         Port to listen on (default: 2583)\n"
           @"  --data-dir <path>     Data directory (default: ./data)\n"
           @"  --config <path>       Config file path (default: ./config.json)\n"
           @"  --log-level <level>   Log level: debug, info, warn, error (default: info)\n"
           @"  --foreground          Run in foreground (don't daemonize)\n"
           @"  --help                Show this help";
}

- (NSArray<NSString *> *)aliases {
    return @[@"start", @"run"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSInteger port = 2583;
    BOOL foreground = NO;
    NSString *logLevel = @"info";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];

        if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 < args.count) {
                port = [args[++i] integerValue];
            }
        } else if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 < args.count) {
                context.dataDir = args[++i];
            }
        } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 < args.count) {
                context.configPath = args[++i];
            }
        } else if ([arg isEqualToString:@"--log-level"]) {
            if (i + 1 < args.count) {
                logLevel = args[++i];
            }
        } else if ([arg isEqualToString:@"--foreground"] || [arg isEqualToString:@"-f"]) {
            foreground = YES;
        } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            [context printInfo:[self helpText]];
            return;
        }
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Starting PDS server on port %ld", (long)port);
        PDS_LOG_INFO(@"Data directory: %@", context.dataDir);
        PDS_LOG_INFO(@"Config path: %@", context.configPath);
        PDS_LOG_INFO(@"Log level: %@", logLevel);
    }

    printf("Starting PDS server on port %ld...\n", (long)port);
    printf("Data directory: %s\n", [context.dataDir UTF8String]);
    printf("Press Ctrl+C to stop.\n");

    NSDictionary *config = [context loadConfig];
    if (config[@"pds"][@"hostname"]) {
        printf("PDS hostname: %s\n", [config[@"pds"][@"hostname"] UTF8String]);
    }

    if (!foreground) {
        printf("Running in background...\n");
    }

    // Initialize and start HTTP server
    HttpServer *httpServer = [HttpServer serverWithPort:(uint16_t)port];
    if (!httpServer) {
        printf("Failed to create HTTP server\n");
        return;
    }

    // Initialize PDS controller with specified data directory
    NSString *dataDir = [[NSURL fileURLWithPath:context.dataDir] path];
    NSLog(@"Initializing PDS controller with data directory: %@", dataDir);
    PDSController *controller = [[PDSController alloc] initWithDirectory:dataDir
                                                         serviceMaxSize:100
                                                       userDatabaseSize:30000];
    if (!controller) {
        printf("Failed to initialize PDS controller\n");
        return;
    }

    // Configure Explore handler
    ExploreHandler *exploreHandler = [ExploreHandler sharedHandler];
    [exploreHandler setController:controller];
    NSLog(@"PDSCLIServeCommand: Set controller on explore handler: %@", controller);

    // Configure OAuth2 handler
    NSError *dbError = nil;
    PDSDatabase *serviceDB = [controller serviceDatabaseWithError:&dbError];
    if (!serviceDB) {
        printf("Failed to initialize service database: %s\n", dbError.localizedDescription.UTF8String);
        return;
    }
    OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:serviceDB];
    [oauthHandler registerRoutesWithServer:httpServer];
    NSLog(@"PDSCLIServeCommand: Registered OAuth2 routes");

    // Configure XRPC dispatcher
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher controller:controller];
    
    [httpServer addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];
    
    [httpServer addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];
    NSLog(@"PDSCLIServeCommand: Registered XRPC routes");

    // Register route handlers (using old routing system temporarily)
    [httpServer addHandlerForPath:@"/explore" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];

    // Add API endpoints
    [httpServer addHandlerForPath:@"/explore/api/accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![request.methodString isEqualToString:@"GET"]) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setJsonBody:@{@"error": @"Method not allowed"}];
            return;
        }

        // Use the same database access as CLI account commands
        NSError *error = nil;
        NSArray *accounts = [PDSAccountManager listAccountsWithContext:context
                                                               filter:nil
                                                                limit:1000];
        NSLog(@"PDSCLIServeCommand API: Found %lu accounts", (unsigned long)accounts.count);
        if (!accounts) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"Failed to load accounts"}];
            return;
        }

        // Convert accounts to JSON-friendly format
        NSMutableArray *accountData = [NSMutableArray array];
        for (PDSDatabaseAccount *account in accounts) {
            [accountData addObject:@{
                @"did": account.did ?: @"",
                @"handle": account.handle ?: @"",
                @"createdAt": @(account.createdAt),
                @"updatedAt": @(account.updatedAt)
            }];
        }

        [response setJsonBody:@{
            @"accounts": accountData,
            @"count": @(accountData.count)
        }];
    }];

    // Start HTTP server
    NSError *serverError = nil;
    if (![httpServer startWithError:&serverError]) {
        printf("Failed to start HTTP server: %s\n", [serverError.localizedDescription UTF8String]);
        return;
    }

    printf("HTTP server started successfully on port %ld\n", (long)port);
    printf("Web interface available at: http://localhost:%ld/explore\n", (long)port);

    if (!foreground) {
        printf("Running in background...\n");
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"PDS server started successfully");
    }

    // Setup signal handling for graceful shutdown
    __block volatile sig_atomic_t shouldExit = 0;

    dispatch_source_t intSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(intSource, ^{
        shouldExit = 1;
        printf("\nShutting down server...\n");
        [httpServer stop];
        // Give async operations 2 seconds to complete before forcing exit
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            printf("Forced exit after timeout.\n");
            exit(0);
        });
    });
    dispatch_resume(intSource);

    dispatch_source_t termSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(termSource, ^{
        shouldExit = 1;
        printf("\nShutting down server...\n");
        [httpServer stop];
        // Give async operations 2 seconds to complete before forcing exit
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            printf("Forced exit after timeout.\n");
            exit(0);
        });
    });
    dispatch_resume(termSource);

    // Keep server running
    if (foreground) {
        printf("Server running in foreground. Press Ctrl+C to stop.\n");
    } else {
        printf("Server started successfully. Running in background mode.\n");
        printf("Use 'kill %d' or Ctrl+C to stop.\n", getpid());
    }

    // Run the main run loop to keep the server alive
    // This properly handles network events
    while (!shouldExit && httpServer.running) {
        @autoreleasepool {
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }
    }

    [httpServer stop];
    printf("Server stopped.\n");
}

@end

#pragma mark - Register

@interface PDSserveCommandRegistrar : NSObject
@end

@implementation PDSserveCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLIServeCommand command]];
}

@end
