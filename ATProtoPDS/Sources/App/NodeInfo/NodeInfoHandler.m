#import "NodeInfoHandler.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "App/PDSConfiguration.h"
#import "NodeInfoProvider.h"
#import "NodeInfoSchemas.h"
#import "Debug/PDSLogger.h"

@interface NodeInfoHandler ()
@property (nonatomic, strong) NodeInfoProvider *provider;
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, weak) PDSController *controller;
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
        _controller = nil;
    }
    return self;
}

- (void)setIssuer:(NSString *)issuer {
    _issuer = [issuer copy];
    [self updateProvider];
}

- (void)setController:(PDSController *)controller {
    _controller = controller;
    [self updateProvider];
}

- (void)updateProvider {
    if (!_issuer || !_controller) {
        return;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    if (!config) {
        return;
    }

    _provider = [[NodeInfoProvider alloc] initWithBaseURL:_issuer configuration:config];
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
    [response setHeader:@"application/json; charset=utf-8" forKey:@"Content-Type"];
    [response setJsonBody:self.provider.discoveryDocument21];
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
    [response setHeader:@"application/json; profile=\"http://nodeinfo.diaspora.software/ns/schema/2.0#\"" forKey:@"Content-Type"];
    [response setJsonBody:self.provider.nodeInfo20];
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
    [response setHeader:@"application/json; profile=\"http://nodeinfo.diaspora.software/ns/schema/2.1#\"" forKey:@"Content-Type"];
    [response setJsonBody:self.provider.nodeInfo21];
    response.statusCode = 200;
}

@end
