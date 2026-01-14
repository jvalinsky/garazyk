#import "App/MSTViewer/MSTViewerHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Repository/PDSRepositoryService.h"
#import "App/Services/PDSAccountService.h"
#import <Foundation/Foundation.h>

#pragma mark - MSTViewerHandler

@interface MSTViewerHandler ()
@property (nonatomic, assign) PDSController *controller;  // assign for Linux compatibility
@property (nonatomic, strong) NSCache *cache;
@end

@implementation MSTViewerHandler

+ (instancetype)sharedHandler {
    static MSTViewerHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MSTViewerHandler alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 100;  // Cache up to 100 items
    }
    return self;
}

- (void)setController:(PDSController *)controller {
    _controller = controller;
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
    return [request.path hasPrefix:@"/mst-viewer"] || [request.path hasPrefix:@"/api/mst"];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    PDS_LOG_DEBUG(@"MSTViewerHandler: %@", path);

    if ([path isEqualToString:@"/mst-viewer"] || [path isEqualToString:@"/mst-viewer/"]) {
        [self serveIndex:response];
    }
    else if ([path hasPrefix:@"/mst-viewer/css/"]) {
        [self serveCss:request response:response];
    }
    else if ([path hasPrefix:@"/mst-viewer/js/"]) {
        [self serveJs:request response:response];
    }
    else if ([path hasPrefix:@"/api/mst/"]) {
        NSString *endpoint = [[path substringFromIndex:9] copy];  // Skip "/api/mst/"
        [self handleApiRequest:request response:response endpoint:endpoint];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Not Found", @"path": path}];
    }
}

#pragma mark - Static File Serving

- (void)serveIndex:(HttpResponse *)response {
    NSString *html = [self loadAsset:@"index.html"];
    if (html) {
        response.statusCode = HttpStatusOK;
        [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
        [response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setBody:[@"index.html not found" dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (void)serveCss:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *filename = [request.path lastPathComponent];
    NSString *content = [self loadAsset:[NSString stringWithFormat:@"css/%@", filename]];
    if (content) {
        response.statusCode = HttpStatusOK;
        [response setBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [response setHeader:@"Content-Type" value:@"text/css; charset=utf-8"];
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setBody:[[NSString stringWithFormat:@"CSS file not found: %@", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (void)serveJs:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *filename = [request.path lastPathComponent];
    NSString *content = [self loadAsset:[NSString stringWithFormat:@"js/%@", filename]];
    if (content) {
        response.statusCode = HttpStatusOK;
        [response setBody:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [response setHeader:@"Content-Type" value:@"application/javascript; charset=utf-8"];
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setBody:[[NSString stringWithFormat:@"JS file not found: %@", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (nullable NSString *)loadAsset:(NSString *)relativePath {
    // Search multiple paths like ExploreHandler does
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSArray *searchPaths = @[
        [cwd stringByAppendingPathComponent:[NSString stringWithFormat:@"ATProtoPDS/Sources/App/MSTViewer/Assets/%@", relativePath]],
        [cwd stringByAppendingPathComponent:[NSString stringWithFormat:@"Sources/App/MSTViewer/Assets/%@", relativePath]],
        [[cwd stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"ATProtoPDS/Sources/App/MSTViewer/Assets/%@", relativePath]],
        [NSString stringWithFormat:@"/usr/local/share/atprotopds/mst-viewer/%@", relativePath]
    ];

    for (NSString *path in searchPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSError *error = nil;
            NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
            if (!error && content) {
                return content;
            }
        }
    }

    return nil;
}

#pragma mark - API Request Handling

- (void)handleApiRequest:(HttpRequest *)request response:(HttpResponse *)response endpoint:(NSString *)endpoint {
    PDS_LOG_DEBUG(@"MST API: %@", endpoint);

    if ([endpoint isEqualToString:@"accounts"]) {
        [self handleAccountsRequest:response];
    }
    else if ([endpoint hasPrefix:@"tree/"]) {
        NSString *did = [endpoint substringFromIndex:5];  // Skip "tree/"
        [self handleTreeRequest:did response:response];
    }
    else if ([endpoint hasPrefix:@"stats/"]) {
        NSString *did = [endpoint substringFromIndex:6];  // Skip "stats/"
        [self handleStatsRequest:did response:response];
    }
    else if ([endpoint hasPrefix:@"export/"]) {
        NSString *remainder = [endpoint substringFromIndex:7];  // Skip "export/"
        NSString *did = remainder;
        NSString *format = [request.queryParams objectForKey:@"format"] ?: @"json";
        [self handleExportRequest:did format:format response:response];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Unknown API endpoint", @"endpoint": endpoint}];
    }
}

#pragma mark - API Endpoint Implementations

- (void)handleAccountsRequest:(HttpResponse *)response {
    // Check cache
    NSArray *cached = [self.cache objectForKey:@"accounts"];
    if (cached) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"accounts": cached}];
        return;
    }

    if (!self.controller || !self.controller.database) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"Database not available"}];
        return;
    }

    // Query database for all accounts
    NSError *error = nil;
    __block NSMutableArray *accounts = [NSMutableArray array];

    [self.controller.database executeInTransaction:^(sqlite3 *db, NSError **txError) {
        const char *sql = "SELECT did, handle FROM accounts ORDER BY created_at DESC LIMIT 1000";
        sqlite3_stmt *stmt = NULL;

        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *didBytes = (const char *)sqlite3_column_text(stmt, 0);
                const char *handleBytes = (const char *)sqlite3_column_text(stmt, 1);

                NSString *did = didBytes ? [NSString stringWithUTF8String:didBytes] : @"";
                NSString *handle = handleBytes ? [NSString stringWithUTF8String:handleBytes] : @"";

                [accounts addObject:@{
                    @"did": did,
                    @"handle": handle.length > 0 ? handle : did
                }];
            }
            sqlite3_finalize(stmt);
        } else {
            *txError = [NSError errorWithDomain:@"MSTViewerHandler"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to query accounts"}];
        }
    } error:&error];

    if (error) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }

    // Cache for 2 minutes
    [self.cache setObject:accounts forKey:@"accounts"];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"accounts": accounts}];
}

- (void)handleTreeRequest:(NSString *)did response:(HttpResponse *)response {
    // Check cache
    NSString *cacheKey = [NSString stringWithFormat:@"tree:%@", did];
    NSDictionary *cached = [self.cache objectForKey:cacheKey];
    if (cached) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:cached];
        return;
    }

    // Load MST from repository service
    MST *mst = [self loadMSTForDid:did];
    if (!mst) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"MST not found", @"did": did}];
        return;
    }

    // Convert to JSON
    NSDictionary *treeJSON = [mst toJSON];
    if (!treeJSON) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"Failed to serialize MST", @"did": did}];
        return;
    }

    // Cache for 60 seconds
    [self.cache setObject:treeJSON forKey:cacheKey];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:treeJSON];
}

