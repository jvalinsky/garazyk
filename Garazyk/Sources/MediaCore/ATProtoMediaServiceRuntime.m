// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaServiceRuntime.h"
#import "MediaCore/ATProtoMediaWorker.h"
#import "MediaCore/ATProtoMediaSQLiteStore.h"
#import "MediaCore/ATProtoMediaXrpcPack.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Debug/GZLogger.h"

@interface ATProtoMediaServiceRuntime ()
@property (nonatomic, strong, readwrite) HttpServer *httpServer;
@property (nonatomic, strong, readwrite) ATProtoMediaWorker *worker;
@property (nonatomic, strong) ATProtoMediaSQLiteStore *jobStore;
@property (nonatomic, strong) id<PDSBlobProvider> blobProvider;
@end

@implementation ATProtoMediaServiceRuntime

- (instancetype)initWithConfiguration:(ATProtoMediaServiceConfiguration *)configuration
                            processor:(id<ATProtoMediaProcessor>)processor {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _processor = processor;
    }
    return self;
}

- (BOOL)startWithError:(NSError **)error {
    ATProtoMediaServiceConfiguration *config = self.configuration;

    GZ_LOG_INFO(@"Media service starting: %@", self.processor.mediaTypeIdentifier);
    GZ_LOG_INFO(@"  Port: %lu", (unsigned long)config.port);
    GZ_LOG_INFO(@"  PDS URL: %@", config.pdsURL);
    GZ_LOG_INFO(@"  Service DID: %@", config.serviceDID);
    GZ_LOG_INFO(@"  Data dir: %@", config.dataDirectory);

    // ── Database ──────────────────────────────────────────────
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"media.db"];
    self.jobStore = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:dbPath error:error];
    if (!self.jobStore) {
        GZ_LOG_ERROR(@"Failed to open database: %@", error ? *error : nil);
        return NO;
    }

    // ── Blob Provider ─────────────────────────────────────────
    if (config.s3Bucket) {
        self.blobProvider = [[PDSCloudStorageBlobProvider alloc] initWithBucket:config.s3Bucket
                                                                         region:config.s3Region
                                                                       endpoint:config.s3Endpoint
                                                                      keyPrefix:@"blobs/"
                                                                  accessKeyId:config.s3AccessKey ?: @""
                                                               secretAccessKey:config.s3SecretKey ?: @""];
        GZ_LOG_INFO(@"  Blob storage: S3 (%@)", config.s3Bucket);
    } else {
        self.blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:[NSURL fileURLWithPath:config.blobDirectory]];
        GZ_LOG_INFO(@"  Blob storage: disk (%@)", config.blobDirectory);
    }

    // ── Worker ────────────────────────────────────────────────
    self.worker = [[ATProtoMediaWorker alloc] init];
    self.worker.jobStore = self.jobStore;
    self.worker.processor = self.processor;
    self.worker.blobProvider = self.blobProvider;
    self.worker.maxConcurrentJobs = config.maxConcurrentJobs;
    self.worker.pollInterval = config.pollInterval;
    [self.worker start];

    // ── XRPC Dispatcher ──────────────────────────────────────
    // A private instance, not the process-wide shared singleton: this
    // runtime owns its own HTTP server and routes requests to this
    // dispatcher directly (see the xrpcHandler block below), and jelcz is
    // the only production consumer, starting exactly one runtime per
    // process. Using the singleton meant a second start (or a second
    // runtime) in the same process — as XCTest does — hit "Duplicate XRPC
    // handler registration".
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    XrpcRoutePackServiceBag *routeServices = [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                                                       jwtMinter:nil
                                                                                 adminController:nil
                                                                                    configuration:nil
                                                                                      adminSecret:nil
                                                                                serviceDatabases:nil
                                                                                userDatabasePool:nil
                                                                                      rateLimiter:nil];
    routeServices.videoJobStore = (id)self.jobStore;
    routeServices.blobProvider = self.blobProvider;

    ATProtoMediaXrpcPack *xrpcPack = [[ATProtoMediaXrpcPack alloc] init];
    xrpcPack.methodMappings = @{
        @"getJobStatus":    [NSString stringWithFormat:@"%@.getJobStatus",    self.processor.mediaTypeIdentifier],
        @"upload":          [NSString stringWithFormat:@"%@.uploadMedia",     self.processor.mediaTypeIdentifier],
        @"getUploadLimits": [NSString stringWithFormat:@"%@.getUploadLimits", self.processor.mediaTypeIdentifier],
    };
    [xrpcPack registerWithDispatcher:dispatcher services:routeServices];

    // ── HTTP Server ───────────────────────────────────────────
    self.httpServer = [HttpServer serverWithPort:config.port];

    __weak typeof(self) weakSelf = self;
    void (^xrpcHandler)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
        [weakSelf setCORSHeaders:request response:response];
        [dispatcher handleRequest:request response:response];
    };

    [self.httpServer addRoute:@"OPTIONS" path:@"/xrpc" handler:xrpcHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/xrpc/*" handler:xrpcHandler];
    [self.httpServer addRoute:@"POST" path:@"/xrpc" handler:xrpcHandler];
    [self.httpServer addRoute:@"POST" path:@"/xrpc/*" handler:xrpcHandler];
    [self.httpServer addRoute:@"GET" path:@"/xrpc" handler:xrpcHandler];
    [self.httpServer addRoute:@"GET" path:@"/xrpc/*" handler:xrpcHandler];
    [self.httpServer addHandlerForPath:@"/xrpc" handler:xrpcHandler];

    // Health endpoint
    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:@{@"status": @"ok", @"service": weakSelf.processor.mediaTypeIdentifier}];
    }];

    // Admin: list jobs
    [self.httpServer addRoute:@"GET" path:@"/admin/api/media/jobs" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *stateFilter = [request queryParamForKey:@"state"];
        if (stateFilter.length == 0) stateFilter = nil;
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSUInteger limit = limitStr.length > 0 ? (NSUInteger)limitStr.integerValue : 25;
        if (limit == 0 || limit > 100) limit = 25;
        NSString *cursorStr = [request queryParamForKey:@"cursor"];
        NSUInteger offset = cursorStr.length > 0 ? (NSUInteger)cursorStr.integerValue : 0;

        NSError *err = nil;
        NSArray *jobs = [weakSelf.jobStore listJobsWithState:stateFilter limit:limit offset:offset error:&err];
        if (err) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"JobListFailed", @"message": err.localizedDescription}];
            return;
        }
        NSString *nextCursor = jobs.count >= limit ? [NSString stringWithFormat:@"%lu", (unsigned long)(offset + limit)] : nil;
        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:jobs ?: @[] forKey:@"jobs"];
        if (nextCursor) body[@"cursor"] = nextCursor;
        response.statusCode = 200;
        [response setJsonBody:body];
    }];

    // Admin: retry job
    [self.httpServer addRoute:@"POST" path:@"/admin/api/media/jobs/:jobId/retry" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *jobId = request.pathParameters[@"jobId"];
        if (jobId.length == 0) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Job ID is required"}];
            return;
        }
        NSError *err = nil;
        BOOL ok = [weakSelf.jobStore incrementJobRetry:jobId error:&err];
        if (!ok) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"JobRetryFailed", @"message": err.localizedDescription ?: @"Unknown error"}];
            return;
        }
        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    NSError *startError = nil;
    if (![self.httpServer startWithError:&startError]) {
        GZ_LOG_ERROR(@"Failed to start HTTP server: %@", startError);
        if (error) *error = startError;
        return NO;
    }

    GZ_LOG_INFO(@"Media service listening on port %lu", (unsigned long)config.port);
    return YES;
}

- (void)stop {
    [self.worker stop];
    [self.httpServer stop];
}

#pragma mark - CORS

- (void)setCORSHeaders:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *origin = [request headerForKey:@"Origin"];
    if (origin.length > 0) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
        [response setHeader:@"Origin" forKey:@"Vary"];
    } else {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }
    [response setHeader:@"GET, POST, OPTIONS, HEAD" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, Accept, Range, If-None-Match, If-Modified-Since, DPoP, DPoP-Nonce, X-Garazyk-Access-JWT, X-Garazyk-Access-Token, *" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"Content-Length, Content-Range, Accept-Ranges, DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"true" forKey:@"Access-Control-Allow-Private-Network"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
}

@end
