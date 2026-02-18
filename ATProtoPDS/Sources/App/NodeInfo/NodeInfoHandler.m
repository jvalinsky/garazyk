#import "NodeInfoHandler.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSConfiguration.h"
#import "NodeInfoProvider.h"
#import "NodeInfoSchemas.h"
#import "Debug/PDSLogger.h"

@interface NodeInfoHandler ()
@property (nonatomic, strong) NodeInfoProvider *provider;
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, weak) id controller;
@property (nonatomic, assign) BOOL configured;
@end

@implementation NodeInfoHandler

+ (instancetype)sharedHandler {
    static NodeInfoHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[NodeInfoHandler alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _provider = nil;
        _issuer = nil;
        _configured = NO;
    }
    return self;
}

- (void)setIssuer:(NSString *)issuer {
    _issuer = [issuer copy];
    [self updateProvider];
}

- (void)setConfigured {
    _configured = YES;
    [self updateProvider];
}

- (void)setController:(id)controller {
    _controller = controller;
    _configured = (controller != nil);
    [self updateProvider];
}

- (void)updateProvider {
    if (!_issuer || !_configured) {
        return;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    if (!config) {
        return;
    }

    _provider = [[NodeInfoProvider alloc] initWithBaseURL:_issuer configuration:config];
    
    // Fetch stats if controller is available
    if ([self.controller respondsToSelector:@selector(accountService)]) {
        id accountService = [self.controller performSelector:@selector(accountService)];
        if ([accountService respondsToSelector:@selector(getAllAccountsWithError:)]) {
            NSError *error = nil;
            NSArray *accounts = [accountService performSelector:@selector(getAllAccountsWithError:) withObject:nil];
            if (accounts) {
                _provider.totalUsers = accounts.count;
                // Currently setting posts/comments to 0 as they are fediverse concepts, 
                // but we could count specific ATProto records here if needed.
                _provider.localPosts = 0; 
                _provider.localComments = 0;
            }
        }
    }
    
    [_provider refreshUsageStatistics];
}

- (void)registerRoutesWithServer:(HttpServer *)httpServer {
    if (!httpServer) {
        PDS_LOG_CORE_ERROR(@"Cannot register routes with nil server");
        return;
    }

    __weak typeof(self) weakSelf = self;

    [httpServer addRoute:@"GET" path:@"/.well-known/nodeinfo" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleDiscoveryRequest:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/nodeinfo/2.0" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleNodeInfo20Request:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/nodeinfo/2.1" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleNodeInfo21Request:request response:response];
    }];

    PDS_LOG_CORE_INFO(@"NodeInfo routes registered");
}

- (void)handleDiscoveryRequest:(HttpRequest *)request response:(HttpResponse *)response {
    if (!response) {
        return;
    }

    if (!self.provider) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"NodeInfo not configured"}];
        return;
    }

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:self.provider.discoveryDocument21];
    response.contentType = @"application/json; charset=utf-8";
    response.statusCode = 200;
}

- (void)handleNodeInfo20Request:(HttpRequest *)request response:(HttpResponse *)response {
    if (!response) {
        return;
    }

    if (!self.provider) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"NodeInfo not configured"}];
        return;
    }

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:self.provider.nodeInfo20];
    response.contentType = @"application/json; profile=\"http://nodeinfo.diaspora.software/ns/schema/2.0#\"";
    response.statusCode = 200;
}

- (void)handleNodeInfo21Request:(HttpRequest *)request response:(HttpResponse *)response {
    if (!response) {
        return;
    }

    if (!self.provider) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"NodeInfo not configured"}];
        return;
    }

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:self.provider.nodeInfo21];
    response.contentType = @"application/json; profile=\"http://nodeinfo.diaspora.software/ns/schema/2.1#\"";
    response.statusCode = 200;
}

@end
