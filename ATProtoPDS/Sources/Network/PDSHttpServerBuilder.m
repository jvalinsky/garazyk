/*!
 @file PDSHttpServerBuilder.m

 @abstract Implementation of HTTP server builder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSHttpServerBuilder.h"
#import "HttpServer.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "XrpcHandler.h"
#import "XrpcMethodRegistry.h"
#import "PDSNetworkTransport.h"
#import "../App/PDSController.h"
#import "../App/PDSApplication.h"
#import "../App/PDSConfiguration.h"
#import "../Auth/JWT.h"
#import "../Auth/OAuth2Handler.h"
#import "../Database/Service/ServiceDatabases.h"
#import "../App/Explore/ExploreHandler.h"
#import "../App/OAuthDemo/OAuthDemoHandler.h"
#import "../App/MSTViewer/MSTViewerHandler.h"
#import "../App/NodeInfo/NodeInfoHandler.h"
#import "../Admin/PDSAdminHandler.h"
#import "../Debug/PDSLogger.h"
#import "../Sync/SubscribeReposHandler.h"

@interface PDSHttpServerBuilder ()
@property (nonatomic, strong, nullable) PDSConfiguration *configuration;
@end

@implementation PDSHttpServerBuilder

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 2583;
        _enableXrpc = YES;
        _enableOAuth = YES;
        _enableExploreUI = YES;
        _enableOAuthDemo = YES;
        _enableMSTViewer = YES;
        _enableNodeInfo = YES;
    }
    return self;
}

- (instancetype)initWithConfiguration:(PDSConfiguration *)configuration {
    self = [self init];
    if (self) {
        _configuration = configuration;
        if (configuration) {
            _port = configuration.serverPort > 0 ? configuration.serverPort : 2583;
            _enableNodeInfo = configuration.nodeinfoEnabled;
            _issuer = [configuration canonicalIssuerWithPortHint:_port];
        }
    }
    return self;
}

#pragma mark - Building

- (nullable HttpServer *)buildWithError:(NSError **)error {
    HttpServer *server = [HttpServer serverWithPort:self.port];
    
    if (![self configureServer:server error:error]) {
        return nil;
    }
    
    return server;
}

- (BOOL)configureServer:(HttpServer *)server error:(NSError **)error {
    if (!server) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSHttpServerBuilderErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server cannot be nil"}];
        }
        return NO;
    }
    
    // Register OAuth routes first (specific paths take precedence)
    if (self.enableOAuth) {
        [self registerOAuthRoutesWithServer:server];
    }
    
    // Register XRPC routes
    if (self.enableXrpc) {
        [self registerXrpcRoutesWithServer:server];
    }
    
    // Register Explore UI routes
    ExploreHandler *exploreHandler = nil;
    if (self.enableExploreUI) {
        exploreHandler = [self registerExploreRoutesWithServer:server];
    }
    
    // Register OAuth Demo routes
    if (self.enableOAuthDemo) {
        [self registerOAuthDemoRoutesWithServer:server];
    }
    
    // Register MST Viewer routes
    if (self.enableMSTViewer) {
        [self registerMSTViewerRoutesWithServer:server];
    }
    
    // Register NodeInfo routes
    if (self.enableNodeInfo) {
        [self registerNodeInfoRoutesWithServer:server];
    }

    // Register Admin routes
    [self registerAdminRoutesWithServer:server];
    
    // Register wildcard route LAST (must be after all specific routes)
    if (self.enableExploreUI && exploreHandler) {
        [server addRoute:@"GET" path:@"/*" handler:^(HttpRequest *request, HttpResponse *response) {
            [exploreHandler handleRequest:request response:response];
        }];
    }
    
    return YES;
}

#pragma mark - Route Registration (Private)

- (void)registerOAuthRoutesWithServer:(HttpServer *)server {
    if (!self.serviceDatabases || !self.jwtMinter) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth routes not registered - missing serviceDatabases or jwtMinter");
        return;
    }
    
    NSError *dbError = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&dbError];
    if (!db) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth routes not registered - could not get service database: %@", dbError);
        return;
    }
    
    OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:db];
    oauthHandler.minter = self.jwtMinter;
    oauthHandler.dataDirectory = self.dataDirectory;
    if (self.application.accountService) {
        oauthHandler.accountService = self.application.accountService;
    } else if (self.controller.accountService) {
        oauthHandler.accountService = self.controller.accountService;
    }
    [oauthHandler registerRoutesWithServer:server];
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: OAuth routes registered");
}

- (void)registerXrpcRoutesWithServer:(HttpServer *)server {
    XrpcDispatcher *dispatcher = self.xrpcDispatcher;
    if (!dispatcher) {
        dispatcher = [[XrpcDispatcher alloc] init];
    }

    if (self.application) {
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:self.application];
    } else if (self.controller) {
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher controller:self.controller];
    } else {
        PDS_LOG_ERROR(@"No application provided to PDSHttpServerBuilder for XRPC registration");
    }

    __weak XrpcDispatcher *weakDispatcher = dispatcher;
    __weak SubscribeReposHandler *weakSubscribeReposHandler = self.subscribeReposHandler;

    // Handler for /xrpc (prefix match for all XRPC methods)
    [server addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];

    // Handler for /xrpc/:method
    [server addRoute:@"*" path:@"/xrpc/:method" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];

    if (self.subscribeReposHandler) {
        [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos" handler:^(HttpRequest *request, HttpResponse *response, id<PDSNetworkConnection> connection) {
            SubscribeReposHandler *strongSubscribeReposHandler = weakSubscribeReposHandler;
            if (!strongSubscribeReposHandler) {
                [connection cancel];
                return;
            }
            [strongSubscribeReposHandler acceptUpgradedConnection:connection request:request];
        }];
    }
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: XRPC routes registered");
}

- (ExploreHandler *)registerExploreRoutesWithServer:(HttpServer *)server {
    PDSController *controller = self.controller;
    
    if (!controller) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: Explore routes not registered - missing controller");
        return nil;
    }
    
    ExploreHandler *exploreHandler = [ExploreHandler sharedHandler];
    [exploreHandler setController:controller];
    
    // API endpoint for PDS data
    [server addRoute:@"GET" path:@"/api/pds/:endpoint" handler:^(HttpRequest *request, HttpResponse *response) {
        [exploreHandler handleRequest:request response:response];
    }];
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Explore routes registered");
    
    return exploreHandler;
}

- (void)registerOAuthDemoRoutesWithServer:(HttpServer *)server {
    PDSController *controller = self.controller;
    
    if (!self.dataDirectory && !controller) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth Demo routes not registered - missing dataDirectory and controller");
        return;
    }
    
    OAuthDemoHandler *oauthDemoHandler = [OAuthDemoHandler sharedHandler];
    
    // Prefer direct data directory injection, fall back to controller
    if (self.dataDirectory) {
        [oauthDemoHandler setDataDirectory:self.dataDirectory];
    } else {
        [oauthDemoHandler setController:controller];
    }
    
    [server addHandlerForPath:@"/oauth-demo" handler:^(HttpRequest *request, HttpResponse *response) {
        [oauthDemoHandler handleRequest:request response:response];
    }];
    
    [server addRoute:@"GET" path:@"/oauth-demo/*" handler:^(HttpRequest *request, HttpResponse *response) {
        [oauthDemoHandler handleRequest:request response:response];
    }];
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: OAuth Demo routes registered");
}

- (void)registerMSTViewerRoutesWithServer:(HttpServer *)server {
    PDSController *controller = self.controller;
    
    if (!controller) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: MST Viewer routes not registered - missing controller");
        return;
    }
    
    MSTViewerHandler *mstViewerHandler = [MSTViewerHandler sharedHandler];
    [mstViewerHandler setController:controller];
    
    [server addHandlerForPath:@"/mst-viewer" handler:^(HttpRequest *request, HttpResponse *response) {
        [mstViewerHandler handleRequest:request response:response];
    }];
    
    [server addHandlerForPath:@"/api/mst" handler:^(HttpRequest *request, HttpResponse *response) {
        [mstViewerHandler handleRequest:request response:response];
    }];
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: MST Viewer routes registered");
}

- (void)registerNodeInfoRoutesWithServer:(HttpServer *)server {
    NodeInfoHandler *nodeInfoHandler = [NodeInfoHandler sharedHandler];

    // Use configured issuer if provided by caller, then shared config canonicalization.
    NSString *issuer = self.issuer;
    if (issuer.length == 0 && self.configuration) {
        issuer = [self.configuration canonicalIssuerWithPortHint:self.port];
    }
    if (issuer.length == 0) {
        issuer = [[PDSConfiguration sharedConfiguration] canonicalIssuerWithPortHint:self.port];
    }
    [nodeInfoHandler setIssuer:issuer];
    if (self.application.accountService) {
        [nodeInfoHandler setAccountService:self.application.accountService];
    } else if (self.controller.accountService) {
        [nodeInfoHandler setAccountService:self.controller.accountService];
    }
    [nodeInfoHandler setConfigured];
    [nodeInfoHandler registerRoutesWithServer:server];

    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: NodeInfo routes registered");
}

- (void)registerAdminRoutesWithServer:(HttpServer *)server {
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];
    
    NSArray *adminPaths = @[
        @"/admin",
        @"/admin/login",
        @"/admin/logout",
        @"/admin/users",
        @"/admin/invites",
        @"/admin/invites/disable",
        @"/admin/blobs",
        @"/admin/metrics",
        @"/admin/health",
        @"/admin/stats",
        @"/admin/audit-log"
    ];
    
    for (NSString *path in adminPaths) {
        [server addRoute:@"GET" path:path handler:^(HttpRequest *request, HttpResponse *response) {
            NSString *result = [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                                path:path
                                                             headers:request.headers
                                                                body:request.body];
            if (result) {
                response.statusCode = 200;
                [response setBodyString:result];
            } else {
                response.statusCode = 404;
                [response setJsonBody:@{@"error": @"Not Found"}];
            }
        }];
        
        [server addRoute:@"POST" path:path handler:^(HttpRequest *request, HttpResponse *response) {
            NSString *result = [adminHandler handleRequestWithMethod:PDSHTTPMethodPOST
                                                                path:path
                                                             headers:request.headers
                                                                body:request.body];
            if (result) {
                response.statusCode = 200;
                [response setBodyString:result];
            } else {
                response.statusCode = 404;
                [response setJsonBody:@{@"error": @"Not Found"}];
            }
        }];
    }
    
    [self registerAdminUIRoutesWithServer:server];

    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Admin routes registered");
}

- (void)registerAdminUIRoutesWithServer:(HttpServer *)server {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *assetsPath = nil;
    
    // Try multiple locations for AdminUI/Assets
    NSArray *candidates = @[
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"AdminUI/Assets"],
        [[NSBundle bundleForClass:[self class]].resourcePath stringByAppendingPathComponent:@"AdminUI/Assets"],
        [[fm currentDirectoryPath] stringByAppendingPathComponent:@"ATProtoPDS/Sources/App/AdminUI/Assets"],
        @"/Users/jack/Software/objpds/ATProtoPDS/Sources/App/AdminUI/Assets"
    ];
    
    for (NSString *candidate in candidates) {
        if ([fm fileExistsAtPath:candidate]) {
            assetsPath = candidate;
            break;
        }
    }
    
    if (!assetsPath) {
        PDS_LOG_WARN(@"PDSHttpServerBuilder: Admin UI assets not found in any candidate path");
        return;
    }
    PDS_LOG_INFO(@"PDSHttpServerBuilder: Admin UI assets found at %@", assetsPath);
    
    [server addRoute:@"GET" path:@"/admin-ui/*" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *filePath = [request.path stringByReplacingOccurrencesOfString:@"/admin-ui/" withString:@""];
        if ([filePath containsString:@".."]) {
            response.statusCode = 403;
            [response setJsonBody:@{@"error": @"Forbidden"}];
            return;
        }
        
        NSString *fullPath = [assetsPath stringByAppendingPathComponent:filePath];
        NSData *data = [NSData dataWithContentsOfFile:fullPath];
        if (data) {
            response.statusCode = 200;
            if ([filePath hasSuffix:@".js"]) {
                [response setHeader:@"application/javascript" forKey:@"Content-Type"];
            } else if ([filePath hasSuffix:@".css"]) {
                [response setHeader:@"text/css" forKey:@"Content-Type"];
            } else if ([filePath hasSuffix:@".html"]) {
                [response setHeader:@"text/html" forKey:@"Content-Type"];
            }
            [response setBodyData:data];
        } else {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"Not Found"}];
        }
    }];
    
    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Admin UI routes registered");
}

@end
