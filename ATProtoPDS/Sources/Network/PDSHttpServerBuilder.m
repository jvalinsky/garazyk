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
        if (configuration) {
            _port = configuration.serverPort > 0 ? configuration.serverPort : 2583;
            _enableNodeInfo = configuration.nodeinfoEnabled;
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
        XrpcDispatcher *strongDispatcher = weakDispatcher;
        if (strongDispatcher) {
            [strongDispatcher handleRequest:request response:response];
        } else {
            response.statusCode = 503;
            [response setJsonBody:@{@"error": @"ServiceUnavailable", @"message": @"Server is shutting down"}];
        }
    }];

    // Handler for /xrpc/:method
    [server addRoute:@"*" path:@"/xrpc/:method" handler:^(HttpRequest *request, HttpResponse *response) {
        XrpcDispatcher *strongDispatcher = weakDispatcher;
        if (strongDispatcher) {
            [strongDispatcher handleRequest:request response:response];
        } else {
            response.statusCode = 503;
            [response setJsonBody:@{@"error": @"ServiceUnavailable", @"message": @"Server is shutting down"}];
        }
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

    // Use configured issuer or generate from port
    NSString *issuer = self.issuer;
    if (!issuer) {
        issuer = [NSString stringWithFormat:@"https://localhost:%lu", (unsigned long)self.port];
    }

    [nodeInfoHandler setIssuer:issuer];
    if (self.controller) {
        [nodeInfoHandler setController:self.controller];
    } else if (self.application) {
        // NodeInfoHandler expects controller, but we can pass application if it has a controller facade
        [nodeInfoHandler setController:self.application];
    }
    [nodeInfoHandler setConfigured];
    [nodeInfoHandler registerRoutesWithServer:server];

    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: NodeInfo routes registered");
}

- (void)registerAdminRoutesWithServer:(HttpServer *)server {
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

    [server addRoute:@"POST" path:@"/admin/login" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *result = [adminHandler handleRequestWithMethod:PDSHTTPMethodPOST
                                                            path:@"/admin/login"
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

    [server addRoute:@"POST" path:@"/admin/logout" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *result = [adminHandler handleRequestWithMethod:PDSHTTPMethodPOST
                                                            path:@"/admin/logout"
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

    PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Admin routes registered");
}

@end
