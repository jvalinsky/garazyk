#import "RelayXrpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@implementation RelayXrpcRoutePack
{
    RelayRepoStateManager *_repoStateManager;
    SubscribeReposHandler *_subscribeReposHandler;
}

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
{
    self = [super init];
    if (self)
    {
        _repoStateManager = repoStateManager;
        _subscribeReposHandler = subscribeReposHandler;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server
{
    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.listRepos"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleListRepos:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getHead"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetHead:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getRepo"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetRepo:request response:response];
             }];

    if (_subscribeReposHandler)
    {
        [server addRoute:@"OPTIONS"
                    path:@"/xrpc/com.atproto.sync.subscribeRepos"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
                     [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
                     response.statusCode = HttpStatusOK;
                 }];

        [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                          handler:^(HttpRequest *request, HttpResponse *response,
                                    id<PDSNetworkConnection> connection) {
                              [_subscribeReposHandler acceptUpgradedConnection:connection
                                                                         request:request];
                          }];
    }
}

#pragma mark - listRepos

- (void)handleListRepos:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 100;
    if (limitParam.length > 0)
    {
        if (![[NSScanner scannerWithString:limitParam] scanInteger:&limit] || limit < 1 || limit > 1000)
        {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"limit must be an integer between 1 and 1000"
            }];
            return;
        }
    }

    NSString *cursorParam = [request queryParamForKey:@"cursor"];
    NSInteger startIndex = 0;
    if (cursorParam.length > 0)
    {
        if (![[NSScanner scannerWithString:cursorParam] scanInteger:&startIndex] || startIndex < 0)
        {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"cursor must be a non-negative integer"
            }];
            return;
        }
    }

    NSArray *allRepos = [_repoStateManager allRepos];
    NSInteger totalRepos = allRepos.count;

    NSMutableArray *repos = [NSMutableArray array];
    NSInteger scanIndex = MIN(startIndex, totalRepos);
    while (scanIndex < totalRepos && repos.count < limit)
    {
        NSString *repoDid = allRepos[(NSUInteger)scanIndex];
        NSString *rootCid = [_repoStateManager rootCIDForRepo:repoDid];
        NSString *rev = [_repoStateManager revForRepo:repoDid];
        RelayRepoStatus status = [_repoStateManager statusForRepo:repoDid];

        if (rootCid.length > 0)
        {
            [repos addObject:@{
                @"did": repoDid,
                @"head": rootCid,
                @"rev": rev ?: @"",
                @"active": @(status == RelayRepoStatusActive)
            }];
        }
        scanIndex += 1;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
    if (scanIndex < totalRepos)
    {
        result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
}

#pragma mark - getHead

- (void)handleGetHead:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *repoParam = [request queryParamForKey:@"repo"];
    if (repoParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"repo parameter is required"
        }];
        return;
    }

    NSString *rootCid = [_repoStateManager rootCIDForRepo:repoParam];
    if (!rootCid)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": [NSString stringWithFormat:@"Repo not found: %@", repoParam]
        }];
        return;
    }

    NSString *rev = [_repoStateManager revForRepo:repoParam];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"did": repoParam,
        @"head": rootCid,
        @"rev": rev ?: @""
    }];
}

#pragma mark - getRepo

- (void)handleGetRepo:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *repoParam = [request queryParamForKey:@"did"];
    if (repoParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"did parameter is required"
        }];
        return;
    }

    NSString *rootCid = [_repoStateManager rootCIDForRepo:repoParam];
    if (!rootCid)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": [NSString stringWithFormat:@"Repo not found: %@", repoParam]
        }];
        return;
    }

    NSString *rev = [_repoStateManager revForRepo:repoParam];
    RelayRepoStatus status = [_repoStateManager statusForRepo:repoParam];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"did": repoParam,
        @"head": rootCid,
        @"rev": rev ?: @"",
        @"active": @(status == RelayRepoStatusActive)
    }];
}

@end
