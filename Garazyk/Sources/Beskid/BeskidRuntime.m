// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidRuntime.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidXrpcRoutePack.h"
#import "Network/RateLimiter.h"
#import "Debug/GZLogger.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@interface BeskidRuntime ()
@property (nonatomic, strong, readwrite) BeskidConfiguration *configuration;
@property (nonatomic, strong, readwrite) BeskidDatabase *database;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation BeskidRuntime

+ (instancetype)sharedRuntime {
    static BeskidRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [[BeskidRuntime alloc] init];
    });
    return runtime;
}

- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return NO;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"BeskidRuntime"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid config file"}];
        return NO;
    }
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    [config loadFromDictionary:json[@"beskid"] ?: json];
    if (![config validate:error]) return NO;
    self.configuration = config;
    return YES;
}

- (void)loadConfigurationFromEnvironment {
    self.configuration = [BeskidConfiguration configurationFromEnvironment];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.isRunning) return YES;
    BeskidConfiguration *config = self.configuration ?: [BeskidConfiguration defaultConfiguration];
    if (![config validate:error]) return NO;
    self.configuration = config;

    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:config.dataDirectory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&mkdirError]) {
        if (error) *error = mkdirError;
        return NO;
    }

    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"beskid.db"];
    self.database = [[BeskidDatabase alloc] initWithPath:dbPath error:error];
    if (!self.database) return NO;
    if (![self.database runMigrations:error]) return NO;

    self.httpServer = [HttpServer serverWithPort:config.httpPort];
    [HttpResponse setDefaultServerHeader:@"garazyk-beskid/1.0.0"];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"garazyk beskid edge cache\n"];
    }];

    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"status": @"ok",
            @"service": @"beskid"
        }];
    }];

    // Configure per-IP rate limiting
    RateLimiter *rateLimiter = [RateLimiter sharedLimiter];
    rateLimiter.enabled = config.rateLimitEnabled;
    rateLimiter.ipLimit = config.rateLimitIpLimit;
    rateLimiter.ipWindowSeconds = config.rateLimitIpWindowSeconds;
    NSString *rlDbPath = [config.dataDirectory stringByAppendingPathComponent:@"ratelimits.db"];
    [rateLimiter reconfigureDatabasePath:rlDbPath];

    BeskidXrpcRoutePack *routes = [[BeskidXrpcRoutePack alloc] initWithDatabase:self.database];
    [routes registerRoutesWithServer:self.httpServer];

    NSError *listenError = nil;
    if (![self.httpServer startWithError:&listenError]) {
        if (error) *error = listenError;
        return NO;
    }
    config.httpPort = self.httpServer.port;

    self.isRunning = YES;
    GZ_LOG_INFO(@"[Beskid] Started on port %lu", (unsigned long)config.httpPort);
    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    [self.httpServer stop];
    [self.database close];
    self.httpServer = nil;
    self.isRunning = NO;
}

@end
