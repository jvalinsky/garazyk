#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/PDSHttpServerBuilder.h"
#import "App/PDSController.h"
#import "Core/CID.h"
#import "App/PDSConfiguration.h"
#import "Auth/JWT.h"
#import "Sync/SubscribeReposHandler.h"
#import "Admin/PDSAdminAuth.h"

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
    return @[@"start", @"run", @"server"];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
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
            return 0;
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
            // Update port from config if not overridden by CLI later
            if (config.serverPort > 0) {
                port = config.serverPort;
            }
        }
    }

    // Apply CLI overrides again to Ensure they take precedence over config
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:@"--port"] || [args[i] isEqualToString:@"-p"]) {
            if (i + 1 < args.count) {
                port = [args[++i] integerValue];
            }
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
        return 0;
    }

    // Initialize PDS controller with specified data directory
    NSString *dataDir = context.dataDir;
    PDS_LOG_INFO_C(PDSLogComponentCLI, @"Initializing PDS controller with data directory: %@", dataDir);
    PDSController *controller = [[PDSController alloc] initWithDirectory:dataDir
                                                         serviceMaxSize:100
                                                       userDatabaseSize:30000];
    if (!controller) {
        printf("Failed to initialize PDS controller\n");
        return 0;
    }
    
    // Ensure PDSAdminAuth has data directory for admin DID persistence
    [PDSAdminAuth sharedAuth].dataDirectory = dataDir;

    SubscribeReposHandler *subscribeReposHandler = [[SubscribeReposHandler alloc] initWithServiceDatabases:controller.serviceDatabases];

    PDSHttpServerBuilder *serverBuilder = [[PDSHttpServerBuilder alloc] initWithConfiguration:[PDSConfiguration sharedConfiguration]];
    serverBuilder.port = (NSUInteger)port;
    serverBuilder.controller = controller;
    serverBuilder.jwtMinter = controller.jwtMinter;
    serverBuilder.serviceDatabases = controller.serviceDatabases;
    serverBuilder.subscribeReposHandler = subscribeReposHandler;
    serverBuilder.issuer = [NSString stringWithFormat:@"https://localhost:%ld", (long)port];

    NSError *builderError = nil;
    if (![serverBuilder configureServer:httpServer error:&builderError]) {
        printf("Failed to configure HTTP server routes: %s\n", builderError.localizedDescription.UTF8String);
        return 0;
    }
    PDS_LOG_DEBUG_C(PDSLogComponentCLI, @"PDSCLIServeCommand: Registered routes via PDSHttpServerBuilder");

    // Register Health Check
    [httpServer addRoute:@"GET" path:@"/health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        [response setJsonBody:@{@"status": @"ok", @"version": @"0.1.0"}];
    }];

    [httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        [response setJsonBody:@{@"status": @"ok"}];
    }];

    [httpServer addRoute:@"GET" path:@"/robots.txt" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"text/plain";
        [response setBodyString:@"User-agent: *\nDisallow: /"];
    }];

    [httpServer addRoute:@"GET" path:@"/account/" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"text/html";
        NSString *html = @"<!DOCTYPE html><html><head><title>ATProto Account</title></head><body><h1>Account Management</h1><p>Account web UI coming soon.</p></body></html>";
        [response setBodyString:html];
    }];

    // Register Server DID Document (did:web support)
    [httpServer addRoute:@"GET" path:@"/.well-known/did.json" handler:^(HttpRequest *request, HttpResponse *response) {
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        NSString *host = config.serverHost ?: @"localhost";
        if ([host isEqualToString:@"0.0.0.0"]) {
            host = @"localhost";
        }

        NSUInteger didPort = port;
        NSString *didHost = host;
        if (didPort != 80 && didPort != 443) {
            didHost = [NSString stringWithFormat:@"%@%%3A%lu", host, (unsigned long)didPort];
        }

        NSString *did = [NSString stringWithFormat:@"did:web:%@", didHost];
        NSString *scheme = (didPort == 443) ? @"https" : @"http";
        NSString *serviceEndpoint = nil;
        if (didPort == 80 || didPort == 443) {
            serviceEndpoint = [NSString stringWithFormat:@"%@://%@", scheme, host];
        } else {
            serviceEndpoint = [NSString stringWithFormat:@"%@://%@:%lu", scheme, host, (unsigned long)didPort];
        }

        NSString *publicKeyMultibase = nil;
        NSData *publicKey = controller.jwtMinter.publicKey;
        if (publicKey.length > 0) {
            publicKeyMultibase = [NSString stringWithFormat:@"b%@", [CID base32Encode:publicKey]];
        }

        NSMutableDictionary *doc = [NSMutableDictionary dictionary];
        doc[@"@context"] = @[@"https://www.w3.org/ns/did/v1"];
        doc[@"id"] = did;
        doc[@"service"] = @[@{
            @"id": @"#atproto_pds",
            @"type": @"AtprotoPersonalDataServer",
            @"serviceEndpoint": serviceEndpoint
        }];
        if (publicKeyMultibase) {
            NSDictionary *verificationMethod = @{
                @"id": [NSString stringWithFormat:@"%@#atproto", did],
                @"type": @"Multikey",
                @"controller": did,
                @"publicKeyMultibase": publicKeyMultibase
            };
            doc[@"verificationMethod"] = @[verificationMethod];
            doc[@"authentication"] = @[verificationMethod[@"id"]];
        } else {
            doc[@"verificationMethod"] = @[];
            doc[@"authentication"] = @[];
        }
        
        response.statusCode = 200;
        [response setJsonBody:doc];
    }];

    // Start HTTP server
    NSError *serverError = nil;
    if (![httpServer startWithError:&serverError]) {
        printf("Failed to start HTTP server: %s\n", [serverError.localizedDescription UTF8String]);
        return 0;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *displayHost = config.serverHost ?: @"localhost";
    if ([displayHost isEqualToString:@"0.0.0.0"]) {
        displayHost = @"localhost";
    }

    printf("HTTP server started successfully on port %ld\n", (long)port);
    printf("Web interface available at: http://%s:%ld/\n", [displayHost UTF8String], (long)port);

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
        [subscribeReposHandler stop];
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
        [subscribeReposHandler stop];
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

    [subscribeReposHandler stop];
    [httpServer stop];
    printf("Server stopped.\n");
    return 0;
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
