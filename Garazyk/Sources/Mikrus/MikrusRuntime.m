// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Mikrus/MikrusRuntime.h"
#import "Mikrus/MikrusConfiguration.h"
#import "Mikrus/MikrusDatabase.h"
#import "Mikrus/MikrusXrpcRoutePack.h"
#import "Network/RateLimiter.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "Debug/GZLogger.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@interface MikrusRuntime ()
@property (nonatomic, strong, readwrite) MikrusConfiguration *configuration;
@property (nonatomic, strong, readwrite) MikrusDatabase *database;
@property (nonatomic, strong) AppViewDatabase *ingestStateDatabase;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@end

@implementation MikrusRuntime

+ (instancetype)sharedRuntime {
    static MikrusRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [[MikrusRuntime alloc] init];
    });
    return runtime;
}

- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return NO;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"MikrusRuntime"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid config file"}];
        return NO;
    }
    MikrusConfiguration *config = [MikrusConfiguration defaultConfiguration];
    [config loadFromDictionary:json[@"mikrus"] ?: json];
    if (![config validate:error]) return NO;
    self.configuration = config;
    return YES;
}

- (void)loadConfigurationFromEnvironment {
    self.configuration = [MikrusConfiguration configurationFromEnvironment];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.isRunning) return YES;
    MikrusConfiguration *config = self.configuration ?: [MikrusConfiguration defaultConfiguration];
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

    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"mikrus.db"];
    self.database = [[MikrusDatabase alloc] initWithPath:dbPath error:error];
    if (!self.database) return NO;
    if (![self.database runMigrations:error]) return NO;

    self.httpServer = [HttpServer serverWithPort:config.httpPort];
    [HttpResponse setDefaultServerHeader:@"garazyk-mikrus/1.0.0"];
    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"garazyk mikrus\n"];
    }];
    __weak typeof(self) weakSelf = self;
    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"status": @"ok",
            @"ingest": strongSelf.ingestEngine.isRunning ? @"running" : @"stopped"
        }];
    }];

    // Configure per-IP rate limiting for Mikrus endpoints.
    // Defaults: 200 req/min per IP (more generous than PDS default of 100).
    // Override via MIKRUS_RATELIMIT_IP_LIMIT, MIKRUS_RATELIMIT_IP_WINDOW, MIKRUS_RATELIMIT_ENABLED.
    RateLimiter *rateLimiter = [RateLimiter sharedLimiter];
    rateLimiter.enabled = config.rateLimitEnabled;
    rateLimiter.ipLimit = config.rateLimitIpLimit;
    rateLimiter.ipWindowSeconds = config.rateLimitIpWindowSeconds;
    NSString *rlDbPath = [config.dataDirectory stringByAppendingPathComponent:@"ratelimits.db"];
    [rateLimiter reconfigureDatabasePath:rlDbPath];

    MikrusXrpcRoutePack *routes = [[MikrusXrpcRoutePack alloc] initWithDatabase:self.database];
    [routes registerRoutesWithServer:self.httpServer];

    NSError *listenError = nil;
    if (![self.httpServer startWithError:&listenError]) {
        if (error) *error = listenError;
        return NO;
    }
    config.httpPort = self.httpServer.port;

    if (config.ingestEnabled) {
        NSString *statePath = [config.dataDirectory stringByAppendingPathComponent:@"ingest-state.db"];
        self.ingestStateDatabase = [[AppViewDatabase alloc] initWithPath:statePath error:error];
        if (!self.ingestStateDatabase) return NO;
        if (![self.ingestStateDatabase runMigrations:error]) return NO;

        self.ingestEngine = [[AppViewIngestEngine alloc] initWithDatabase:self.ingestStateDatabase
                                                                relayURLs:config.relayURLs];
        self.ingestEngine.checkpointIntervalMs = config.cursorCheckpointIntervalMs;
        self.ingestEngine.delegate = self;
        [self.ingestEngine start];
    }

    self.isRunning = YES;
    GZ_LOG_INFO(@"[Mikrus] Started on port %lu", (unsigned long)config.httpPort);
    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    [self.ingestEngine stop];
    [self.httpServer stop];
    [self.database close];
    [self.ingestStateDatabase close];
    self.ingestEngine = nil;
    self.httpServer = nil;
    self.isRunning = NO;
}

#pragma mark - AppViewIngestEngineDelegate

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveCommit:(AppViewIngestEvent *)event {
    for (NSDictionary *op in event.ops ?: @[]) {
        NSString *action = op[@"action"];
        NSString *path = op[@"path"];
        if (path.length == 0) continue;
        NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
        NSString *collection = parts.count > 0 ? parts[0] : nil;
        NSString *rkey = parts.count > 1 ? parts[1] : nil;
        if (collection.length == 0 || rkey.length == 0 || event.did.length == 0) continue;

        NSError *error = nil;
        if ([action isEqualToString:@"delete"]) {
            if (![self.database deleteRecordForDID:event.did collection:collection rkey:rkey error:&error]) {
                GZ_LOG_WARN(@"[Mikrus] Failed to delete %@/%@ for %@: %@",
                            collection, rkey, event.did, error.localizedDescription);
            }
            continue;
        }

        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSDictionary *record = op[@"record"];
            if (![record isKindOfClass:[NSDictionary class]]) continue;
            NSString *cid = [op[@"cid"] isKindOfClass:[NSString class]] ? op[@"cid"] : nil;
            if (![self.database indexRecord:record
                                        did:event.did
                                 collection:collection
                                       rkey:rkey
                                        cid:cid
                                        seq:event.seq
                                      error:&error]) {
                GZ_LOG_WARN(@"[Mikrus] Failed to index %@/%@ for %@: %@",
                            collection, rkey, event.did, error.localizedDescription);
            }
        }
    }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine didReceiveIdentityChange:(AppViewIngestEvent *)event {
    (void)engine;
    (void)event;
}

@end
