#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/Explore/ExploreHandler.h"
#import "App/PDSController.h"
#import "App/PDSConfiguration.h"
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
           @"  --log-components <c>  Comma-separated list of components to enable\n"
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
    NSString *logComponents = nil;

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
        } else if ([arg isEqualToString:@"--log-components"]) {
            if (i + 1 < args.count) {
                logComponents = args[++i];
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
        if (logComponents) {
            PDS_LOG_INFO(@"Enabled components: %@", logComponents);
        }
    }

    printf("Starting PDS server on port %ld...\n", (long)port);
    printf("Data directory: %s\n", [context.dataDir UTF8String]);
    printf("Press Ctrl+C to stop.\n");

    // Load configuration from file into shared PDSConfiguration
    if (context.configPath && [[NSFileManager defaultManager] fileExistsAtPath:context.configPath]) {
        NSError *configError = nil;
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        if (![config loadFromPath:context.configPath error:&configError]) {
            printf("Warning: Failed to load config: %s\n", [configError.localizedDescription UTF8String]);
        } else {
            printf("Loaded config from: %s\n", [context.configPath UTF8String]);
            printf("Server host: %s\n", [config.serverHost UTF8String]);
        }
    }

    if (!foreground) {
        printf("Running in background...\n");
    }

    // Apply logging overrides from CLI
    if (logLevel) {
        PDSLogLevel level = PDSLogLevelInfo;
        if ([logLevel isEqualToString:@"debug"]) level = PDSLogLevelDebug;
        else if ([logLevel isEqualToString:@"warn"]) level = PDSLogLevelWarn;
        else if ([logLevel isEqualToString:@"error"]) level = PDSLogLevelError;
        [PDSLogger sharedLogger].logLevel = level;
    }

    if (logComponents) {
        NSArray *componentsList = [logComponents componentsSeparatedByString:@","];
        NSMutableSet *componentSet = [NSMutableSet set];
        for (NSString *c in componentsList) {
            [componentSet addObject:[c stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        [PDSLogger sharedLogger].enabledComponents = componentSet;
    }

    // Initialize and start HTTP server
    HttpServer *httpServer = [HttpServer serverWithPort:(uint16_t)port];
    if (!httpServer) {
        printf("Failed to create HTTP server\n");
        return;
    }

    // Initialize PDS controller with specified data directory
    NSString *dataDir = context.dataDir;
    PDS_LOG_INFO_C(PDSLogComponentCLI, @"Initializing PDS controller with data directory: %@", dataDir);
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
    PDS_LOG_DEBUG_C(PDSLogComponentCLI, @"PDSCLIServeCommand: Set controller on explore handler: %@", controller);

    // Configure OAuth2 handler
    NSError *dbError = nil;
    PDSDatabase *serviceDB = [controller serviceDatabaseWithError:&dbError];
    if (!serviceDB) {
        printf("Failed to initialize service database: %s\n", dbError.localizedDescription.UTF8String);
        return;
    }
    OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:serviceDB];
    [oauthHandler registerRoutesWithServer:httpServer];
    PDS_LOG_DEBUG_C(PDSLogComponentCLI, @"PDSCLIServeCommand: Registered OAuth2 routes");

    // Configure XRPC dispatcher
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher controller:controller];
    
    [httpServer addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];
    
    [httpServer addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];
    PDS_LOG_DEBUG_C(PDSLogComponentCLI, @"PDSCLIServeCommand: Registered XRPC routes");

    // Register route handlers (using old routing system temporarily)
    [httpServer addHandlerForPath:@"/explore" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];

    // Register Health Check
    [httpServer addRoute:@"GET" path:@"/health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        [response setJsonBody:@{@"status": @"ok", @"version": @"0.1.0"}];
    }];

    // Register Server DID Document (did:web support)
    [httpServer addRoute:@"GET" path:@"/.well-known/did.json" handler:^(HttpRequest *request, HttpResponse *response) {
        // Construct a did:web DID document for this server
        // TODO: Get actual hostname from config
        NSString *hostname = @"localhost";
        if (port != 80 && port != 443) {
            hostname = [NSString stringWithFormat:@"localhost:%ld", (long)port];
        }
        
        NSString *did = [NSString stringWithFormat:@"did:web:%@", hostname];
        NSString *serviceEndpoint = [NSString stringWithFormat:@"http://%@", hostname];
        
        NSDictionary *doc = @{
            @"@context": @[@"https://www.w3.org/ns/did/v1"],
            @"id": did,
            @"service": @[@{
                @"id": @"#atproto_pds",
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": serviceEndpoint
            }],
            @"verificationMethod": @[],
            @"authentication": @[]
        };
        
        response.statusCode = 200;
        [response setJsonBody:doc];
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
