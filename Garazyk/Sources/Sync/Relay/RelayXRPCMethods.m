#import "Sync/Relay/RelayXRPCMethods.h"
#import "Sync/Relay/RelayConfiguration.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayEventBuffer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcHandler.h"
#import "Debug/PDSLogger.h"

static NSString *normalizedHostnameString(NSString *hostInput);

static NSString *normalizedHostnameString(NSString *hostInput) {
  if (![hostInput isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *normalized = [hostInput lowercaseString];
  normalized = [normalized stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized hasPrefix:@"https://"]) {
    normalized = [normalized substringFromIndex:8];
  } else if ([normalized hasPrefix:@"http://"]) {
    normalized = [normalized substringFromIndex:7];
  }
  if ([normalized hasPrefix:@"www."]) {
    normalized = [normalized substringFromIndex:4];
  }
  NSURL *url = [NSURL URLWithString:
                    [NSString stringWithFormat:@"https://%@", normalized]];
  return url.host;
}

@interface RelayXRPCMethods ()
@property (nonatomic, strong, readwrite) RelayConfiguration *configuration;
@property (nonatomic, strong, readwrite) RelayRepoStateManager *repoStateManager;
@property (nonatomic, strong, readwrite) RelayEventBuffer *eventBuffer;
@end

@implementation RelayXRPCMethods

- (instancetype)initWithConfiguration:(RelayConfiguration *)configuration
                     repoStateManager:(RelayRepoStateManager *)repoStateManager
                          eventBuffer:(RelayEventBuffer *)eventBuffer {
  self = [super init];
  if (self) {
    _configuration = configuration;
    _repoStateManager = repoStateManager;
    _eventBuffer = eventBuffer;
  }
  return self;
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                   configuration:(RelayConfiguration *)configuration
                repoStateManager:(RelayRepoStateManager *)repoStateManager
                     eventBuffer:(RelayEventBuffer *)eventBuffer {
  RelayXRPCMethods *methods = [[RelayXRPCMethods alloc] initWithConfiguration:configuration
                                                               repoStateManager:repoStateManager
                                                                    eventBuffer:eventBuffer];
  
  [dispatcher registerComAtprotoSyncGetHead:^(HttpRequest *request,
                                               HttpResponse *response) {
    [methods handleGetHead:request response:response];
  }];
  
  [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *request,
                                               HttpResponse *response) {
    [methods handleGetRepo:request response:response];
  }];
  
  [dispatcher registerComAtprotoSyncListHosts:^(HttpRequest *request,
                                                 HttpResponse *response) {
    [methods handleListHosts:request response:response];
  }];
  
  [dispatcher registerComAtprotoSyncRequestCrawl:^(HttpRequest *request,
                                                    HttpResponse *response) {
    [methods handleRequestCrawl:request response:response];
  }];
}

- (void)handleGetHead:(HttpRequest *)request response:(HttpResponse *)response {
  NSString *did = [request queryParamForKey:@"repo"];
  if (did.length == 0) {
    response.statusCode = HttpStatusBadRequest;
    [response setJsonBody:@{
      @"error": @"InvalidRequest",
      @"message": @"Missing repo parameter"
    }];
    return;
  }
  
  NSString *rootCid = [self.repoStateManager rootCIDForRepo:did];
  if (!rootCid) {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
      @"error": @"RepoNotFound",
      @"message": [NSString stringWithFormat:@"Repo %@ not found", did]
    }];
    return;
  }
  
  response.statusCode = HttpStatusOK;
  [response setJsonBody:@{
    @"repo": did,
    @"root": rootCid
  }];
}

