# PDSApplication Facade

## Overview

`PDSApplication` is the primary facade for the PDS. It:
- Composes all services
- Manages server lifecycle
- Provides a unified interface to the entire system
- Handles initialization and configuration

## Architecture

### Service Composition

```
PDSApplication
├── PDSAccountService
├── PDSRecordService
├── PDSBlobService
├── PDSRepositoryService
├── PDSAdminController
├── PDSRelayService
├── PDSServiceDatabases
└── PDSDatabasePool
```

### Initialization Flow

The actual initialization in PDSApplication.m follows this pattern (lines 1-150):

```objc
// In PDSApplication.m
- (instancetype)initWithConfiguration:(nullable PDSConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration ?: [PDSConfiguration sharedConfiguration];
        _dataDirectory = _configuration.dataDirectory ?: [PDSConfiguration defaultDataDirectory];
        _httpPort = _configuration.serverPort > 0 ? _configuration.serverPort : 2583;
        _running = NO;

        // Catch unhandled ObjC exceptions before they silently crash
        NSSetUncaughtExceptionHandler(&PDSApplicationUncaughtExceptionHandler);

        // Configure logging from configuration
        [self configureLogging];
        
        // Configure rate limiter
        [self configureRateLimiter];
        
        PDS_LOG_INFO_C(PDSLogComponentCore, @"PDSApplication initializing with data directory: %@", _dataDirectory);
        
        // Initialize infrastructure (databases, JWT minter)
        [self initializeInfrastructure];
        
        // Initialize services
        [self initializeServices];
        
        // Load lexicons
        [self loadLexicons];
    }
    return self;
}
```

**Key initialization steps (from PDSApplication.m lines 150-250):**

1. **Database initialization:**
```objc
_serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:_dataDirectory
                                                     serviceMaxSize:serviceMaxSize
                                                   didCacheMaxSize:didCacheSize
                                                 sequencerMaxSize:sequencerSize];

_userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:_dataDirectory maxSize:userMaxSize];
```

2. **JWT Minter setup:**
```objc
_jwtMinter = [[JWTMinter alloc] init];
_jwtMinter.issuer = [_configuration canonicalIssuerWithPortHint:_httpPort];
_jwtMinter.signingAlgorithm = @"ES256K";

// Load or create signing key
id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:[_serviceDatabases serviceDatabaseWithError:nil]];
id<PDSKeyPair> activeKey = [keyManager getActiveKeyPair:&serverKeyError];
if (activeKey) {
    _jwtMinter.keyManager = keyManager;
}
```

3. **Service initialization:**
```objc
_accountService = [[PDSAccountService alloc] initWithDatabasePool:_userDatabasePool];
_recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
_blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool storage:blobStorage];
_repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
```

## Service Access

### Getting Services

```objc
// Access services through PDSApplication
PDSApplication *app = ...;

// Account operations
[app.accountService createAccountWithEmail:@"user@example.com" 
                                   handle:@"user.example.com"
                                 password:@"password"
                               completion:^(NSString *did, NSError *error) {
    // Handle result
}];

// Record operations
[app.recordService createRecord:@{@"text": @"Hello"}
                    collection:@"app.bsky.feed.post"
                           did:userDID
                    completion:^(NSString *uri, NSError *error) {
    // Handle result
}];

// Blob operations
[app.blobService uploadBlob:imageData
                 completion:^(NSString *blobCID, NSError *error) {
    // Handle result
}];
```

## Lifecycle Management

### Starting the Server

```objc
// In main.m or CLI dispatcher
PDSApplication *app = [[PDSApplication alloc] 
    initWithConfiguration:config error:&error];

if (!app) {
    NSLog(@"Failed to initialize PDS: %@", error);
    exit(1);
}

// Start HTTP server
[app.httpServer startWithCompletion:^(NSError *error) {
    if (error) {
        NSLog(@"Failed to start server: %@", error);
        exit(1);
    }
    
    NSLog(@"PDS started on port %ld", (long)app.configuration.server.port);
}];

// Keep server running
[[NSRunLoop mainRunLoop] run];
```

### Stopping the Server

```objc
// Graceful shutdown
[app.httpServer stopWithCompletion:^(NSError *error) {
    if (error) {
        NSLog(@"Error stopping server: %@", error);
    }
    
    // Close databases
    [app.serviceDatabases close];
    [app.databasePool close];
    
    NSLog(@"PDS stopped");
    exit(0);
}];
```

## Configuration

