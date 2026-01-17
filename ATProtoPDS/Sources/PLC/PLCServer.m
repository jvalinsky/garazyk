#import "PLC/PLCServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"

@interface PLCServer ()
@property (nonatomic, strong) id<PLCStore> store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) HttpServer *httpServer;

- (void)serveStaticFile:(NSString *)path response:(HttpResponse *)resp;
- (NSString *)assetsPath;
@end

@implementation PLCServer

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _store = store;
        _auditor = auditor;
        _httpServer = [HttpServer serverWithPort:port];
        [self setupRoutes];
    }
    return self;
}

- (void)setupRoutes {
    __weak typeof(self) weakSelf = self;
    
    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        resp.statusCode = HttpStatusOK;
        [resp setJsonBody:@{@"status": @"ok"}];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/_list" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        NSError *error = nil;
        NSArray<NSString *> *dids = [weakSelf.store getAllDIDsWithError:&error];
        if (error) {
            [[PLCMetrics sharedMetrics] recordError];
            resp.statusCode = HttpStatusInternalServerError;
            [resp setJsonBody:@{@"error": error.localizedDescription}];
        } else {
            resp.statusCode = HttpStatusOK;
            [resp setJsonBody:dids];
        }
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/_metrics" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        NSString *metrics = [[PLCMetrics sharedMetrics] renderMetrics];
        resp.statusCode = HttpStatusOK;
        resp.contentType = @"text/plain; charset=utf-8";
        [resp setBodyString:metrics];
    }];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf serveStaticFile:@"index.html" response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/css/:file" handler:^(HttpRequest *req, HttpResponse *resp) {
        NSString *file = req.pathParameters[@"file"];
        [weakSelf serveStaticFile:[NSString stringWithFormat:@"css/%@", file] response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/js/:file" handler:^(HttpRequest *req, HttpResponse *resp) {
        NSString *file = req.pathParameters[@"file"];
        [weakSelf serveStaticFile:[NSString stringWithFormat:@"js/%@", file] response:resp];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        NSString *did = req.pathParameters[@"did"];
        if ([did hasPrefix:@"did:plc:"]) {
            [weakSelf handleGetDID:req response:resp];
        } else {
            // Fallback to static files if it doesn't look like a DID
            [weakSelf serveStaticFile:did response:resp];
        }
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did/log" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetLog:req response:resp];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did/log/audit" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetLog:req response:resp];
    }];
    
    [self.httpServer addRoute:@"POST" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        [weakSelf handlePostDID:req response:resp];
    }];
}

- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }
    
    if (!history || history.count == 0) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }
    
    PLCDIDState *state = [PLCStateReplayer replayHistory:history error:&error];
    if (!state) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": @"Failed to replay history"}];
        return;
    }
    
    if (state.tombstoned) {
        resp.statusCode = 410; // Gone
        [resp setJsonBody:@{@"message": [NSString stringWithFormat:@"DID not available: %@", did]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:[state toDIDDocument]];
}

- (void)handleGetLog:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
    if (!did) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": @"Internal server error"}];
        return;
    }
    
    if (!history) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }
    
    NSMutableArray *historyDicts = [NSMutableArray array];
    for (PLCOperation *op in history) {
        [historyDicts addObject:[op toDictionary]];
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:historyDicts];
}

- (void)handlePostDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSDictionary *json = req.jsonBody;
    if (!json) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing JSON body"}];
        return;
    }
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    if (!op) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Invalid operation format: %@", error.localizedDescription]}];
        return;
    }
    
    op.did = did;
    
    // Validate using auditor
    if (![self.auditor verifyOperation:op error:&error]) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Audit failed: %@", error.localizedDescription]}];
        return;
    }
    
    // Append to store
    if (![self.store appendOperation:op error:&error]) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Failed to append: %@", error.localizedDescription]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:@{@"status": @"ok"}];
}

- (BOOL)startWithError:(NSError **)error {
    return [self.httpServer startWithError:error];
}

- (void)stop {
    [self.httpServer stop];
}

#pragma mark - Static Files

- (void)serveStaticFile:(NSString *)path response:(HttpResponse *)resp {
    NSString *assets = [self assetsPath];
    if (!assets) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"Assets not found"}];
        return;
    }
    
    NSString *fullPath = [assets stringByAppendingPathComponent:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"File not found", @"path": path}];
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:fullPath];
    if (!data) {
        resp.statusCode = HttpStatusInternalServerError;
        return;
    }
    
    NSString *extension = [path pathExtension].lowercaseString;
    NSString *contentType = @"text/plain";
    if ([extension isEqualToString:@"html"]) contentType = @"text/html; charset=utf-8";
    else if ([extension isEqualToString:@"css"]) contentType = @"text/css; charset=utf-8";
    else if ([extension isEqualToString:@"js"]) contentType = @"application/javascript; charset=utf-8";
    else if ([extension isEqualToString:@"json"]) contentType = @"application/json; charset=utf-8";
    
    // Explicitly set the header to ensure it overrides any defaults
    [resp setHeader:contentType forKey:@"Content-Type"];
    resp.contentType = contentType;
    resp.statusCode = HttpStatusOK;
    [resp setBody:data];
    
    // Debug logging
    fprintf(stderr, "[PLCServer] Serving %s with Content-Type: %s\n", path.UTF8String, contentType.UTF8String);
}

- (NSString *)assetsPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = [fm currentDirectoryPath];
    
    NSArray *candidates = @[
        [cwd stringByAppendingPathComponent:@"ATProtoPDS/Sources/PLC/Assets"],
        [cwd stringByAppendingPathComponent:@"Sources/PLC/Assets"],
        [cwd stringByAppendingPathComponent:@"Assets"],
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Assets"]
    ];
    
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            return path;
        }
    }
    
    return nil;
}

@end
