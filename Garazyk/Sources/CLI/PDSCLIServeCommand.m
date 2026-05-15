// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Admin/PDSAdminAuth.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/ATProtoHttpServerBuilder.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "PDSCLIDefinitions.h"
#import "Services/PDS/PDSRelayService.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Compat/PlatformShims/SignalHandling/PDSSignalManager.h"

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
  return @"kaszlak serve [options]";
}

- (NSString *)helpText {
  return @"Start the PDS HTTP server.\n\n"
         @"Usage: kaszlak serve [options]\n\n"
         @"Options:\n"
         @"  --port <port>         Port to listen on (default: 2583)\n"
         @"  --data-dir <path>     Data directory\n"
         @"  --config <path>       Config file path (default: ./config.json)\n"
         @"  --log-level <level>   Log level: debug, info, warn, error "
         @"(default: info)\n"
         @"  --log-components <c>  Comma-separated list of components to "
         @"enable\n"
         @"  --foreground          Run in foreground (don't daemonize)\n"
         @"  --help                Show this help\n\n"
         @"Examples:\n"
         @"  kaszlak serve                           # Start server on default port\n"
         @"  kaszlak serve --port 3000              # Start on port 3000\n"
         @"  kaszlak serve --data-dir /var/lib/kaszlak   # Use custom data directory\n"
         @"  kaszlak serve --foreground              # Run in foreground (no daemon)";
}