### Configuration File

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "issuer": "https://pds.example.com"
  },
  "database": {
    "path": "./pds-data/db"
  },
  "plc": {
    "url": "https://plc.directory"
  },
  "session": {
    "invite_code_required": true
  },
  "debug": {
    "verbose": false,
    "log_level": "info"
  }
}
```

### Loading Configuration

```objc
// In PDSConfiguration.m
+ (instancetype)loadFromFile:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        *error = [NSError errorWithDomain:@"Config" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"File not found"}];
        return nil;
    }
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data 
                                                          options:0 
                                                            error:error];
    if (!json) return nil;
    
    PDSConfiguration *config = [[PDSConfiguration alloc] init];
    config.serverHost = json[@"server"][@"host"] ?: @"0.0.0.0";
    config.serverPort = [json[@"server"][@"port"] integerValue] ?: 2583;
    config.issuer = json[@"server"][@"issuer"];
    config.databasePath = json[@"database"][@"path"];
    config.plcURL = json[@"plc"][@"url"];
    config.inviteCodeRequired = [json[@"session"][@"invite_code_required"] boolValue];
    
    return config;
}
```

## Error Handling

### Standardized Errors

```objc
// In XrpcErrorHelper.m
+ (NSDictionary *)errorResponseForError:(NSError *)error {
    NSString *errorCode = @"InternalServerError";
    NSString *message = error.localizedDescription;
    
    if ([error.domain isEqualToString:@"XRPC"]) {
        switch (error.code) {
            case 1:
                errorCode = @"InvalidRequest";
                break;
            case 2:
                errorCode = @"Unauthorized";
                break;
            case 3:
                errorCode = @"Forbidden";
                break;
            case 4:
                errorCode = @"NotFound";
                break;
            case 5:
                errorCode = @"Conflict";
                break;
        }
    }
    
    return @{
        @"error": errorCode,
        @"message": message
    };
}
```

## Logging

### Structured Logging

```objc
// In PDSApplication.m
- (void)logMessage:(NSString *)message 
             level:(NSString *)level 
           context:(NSDictionary *)context {
    if (self.configuration.debug.verbose) {
        NSMutableString *log = [NSMutableString stringWithFormat:@"[%@] %@", level, message];
        
        if (context) {
            [log appendFormat:@" %@", context];
        }
        
        NSLog(@"%@", log);
    }
}

// Usage
[app logMessage:@"Record created" 
          level:@"INFO" 
        context:@{@"did": userDID, @"collection": @"app.bsky.feed.post"}];
```

## Monitoring and Metrics

### Request Metrics

```objc
// In PDSApplication.m
- (void)recordRequestMetric:(NSString *)method 
                   duration:(NSTimeInterval)duration 
                    success:(BOOL)success {
    @synchronized(self.metrics) {
        NSMutableDictionary *methodMetrics = self.metrics[method];
        if (!methodMetrics) {
            methodMetrics = [NSMutableDictionary dictionary];
            self.metrics[method] = methodMetrics;
        }
        
        methodMetrics[@"count"] = @([methodMetrics[@"count"] integerValue] + 1);
        methodMetrics[@"totalDuration"] = @([methodMetrics[@"totalDuration"] doubleValue] + duration);
        
        if (!success) {
            methodMetrics[@"errors"] = @([methodMetrics[@"errors"] integerValue] + 1);
        }
    }
}

// Get metrics
- (NSDictionary *)getMetrics {
    @synchronized(self.metrics) {
        return [self.metrics copy];
    }
}
```

## Health Checks

### Server Health

```objc
// In PDSApplication.m
- (BOOL)isHealthy:(NSError **)error {
    // Check database connectivity
    if (![self.serviceDatabases isConnected]) {
        *error = [NSError errorWithDomain:@"Health" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Database not connected"}];
        return NO;
    }
    
    // Check HTTP server
    if (![self.httpServer isRunning]) {
        *error = [NSError errorWithDomain:@"Health" code:2 
            userInfo:@{NSLocalizedDescriptionKey: @"HTTP server not running"}];
        return NO;
    }
    
    return YES;
}
```

## Best Practices

1. **Use PDSApplication for all access** — Don't access services directly
2. **Handle errors properly** — Always check for errors
3. **Log important events** — For debugging and monitoring
4. **Monitor metrics** — Track performance
5. **Graceful shutdown** — Clean up resources
6. **Configuration validation** — Validate on startup

## Next Steps

- **[Services Overview](./services-overview)** — Service architecture
- **[Account Service](./account-service)** — Account management
- **[Record Service](./record-service)** — Record operations
- **[Network Layer](../04-network-layer/http-server)** — HTTP and XRPC
