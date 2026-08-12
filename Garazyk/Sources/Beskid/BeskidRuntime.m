// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidRuntime.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidXrpcRoutePack.h"
#import "Beskid/BeskidMetrics.h"
#import "Beskid/AdminUI/BeskidAdminSnapshot.h"
#import "Beskid/AdminUI/BeskidAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/RateLimiter.h"
#import "Debug/GZLogger.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@interface GZBeskidRuntime ()
@property (nonatomic, strong, readwrite) GZBeskidConfiguration *configuration;
@property (nonatomic, strong, readwrite) GZBeskidDatabase *database;
@property (nonatomic, strong) ATProtoHttpServer *httpServer;
@property (nonatomic, strong) GZBeskidMetrics *metrics;
@property (nonatomic, strong) GZAdminUIHost *adminUIHostInstance;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation GZBeskidRuntime

+ (instancetype)sharedRuntime {
    static GZBeskidRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [[GZBeskidRuntime alloc] init];
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
    GZBeskidConfiguration *config = [GZBeskidConfiguration defaultConfiguration];
    [config loadFromDictionary:json[@"beskid"] ?: json];
    if (![config validate:error]) return NO;
    self.configuration = config;
    return YES;
}

- (void)loadConfigurationFromEnvironment {
    self.configuration = [GZBeskidConfiguration configurationFromEnvironment];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.isRunning) return YES;
    GZBeskidConfiguration *config = self.configuration ?: [GZBeskidConfiguration defaultConfiguration];
    if (![config validate:error]) return NO;
    self.configuration = config;

    self.metrics = [[GZBeskidMetrics alloc] init];

    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:config.dataDirectory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&mkdirError]) {
        if (error) *error = mkdirError;
        return NO;
    }

    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"beskid.db"];
    self.database = [[GZBeskidDatabase alloc] initWithPath:dbPath error:error];
    if (!self.database) return NO;
    if (![self.database runMigrations:error]) return NO;
    self.database.metrics = self.metrics;

    // Seed entry gauges from the live on-disk count
    NSDictionary *counts = [self.database entryCountsWithError:nil];
    [self.metrics seedEntryGaugesWithRecordCount:[counts[@"records"] unsignedIntegerValue]
                                   identityCount:[counts[@"identities"] unsignedIntegerValue]];

    self.httpServer = [ATProtoHttpServer serverWithPort:config.httpPort];
    [ATProtoHttpResponse setDefaultServerHeader:@"garazyk-beskid/1.0.0"];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = HttpStatusOK;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"garazyk beskid edge cache\n"];
    }];

    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"status": @"ok",
            @"service": @"beskid"
        }];
    }];

    // Configure per-IP rate limiting
    ATProtoRateLimiter *rateLimiter = [ATProtoRateLimiter sharedLimiter];
    rateLimiter.enabled = config.rateLimitEnabled;
    rateLimiter.ipLimit = config.rateLimitIpLimit;
    rateLimiter.ipWindowSeconds = config.rateLimitIpWindowSeconds;
    NSString *rlDbPath = [config.dataDirectory stringByAppendingPathComponent:@"ratelimits.db"];
    [rateLimiter reconfigureDatabasePath:rlDbPath];

    GZBeskidXrpcRoutePack *routes = [[GZBeskidXrpcRoutePack alloc] initWithDatabase:self.database];
    routes.metrics = self.metrics;
    [routes registerRoutesWithServer:self.httpServer];

    NSError *listenError = nil;
    if (![self.httpServer startWithError:&listenError]) {
        if (error) *error = listenError;
        return NO;
    }
    config.httpPort = self.httpServer.port;

    // Embedded admin listener: only starts when a password is configured
    if (self.adminPassword.length > 0) {
        GZAdminUIServiceConfig *adminConfig = [[GZAdminUIServiceConfig alloc] init];
        adminConfig.host = self.adminUIHost ?: @"127.0.0.1";
        adminConfig.port = self.adminUIPort ?: 2595;
        adminConfig.adminPassword = self.adminPassword;
        adminConfig.serviceIdentifier = @"beskid";
        self.adminUIHostInstance = [[GZAdminUIHost alloc] initWithConfiguration:adminConfig packs:@[GZBeskidAdminUIPack.class]];
        [GZBeskidAdminUIPack configureHost:self.adminUIHostInstance
                                  snapshot:[[GZBeskidAdminSnapshot alloc] initWithDatabase:self.database
                                                                                   metrics:self.metrics
                                                                             configuration:self.configuration]];
        if (![self.adminUIHostInstance startWithError:&listenError]) {
            [self.httpServer stop];
            if (error) *error = listenError;
            return NO;
        }
    } else {
        GZ_LOG_CORE_WARN(@"Beskid admin UI disabled: BESKID_ADMIN_PASSWORD or BESKID_ADMIN_PASSWORD_FILE is not configured");
    }

    self.isRunning = YES;
    GZ_LOG_INFO(@"[Beskid] Started on port %lu", (unsigned long)config.httpPort);
    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    [self.adminUIHostInstance stop];
    [self.httpServer stop];
    [self.database close];
    self.adminUIHostInstance = nil;
    self.httpServer = nil;
    self.isRunning = NO;
}

@end