- (NSArray<NSString *> *)aliases {
  return @[ @"start", @"run", @"server", @"s" ];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args
                    context:(PDSCLICommandContext *)context {
  // SIGPIPE is already ignored by PDSSignalManager in main()

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
    } else if ([arg isEqualToString:@"--data-dir"] ||
               [arg isEqualToString:@"-d"]) {
      if (i + 1 < args.count) {
        context.dataDir = args[++i];
      }
    } else if ([arg isEqualToString:@"--config"] ||
               [arg isEqualToString:@"-c"]) {
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
    } else if ([arg isEqualToString:@"--foreground"] ||
               [arg isEqualToString:@"-f"]) {
      foreground = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      [context printInfo:[self helpText]];
      return 0;
    }
  }

  if (context.verbose) {
    GZ_LOG_INFO(@"Starting PDS server on port %ld", (long)port);
    GZ_LOG_INFO(@"Data directory: %@", context.dataDir);
    GZ_LOG_INFO(@"Config path: %@", context.configPath);
    GZ_LOG_INFO(@"Log level: %@", logLevel);
    if (logComponents) {
      GZ_LOG_INFO(@"Enabled components: %@", logComponents);
    }
  }

  printf("Starting PDS server on port %ld...\n", (long)port);
  printf("Data directory: %s\n", [context.dataDir UTF8String]);
  printf("Press Ctrl+C to stop.\n");

  // Load configuration from file into shared ATProtoServiceConfiguration
  if (context.configPath &&
      [[NSFileManager defaultManager] fileExistsAtPath:context.configPath]) {
    NSError *configError = nil;
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    if (![config loadFromPath:context.configPath error:&configError]) {
      printf("Warning: Failed to load config: %s\n",
             [configError.localizedDescription UTF8String]);
    } else {
      printf("Loaded config from: %s\n", [context.configPath UTF8String]);
      printf("Server host: %s\n", [config.serverHost UTF8String]);
      // Update port from config if not overridden by CLI later
      if (config.serverPort > 0) {
        port = config.serverPort;
      }
      // Update data directory from config if not overridden by CLI
      if (config.dataDirectory.length > 0 &&
          (context.dataDir == nil ||
           [context.dataDir
               isEqualToString:[ATProtoServiceConfiguration defaultDataDirectory]])) {
        context.dataDir = config.dataDirectory;
      }
    }
  }

  // Apply CLI overrides again to Ensure they take precedence over config
  for (NSUInteger i = 0; i < args.count; i++) {
    if ([args[i] isEqualToString:@"--port"] ||
        [args[i] isEqualToString:@"-p"]) {
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
    GZLogLevel level = GZLogLevelInfo;
    if ([logLevel isEqualToString:@"debug"])
      level = GZLogLevelDebug;
    else if ([logLevel isEqualToString:@"warn"])
      level = GZLogLevelWarn;
    else if ([logLevel isEqualToString:@"error"])
      level = GZLogLevelError;
    [GZLogger sharedLogger].logLevel = level;
  }

  if (logComponents) {
    NSArray *componentsList = [logComponents componentsSeparatedByString:@","];
    NSMutableSet *componentSet = [NSMutableSet set];
    for (NSString *c in componentsList) {
      [componentSet addObject:[c stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]]];
    }
    [GZLogger sharedLogger].enabledComponents = componentSet;
  }

  // Initialize and start HTTP server
  HttpServer *httpServer = [HttpServer serverWithPort:(uint16_t)port];
  if (!httpServer) {
    printf("Failed to create HTTP server\n");
    return 0;
  }

  // Initialize PDS controller with specified data directory
  NSString *dataDir = context.dataDir;
  if ([dataDir isEqualToString:[ATProtoServiceConfiguration defaultDataDirectory]] ||
      [dataDir isEqualToString:@"./data"]) {
    dataDir = @".";
  }

  // CRITICAL: Set serverPort BEFORE creating PDSController so that
  // PDSApplication uses the correct port for JWT issuer calculation.
  // Without this, JWT minter defaults to port 8080 while server runs on --port.
  [[ATProtoServiceConfiguration sharedConfiguration] setServerPort:port];

  GZ_LOG_INFO_C(GZLogComponentCLI,
                 @"Initializing PDS controller with data directory: %@",
                 dataDir);
  PDSController *controller = [[PDSController alloc] initWithDirectory:dataDir
                                                        serviceMaxSize:100
                                                      userDatabaseSize:30000];
  if (!controller) {
    printf("Failed to initialize PDS controller\n");
    return 0;
  }

  // Ensure PDSAdminAuth has data directory for admin DID persistence
  [PDSAdminAuth sharedAuth].dataDirectory = dataDir;
  [PDSAdminAuth sharedAuth].controller = controller;

  // Use the handler from the controller
  SubscribeReposHandler *subscribeReposHandler = controller.subscribeReposHandler;

  ATProtoHttpServerBuilder *serverBuilder = [[ATProtoHttpServerBuilder alloc]
      initWithConfiguration:[ATProtoServiceConfiguration sharedConfiguration]];
  serverBuilder.port = (NSUInteger)port;
  serverBuilder.controller = controller;
  serverBuilder.jwtMinter = controller.jwtMinter;
  serverBuilder.serviceDatabases = controller.serviceDatabases;
  serverBuilder.subscribeReposHandler = subscribeReposHandler;

  // Set the Server header for all PDS responses
  [HttpResponse setDefaultServerHeader:@"kaszlak/1.0.0 (garazyk)"];

  // Calculate canonical issuer with the actual port
  NSString *canonicalIssuer = [[ATProtoServiceConfiguration sharedConfiguration] canonicalIssuerWithPortHint:port];
  serverBuilder.issuer = canonicalIssuer;

  // Ensure JWT minter issuer matches the server port (belt and suspenders)
  controller.jwtMinter.issuer = canonicalIssuer;

  NSError *builderError = nil;
  if (![serverBuilder configureServer:httpServer error:&builderError]) {
    printf("Failed to configure HTTP server routes: %s\n",
           builderError.localizedDescription.UTF8String);
    return 0;
  }
  GZ_LOG_DEBUG_C(
      GZLogComponentCLI,
      @"PDSCLIServeCommand: Registered routes via ATProtoHttpServerBuilder");

  // Register Health Check
  [httpServer addRoute:@"GET"
                    path:@"/health"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                   NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
                   response.statusCode = [health[@"status"] isEqualToString:@"critical"] ? 503 : 200;
                   [response setJsonBody:health];
                 }];

    [httpServer addRoute:@"GET"
                    path:@"/_health"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                   NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
                   response.statusCode = [health[@"status"] isEqualToString:@"critical"] ? 503 : 200;
                   [response setJsonBody:health];
                 }];

  // Admin Login: accepts admin password, returns admin-scoped JWT
  [httpServer addRoute:@"POST"
                  path:@"/admin/login"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 NSDictionary *body = request.jsonBody;
                 if (![body isKindOfClass:[NSDictionary class]]) {
                   response.statusCode = 400;
                   [response setJsonBody:@{@"error": @"InvalidRequest",
                                           @"message": @"Expected JSON body"}];
                   return;
                 }
                 NSString *password = body[@"password"];
                 if (!password || password.length == 0) {
                   response.statusCode = 400;
                   [response setJsonBody:@{@"error": @"InvalidRequest",
                                           @"message": @"Password required"}];
                   return;
                 }
                 NSError *authError = nil;
                 if (![[PDSAdminAuth sharedAuth] authenticateWithPassword:password
                                                                    error:&authError]) {
                   response.statusCode = authError.code == 401 ? 401 : 403;
                   [response setJsonBody:@{@"error": @"AuthenticationFailed",
                                           @"message": authError.localizedDescription ?: @"Invalid credentials"}];
                   return;
                 }
                 NSString *token = [PDSAdminAuth sharedAuth].adminToken;
                 response.statusCode = 200;
                 [response setJsonBody:@{@"token": token ?: @""}];
               }];

  [httpServer addRoute:@"GET"
                  path:@"/robots.txt"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 response.statusCode = 200;
                 response.contentType = @"text/plain";
                 [response setBodyString:@"User-agent: *\nDisallow: /"];
               }];

  // Register Server DID Document (did:web support)
  [httpServer
      addRoute:@"GET"
          path:@"/.well-known/did.json"
       handler:^(HttpRequest *request, HttpResponse *response) {
         ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];

         // Use issuer URL for did:web hostname (not serverHost which is bind
         // address)
         NSString *issuer = config.canonicalIssuer ?: config.issuer;
         NSURL *issuerUrl = issuer ? [NSURL URLWithString:issuer] : nil;
         NSString *host = issuerUrl.host ?: @"localhost";
         NSString *scheme = issuerUrl.scheme ?: @"https";

         // Only include port in did:web if issuer URL explicitly has one
         // If issuer is https://pds.example.com (no port), did:web is
         // did:web:pds.example.com If issuer is https://pds.example.com:8443,
         // did:web is did:web:pds.example.com%3A8443
         NSUInteger issuerPort =
             issuerUrl.port ? [issuerUrl.port unsignedIntegerValue] : 0;
         NSString *didHost = host;
         if (issuerPort != 0 && issuerPort != 80 && issuerPort != 443) {
           didHost = [NSString
               stringWithFormat:@"%@%%3A%lu", host, (unsigned long)issuerPort];
         }

         NSString *did = [NSString stringWithFormat:@"did:web:%@", didHost];

         // Service endpoint uses issuer URL as-is if available
         NSString *serviceEndpoint =
             issuer ?: [NSString stringWithFormat:@"%@://%@", scheme, host];

         NSString *publicKeyMultibase = nil;
         NSData *publicKey = controller.jwtMinter.publicKey;
         if (publicKey.length > 0) {
           publicKeyMultibase =
               [NSString stringWithFormat:@"b%@", [CID base32Encode:publicKey]];
         }

         NSMutableDictionary *doc = [NSMutableDictionary dictionary];
         doc[@"@context"] = @[ @"https://www.w3.org/ns/did/v1" ];
         doc[@"id"] = did;
         doc[@"service"] = @[ @{
           @"id" : @"#atproto_pds",
           @"type" : @"AtprotoPersonalDataServer",
           @"serviceEndpoint" : serviceEndpoint
         } ];
         if (publicKeyMultibase) {
           NSDictionary *verificationMethod = @{
             @"id" : [NSString stringWithFormat:@"%@#atproto", did],
             @"type" : @"Multikey",
             @"controller" : did,
             @"publicKeyMultibase" : publicKeyMultibase
           };
           doc[@"verificationMethod"] = @[ verificationMethod ];
           doc[@"authentication"] = @[ verificationMethod[@"id"] ];
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
    printf("Failed to start HTTP server: %s\n",
           [serverError.localizedDescription UTF8String]);
    return 0;
  }

  [subscribeReposHandler startObservingNotifications];

  // Start relay service to notify external relays to crawl this PDS
  [[controller relayService] start];

  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSString *displayHost = config.serverHost ?: @"localhost";
  if ([displayHost isEqualToString:@"0.0.0.0"]) {
    displayHost = @"localhost";
  }

  printf("HTTP server started successfully on port %ld\n", (long)port);
  printf("Service endpoint available at: http://%s:%ld/\n",
         [displayHost UTF8String], (long)port);

  if (!foreground) {
    printf("Running in background...\n");
  }

  if (context.verbose) {
    GZ_LOG_INFO(@"PDS server started successfully");
  }

  // Setup signal handling for graceful shutdown via PDSSignalManager
  __block volatile sig_atomic_t shouldExit = 0;

  [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGINT handler:^(int sig) {
    shouldExit = 1;
    printf("\nShutting down server...\n");
    [subscribeReposHandler stop];
    [httpServer stop];
    // Give async operations 2 seconds to complete before forcing exit
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     printf("Forced exit after timeout.\n");
                     exit(0);
                   });
  }];

  [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:^(int sig) {
    shouldExit = 1;
    printf("\nShutting down server...\n");
    [subscribeReposHandler stop];
    [httpServer stop];
    // Give async operations 2 seconds to complete before forcing exit
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     printf("Forced exit after timeout.\n");
                     exit(0);
                   });
  }];

  // SIGHUP: log rotation trigger
  [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGHUP handler:^(int sig) {
    GZ_LOG_SERVICE_INFO(@"Received SIGHUP — rotating logs");
    [[GZLogger sharedLogger] rotateLogIfNeeded];
  }];

  // SIGUSR1: diagnostic dump
  [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGUSR1 handler:^(int sig) {
    GZ_LOG_SERVICE_INFO(@"Received SIGUSR1 — diagnostic dump requested");
    // Future: dump goroutine-equivalent (dispatch queue state), connection pool stats, etc.
  }];

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
      [[NSRunLoop mainRunLoop]
             runMode:NSDefaultRunLoopMode
          beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
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