- (void)handleGetRepo:(HttpRequest *)request response:(HttpResponse *)response {
  NSString *did = [request queryParamForKey:@"repo"];
  if (did.length == 0) {
    response.statusCode = HttpStatusBadRequest;
    [response setJsonBody:@{
      @"error": @"InvalidRequest",
      @"message": @"Missing repo parameter"
    }];
    return;
  }
  
  NSString *rootCid = [self.repoStateManager rootCIDForRepo:did];
  NSString *rev = [self.repoStateManager revForRepo:did];
  
  if (!rootCid) {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
      @"error": @"RepoNotFound",
      @"message": [NSString stringWithFormat:@"Repo %@ not found", did]
    }];
    return;
  }
  
  NSString *cursorParam = [request queryParamForKey:@"since"];
  int64_t since = 0;
  if (cursorParam.length > 0) {
    NSScanner *scanner = [NSScanner scannerWithString:cursorParam];
    [scanner scanLongLong:&since];
  }
  
  NSArray *events = [self.eventBuffer eventsAfterCursor:since count:1000];
  
  response.statusCode = HttpStatusOK;
  [response setJsonBody:@{
    @"repo": did,
    @"root": rootCid,
    @"rev": rev ?: @"0",
    @"events": events ?: @[]
  }];
}

- (void)handleListHosts:(HttpRequest *)request response:(HttpResponse *)response {
  NSString *limitParam = [request queryParamForKey:@"limit"];
  NSInteger limit = 200;
  if (limitParam.length > 0) {
    NSScanner *scanner = [NSScanner scannerWithString:limitParam];
    if (![scanner scanInteger:&limit] || limit < 1 || limit > 1000) {
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
  if (cursorParam.length > 0) {
    NSScanner *scanner = [NSScanner scannerWithString:cursorParam];
    if (![scanner scanInteger:&startIndex] || startIndex < 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error": @"InvalidRequest",
        @"message": @"cursor must be a non-negative integer"
      }];
      return;
    }
  }
  
  NSArray *allRepos = [self.repoStateManager allRepos];
  NSInteger totalHosts = allRepos.count;
  
  NSMutableArray *hosts = [NSMutableArray array];
  NSInteger scanIndex = MIN(startIndex, totalHosts);
  while (scanIndex < totalHosts && hosts.count < limit) {
    NSString *repoDid = allRepos[scanIndex];
    NSString *rootCid = [self.repoStateManager rootCIDForRepo:repoDid];
    NSString *rev = [self.repoStateManager revForRepo:repoDid];
    RelayRepoStatus status = [self.repoStateManager statusForRepo:repoDid];
    
    NSString *statusStr = @"active";
    switch (status) {
      case RelayRepoStatusActive:
        statusStr = @"active";
        break;
      case RelayRepoStatusDesynchronized:
        statusStr = @"desynchronized";
        break;
      case RelayRepoStatusInProgress:
        statusStr = @"inProgress";
        break;
      case RelayRepoStatusThrottled:
        statusStr = @"throttled";
        break;
      case RelayRepoStatusTombstoned:
        statusStr = @"tombstoned";
        break;
    }
    
    [hosts addObject:@{
      @"host": repoDid,
      @"root": rootCid ?: [NSNull null],
      @"rev": rev ?: [NSNull null],
      @"status": statusStr
    }];
    scanIndex += 1;
  }
  
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:hosts forKey:@"hosts"];
  if (scanIndex < totalHosts) {
    result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
  }
  
  response.statusCode = HttpStatusOK;
  [response setJsonBody:result];
}

- (void)handleRequestCrawl:(HttpRequest *)request response:(HttpResponse *)response {
  NSDictionary *body = request.jsonBody ?: @{};
  NSString *hostname = body[@"hostname"];
  
  if (![hostname isKindOfClass:[NSString class]] ||
      [[hostname stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]]
          length] == 0) {
    response.statusCode = HttpStatusBadRequest;
    [response setJsonBody:@{
      @"error": @"InvalidRequest",
      @"message": @"Missing hostname"
    }];
    return;
  }
  
  NSString *requestedHost = normalizedHostnameString(hostname);
  
  PDS_LOG_INFO_C(@"Relay", @"requestCrawl received for host: %@", requestedHost);
  
  response.statusCode = HttpStatusOK;
  [response setJsonBody:@{
    @"message": @"Crawl request accepted",
    @"hostname": requestedHost
  }];
}

@end