- (void)handleStatsRequest:(NSString *)did response:(HttpResponse *)response {
    // Check cache
    NSString *cacheKey = [NSString stringWithFormat:@"stats:%@", did];
    NSDictionary *cached = [self.cache objectForKey:cacheKey];
    if (cached) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:cached];
        return;
    }

    // Load MST
    MST *mst = [self loadMSTForDid:did];
    if (!mst) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"MST not found", @"did": did}];
        return;
    }

    // Get statistics
    NSDictionary *stats = [mst getStatistics];

    // Cache for 60 seconds
    [self.cache setObject:stats forKey:cacheKey];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:stats];
}

- (void)handleExportRequest:(NSString *)did format:(NSString *)format response:(HttpResponse *)response {
    // Load MST
    MST *mst = [self loadMSTForDid:did];
    if (!mst) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"MST not found", @"did": did}];
        return;
    }

    if ([format isEqualToString:@"json"]) {
        NSDictionary *treeJSON = [mst toJSON];
        if (!treeJSON) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"Failed to serialize MST"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:treeJSON];
        [response setHeader:@"Content-Disposition"
                      value:[NSString stringWithFormat:@"attachment; filename=\"mst-%@.json\"",
                            [did substringToIndex:MIN(16, did.length)]]];
    }
    else if ([format isEqualToString:@"dot"]) {
        NSString *dotString = [mst toDOT];
        if (!dotString) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"Failed to generate DOT format"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setBody:[dotString dataUsingEncoding:NSUTF8StringEncoding]];
        [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
        [response setHeader:@"Content-Disposition"
                      value:[NSString stringWithFormat:@"attachment; filename=\"mst-%@.dot\"",
                            [did substringToIndex:MIN(16, did.length)]]];
    }
    else if ([format isEqualToString:@"svg"]) {
        // For SVG, return DOT format and let client convert
        // (Graphviz conversion would require system dependency)
        NSString *dotString = [mst toDOT];
        if (!dotString) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"Failed to generate DOT format"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"format": @"dot",
            @"content": dotString,
            @"message": @"SVG generation requires Graphviz on client"
        }];
    }
    else {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"Invalid format", @"format": format}];
    }
}

#pragma mark - Helper Methods

- (nullable MST *)loadMSTForDid:(NSString *)did {
    if (!self.controller || !self.controller.database) {
        return nil;
    }

    PDSRepositoryService *repoService = [[PDSRepositoryService alloc] initWithDatabase:self.controller.database];
    if (!repoService) {
        return nil;
    }

    NSError *error = nil;
    MST *mst = [repoService loadMSTForDid:did error:&error];

    if (error) {
        PDS_LOG_ERROR(@"Failed to load MST for %@: %@", did, error.localizedDescription);
        return nil;
    }

    return mst;
}

@end
