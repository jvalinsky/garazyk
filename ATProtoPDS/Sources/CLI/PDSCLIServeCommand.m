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

    // Load PDSConfiguration from config file if provided
    PDSConfiguration *pdsConfig = [PDSConfiguration sharedConfiguration];
    NSLog(@"Config path: %@, exists: %d", context.configPath, [[NSFileManager defaultManager] fileExistsAtPath:context.configPath]);
    if (context.configPath && [[NSFileManager defaultManager] fileExistsAtPath:context.configPath]) {
        NSError *configError = nil;
        if ([pdsConfig loadFromPath:context.configPath error:&configError]) {
            NSLog(@"Loaded configuration from: %@", context.configPath);
            NSLog(@"  PLC URL: %@", pdsConfig.plcURL);
            NSLog(@"  Skip PLC operations: %@", pdsConfig.debugSkipPlcOperations ? @"YES" : @"NO");
        } else {
            NSLog(@"Warning: Failed to load configuration: %@", configError.localizedDescription);
        }
    } else {
        NSLog(@"No config file found or configPath not set");
    }

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
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        if ([request.methodString isEqualToString:@"OPTIONS"]) {
            response.statusCode = 204;
            return;
        }
        [dispatcher handleRequest:request response:response];
    }];
    
    [httpServer addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Content-Type, Authorization" forKey:@"Access-Control-Allow-Headers"];
        if ([request.methodString isEqualToString:@"OPTIONS"]) {
            response.statusCode = 204;
            return;
        }
        [dispatcher handleRequest:request response:response];
    }];
    NSLog(@"PDSCLIServeCommand: Registered XRPC routes");

    // Register route handlers (using old routing system temporarily)
    [httpServer addHandlerForPath:@"/explore" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [exploreHandler handleRequest:request response:response];
    }];

    // Well-known endpoint for ATProto DID discovery
    // Returns the DID for the handle in the Host header
    [httpServer addHandlerForPath:@"/.well-known/atproto-did" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"text/plain" forKey:@"Content-Type"];
        
        // Get the Host header to determine which user's DID to return
        NSString *host = request.headers[@"Host"] ?: request.headers[@"host"];
        NSString *hostname = [[host componentsSeparatedByString:@":"] firstObject]; // Remove port if present
        
        // For subdomain-based DIDs: alice.september.exe.xyz -> did:web:alice.september.exe.xyz
        NSString *did = [NSString stringWithFormat:@"did:web:%@", hostname];
        
        response.statusCode = HttpStatusOK;
        [response setBody:[did dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    // DID document endpoint for did:web resolution (hostname-level)
    // did:web:alice.september.exe.xyz -> https://alice.september.exe.xyz/.well-known/did.json
    [httpServer addHandlerForPath:@"/.well-known/did.json" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"application/json" forKey:@"Content-Type"];
        
        // Get the Host header to determine which user's DID document to return
        NSString *host = request.headers[@"Host"] ?: request.headers[@"host"];
        NSString *hostname = [[host componentsSeparatedByString:@":"] firstObject]; // Remove port if present
        
        // The DID is simply did:web:<hostname>
        NSString *did = [NSString stringWithFormat:@"did:web:%@", hostname];
        
        // Extract username from subdomain (e.g., alice.september.exe.xyz -> alice)
        // The handle is the full hostname
        NSString *handle = hostname;
        
        // TODO: Look up the user's signing key from the database
        // For now, we generate a placeholder verification method
        // In production, this should come from ActorStore.signingKeyWithError:
        
        // Return DID document per ATProto spec
        // https://atproto.com/specs/did
        NSDictionary *didDoc = @{
            @"@context": @[@"https://www.w3.org/ns/did/v1"],
            @"id": did,
            @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
            @"verificationMethod": @[
                @{
                    @"id": [NSString stringWithFormat:@"%@#atproto", did],
                    @"type": @"Multikey",
                    @"controller": did,
                    // TODO: Replace with actual public key from user's ActorStore
                    // This is a placeholder P-256 key - users need real keys generated on account creation
                    @"publicKeyMultibase": @"zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU2169"
                }
            ],
            @"service": @[@{
                @"id": [NSString stringWithFormat:@"%@#atproto_pds", did],
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": @"https://september.exe.xyz"
            }]
        };
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:didDoc];
    }];
    
    // Legacy path-based DID document endpoint (for backwards compatibility)
    // did:web:september.exe.xyz:user:alice -> https://september.exe.xyz/user/alice/did.json
    // NOTE: ATProto does NOT support path-based did:web, but we keep this for debugging
    [httpServer addHandlerForPath:@"/user" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        
        // Parse path like /user/alice/did.json
        NSString *path = request.path;
        if (![path hasSuffix:@"/did.json"]) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"Not Found", @"note": @"ATProto requires hostname-level did:web DIDs, not path-based"}];
            return;
        }
        
        // Extract username from /user/<username>/did.json
        NSArray *parts = [path componentsSeparatedByString:@"/"];
        if (parts.count < 3) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"Not Found"}];
            return;
        }
        NSString *username = parts[2];
        
        // Return the CORRECT subdomain-based DID (not path-based)
        NSString *did = [NSString stringWithFormat:@"did:web:%@.september.exe.xyz", username];
        NSString *handle = [NSString stringWithFormat:@"%@.september.exe.xyz", username];
        
        // Return DID document with proper format
        NSDictionary *didDoc = @{
            @"@context": @[@"https://www.w3.org/ns/did/v1"],
            @"id": did,
            @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
            @"verificationMethod": @[
                @{
                    @"id": [NSString stringWithFormat:@"%@#atproto", did],
                    @"type": @"Multikey",
                    @"controller": did,
                    @"publicKeyMultibase": @"zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU2169"
                }
            ],
            @"service": @[@{
                @"id": [NSString stringWithFormat:@"%@#atproto_pds", did],
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": @"https://september.exe.xyz"
            }]
        };
        
        [response setHeader:@"application/json" forKey:@"Content-Type"];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:didDoc];
    }];

    // Health check endpoint
    [httpServer addHandlerForPath:@"/xrpc/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        if ([request.methodString isEqualToString:@"OPTIONS"]) {
            response.statusCode = 204;
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"version": @"0.1.0"}];
    }];

    // Root handler
    [httpServer addHandlerForPath:@"/" handler:^(HttpRequest *request, HttpResponse *response) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        // Redirect to explore UI or return server info
        if ([request.path isEqualToString:@"/"]) {
            response.statusCode = 302;
            [response setHeader:@"/explore/" forKey:@"Location"];
        }
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
