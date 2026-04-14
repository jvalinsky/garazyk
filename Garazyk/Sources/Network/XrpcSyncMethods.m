#import "Network/XrpcSyncMethods.h"
#import "App/PDSConfiguration.h"
#import "App/Services/PDSBlobService.h"
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSRelayService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Auth/JWT.h"
#import "Compat/PDSTypes.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Repository/CAR.h"
#import "Repository/MST.h"
#import "Blob/BlobStorage.h"

static NSString *trimmedNonEmptyString(NSString *value);
static BOOL parseStrictIntegerString(NSString *value, NSInteger *result);
static void setSubscribeReposUpgradeRequired(HttpRequest *request,
                                             HttpResponse *response);
static NSString *normalizedHostnameString(NSString *hostInput);
static NSDictionary *localSyncHostEntry(PDSServiceDatabases *serviceDatabases,
                                        PDSConfiguration *config);

static NSString *trimmedNonEmptyString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseStrictIntegerString(NSString *value, NSInteger *result) {
  NSString *trimmed = trimmedNonEmptyString(value);
  if (trimmed.length == 0) {
    return NO;
  }

  NSScanner *scanner = [NSScanner scannerWithString:trimmed];
  scanner.charactersToBeSkipped = nil;

  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
    return NO;
  }

  if (result) {
    *result = parsed;
  }
  return YES;
}

static void setSubscribeReposUpgradeRequired(HttpRequest *request,
                                             HttpResponse *response) {
  if (request.method != HttpMethodGET) {
    response.statusCode = HttpStatusMethodNotAllowed;
    [response setHeader:@"GET" forKey:@"Allow"];
    [response setJsonBody:@{
      @"error" : @"MethodNotAllowed",
      @"message" : @"subscribeRepos only supports GET"
    }];
    return;
  }

  response.statusCode = 426;
  [response setHeader:@"websocket" forKey:@"Upgrade"];
  [response setHeader:@"Upgrade" forKey:@"Connection"];
  [response setJsonBody:@{
    @"error" : @"UpgradeRequired",
    @"message" : @"WebSocket upgrade required for subscribeRepos"
  }];
  response.keepAlive = NO;
}

static NSString *normalizedHostnameString(NSString *hostInput) {
  if (![hostInput isKindOfClass:[NSString class]]) {
    return @"localhost";
  }

  NSString *trimmed = [hostInput
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    return @"localhost";
  }

  // If it's already a DID or something else, return it as is but lowercased
  if ([trimmed hasPrefix:@"did:"]) {
    return [trimmed lowercaseString];
  }

  NSString *urlString = trimmed;
  // If it's just a hostname, componentsWithString: might fail to find the host.
  // We ensure it has a scheme for reliable parsing.
  if ([trimmed rangeOfString:@"://"].location == NSNotFound) {
    urlString = [@"https://" stringByAppendingString:trimmed];
  }

  NSURLComponents *components =
      [NSURLComponents componentsWithString:urlString];
  
  // host returns the hostname portion without ports or paths.
  NSString *hostname = components.host;
  
  // Fallback if NSURLComponents failed to parse a host
  if (hostname.length == 0) {
      // Manual split for port if present
      if ([trimmed containsString:@":"]) {
          hostname = [[trimmed componentsSeparatedByString:@":"] firstObject];
      } else {
          hostname = trimmed;
      }
  }

  if ([[hostname lowercaseString] isEqualToString:@"0.0.0.0"]) {
    return @"localhost";
  }
  return [hostname lowercaseString];
}

static NSDictionary *localSyncHostEntry(PDSServiceDatabases *serviceDatabases,
                                        PDSConfiguration *config) {
  NSError *accountsError = nil;
  NSArray<PDSDatabaseAccount *> *accounts =
      [serviceDatabases getAllAccountsWithError:&accountsError];
  NSInteger accountCount = accounts ? (NSInteger)accounts.count : 0;
  return @{
    @"hostname" : normalizedHostnameString(config.serverHost ?: @"localhost"),
    @"seq" : @0,
    @"accountCount" : @(MAX(accountCount, 0)),
    @"status" : @"active"
  };
}

@implementation XrpcSyncMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
                  relayService:(PDSRelayService *)relayService
                 configuration:(PDSConfiguration *)config {
  (void)relayService;

  // com.atproto.sync.getRepo
  [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *request,
                                              HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    NSString *sinceRev = [request queryParamForKey:@"since"];
    if (did.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did"
      }];
      return;
    }

    NSError *exportError = nil;
    PDSRepoChunkProducer producer =
        [repositoryService repoContentsChunkProducer:did
                                               since:sinceRev
                                               error:&exportError];
    if (!producer) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : exportError.localizedDescription ?: @"Repository not found"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    response.contentType = @"application/vnd.ipld.car";
    [response setBodyChunkProducer:producer chunkedTransferEncoding:YES];
  }];

  // com.atproto.sync.getCheckout
  [dispatcher registerComAtprotoSyncGetCheckout:^(HttpRequest *request,
                                                  HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    if (did.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did"
      }];
      return;
    }

    NSError *error = nil;
    NSData *repoData =
        [repositoryService getRepoContents:did since:nil error:&error];
    if (!repoData || error) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : error.localizedDescription ?: @"Repository not found"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    response.contentType = @"application/vnd.ipld.car";
    [response setBodyData:repoData];
  }];

  // com.atproto.sync.getHead
  [dispatcher registerComAtprotoSyncGetHead:^(HttpRequest *request,
                                              HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                   jwtMinter:jwtMinter
                                             adminController:adminController
                                                     request:request
                                                    response:response];
    if (!did) {
      if (response.statusCode == HttpStatusOK) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
          @"error" : @"AuthRequired",
          @"message" : @"Valid authorization required"
        }];
      }
      return;
    }

    NSError *error = nil;
    NSDictionary *latest =
        [repositoryService getLatestCommitForDid:did error:&error];
    if (error || !latest) {
      response.statusCode = 404;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : @"Repository not found"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"root" : latest[@"cid"] ?: @""}];
  }];

  // com.atproto.sync.getLatestCommit
  [dispatcher registerComAtprotoSyncGetLatestCommit:^(HttpRequest *request,
                                                      HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    if (did.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing required parameter: did"
      }];
      return;
    }

    NSError *error = nil;
    NSDictionary *latest =
        [repositoryService getLatestCommitForDid:did error:&error];
    if (error || !latest) {
      response.statusCode = 404;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" :
            [NSString stringWithFormat:@"Could not find root for DID: %@", did]
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
      @"cid" : latest[@"cid"] ?: @"",
      @"rev" : latest[@"rev"] ?: @""
    }];
  }];

  // com.atproto.sync.getBlocks
  [dispatcher registerComAtprotoSyncGetBlocks:^(HttpRequest *request,
                                                HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    NSArray<NSString *> *cids = [request queryParamsForKey:@"cids"];
    if (did.length == 0 || cids.count == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did or cids parameter"
      }];
      return;
    }

    NSError *error = nil;
    NSData *blocksData =
        [repositoryService getBlocksForDid:did cids:cids error:&error];
    if (error || !blocksData) {
      response.statusCode = 404;
      [response setJsonBody:@{
        @"error" : @"BlocksNotFound",
        @"message" : error.localizedDescription ?: @"Blocks not found"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    response.contentType = @"application/vnd.ipld.car";
    [response setBodyData:blocksData];
  }];

  // com.atproto.sync.getHostStatus
  [dispatcher registerComAtprotoSyncGetHostStatus:^(HttpRequest *request,
                                                    HttpResponse *response) {
    NSString *hostnameParam = [request queryParamForKey:@"hostname"];
    if (hostnameParam.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing hostname"
      }];
      return;
    }

    NSDictionary *hostEntry = localSyncHostEntry(serviceDatabases, config);
    NSString *requested = normalizedHostnameString(hostnameParam);
    NSString *local = hostEntry[@"hostname"];
    if (![requested isEqualToString:local]) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"HostNotFound",
        @"message" : @"Host not found"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:hostEntry];
  }];

  // com.atproto.sync.listHosts
  [dispatcher registerComAtprotoSyncListHosts:^(HttpRequest *request,
                                                HttpResponse *response) {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 200;
    if (limitParam.length > 0) {
      if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 ||
          limit > 1000) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"limit must be an integer between 1 and 1000"
        }];
        return;
      }
    }

    NSString *cursorParam = [request queryParamForKey:@"cursor"];
    NSInteger startIndex = 0;
    if (cursorParam.length > 0) {
      if (!parseStrictIntegerString(cursorParam, &startIndex) ||
          startIndex < 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"cursor must be a non-negative integer"
        }];
        return;
      }
    }

    NSDictionary *hostEntry = localSyncHostEntry(serviceDatabases, config);
    NSMutableArray<NSDictionary *> *hosts = [NSMutableArray array];
    NSInteger totalHosts = 1;
    NSInteger scanIndex = MIN(startIndex, totalHosts);
    while (scanIndex < totalHosts && hosts.count < (NSUInteger)limit) {
      [hosts addObject:hostEntry];
      scanIndex += 1;
    }

    NSMutableDictionary *result =
        [NSMutableDictionary dictionaryWithObject:hosts forKey:@"hosts"];
    if (scanIndex < totalHosts) {
      result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  // com.atproto.sync.listRepos
  [dispatcher registerComAtprotoSyncListRepos:^(HttpRequest *request,
                                                HttpResponse *response) {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 500;
    if (limitParam.length > 0) {
      if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 ||
          limit > 1000) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"limit must be an integer between 1 and 1000"
        }];
        return;
      }
    }

    NSString *cursorParam = [request queryParamForKey:@"cursor"];
    NSInteger startIndex = 0;
    if (cursorParam.length > 0) {
      if (!parseStrictIntegerString(cursorParam, &startIndex) ||
          startIndex < 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"cursor must be a non-negative integer"
        }];
        return;
      }
    }

    NSError *accountsError = nil;
    NSArray<PDSDatabaseAccount *> *accounts =
        [serviceDatabases getAllAccountsWithError:&accountsError];
    if (!accounts) {
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"DatabaseUnavailable",
        @"message" : accountsError.localizedDescription
            ?: @"Failed to load accounts"
      }];
      return;
    }

    NSMutableArray<NSDictionary *> *repos = [NSMutableArray array];
    NSInteger scanIndex = MIN(startIndex, (NSInteger)accounts.count);
    while (scanIndex < (NSInteger)accounts.count &&
           repos.count < (NSUInteger)limit) {
      PDSDatabaseAccount *account = accounts[(NSUInteger)scanIndex];
      if (account.did.length > 0) {
        NSDictionary *latest =
            [repositoryService getLatestCommitForDid:account.did error:nil];
        if (!latest) {
          scanIndex += 1;
          continue;
        }

        NSString *head = [latest[@"cid"] isKindOfClass:[NSString class]]
                             ? latest[@"cid"]
                             : nil;
        NSString *rev = [latest[@"rev"] isKindOfClass:[NSString class]]
                            ? latest[@"rev"]
                            : @"";
        if (head.length > 0) {
          [repos addObject:@{
            @"did" : account.did,
            @"head" : head,
            @"rev" : rev,
            @"active" : @YES
          }];
        }
      }
      scanIndex += 1;
    }

    NSMutableDictionary *result =
        [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
    if (scanIndex < (NSInteger)accounts.count) {
      result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  // com.atproto.sync.listReposByCollection
  [dispatcher registerComAtprotoSyncListReposByCollection:^(
                  HttpRequest *request, HttpResponse *response) {
    NSString *collection = [request queryParamForKey:@"collection"];
    if (collection.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing collection"
      }];
      return;
    }

    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : nsidError.localizedDescription ?: @"Invalid collection"
      }];
      return;
    }

    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 500;
    if (limitParam.length > 0) {
      if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 ||
          limit > 2000) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"limit must be an integer between 1 and 2000"
        }];
        return;
      }
    }

    NSString *cursorParam = [request queryParamForKey:@"cursor"];
    NSInteger startIndex = 0;
    if (cursorParam.length > 0) {
      if (!parseStrictIntegerString(cursorParam, &startIndex) ||
          startIndex < 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
          @"error" : @"InvalidRequest",
          @"message" : @"cursor must be a non-negative integer"
        }];
        return;
      }
    }

    NSError *accountsError = nil;
    NSArray<PDSDatabaseAccount *> *accounts =
        [serviceDatabases getAllAccountsWithError:&accountsError];
    if (!accounts) {
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"DatabaseUnavailable",
        @"message" : accountsError.localizedDescription
            ?: @"Failed to load accounts"
      }];
      return;
    }

    NSMutableArray<NSDictionary *> *repos = [NSMutableArray array];
    NSInteger scanIndex = MIN(startIndex, (NSInteger)accounts.count);
    while (scanIndex < (NSInteger)accounts.count &&
           repos.count < (NSUInteger)limit) {
      PDSDatabaseAccount *account = accounts[(NSUInteger)scanIndex];
      if (account.did.length > 0) {
        NSError *storeError = nil;
        PDSActorStore *store =
            [userDatabasePool storeForDid:account.did error:&storeError];
        if (store) {
          NSArray<PDSDatabaseRecord *> *records =
              [store listRecordsForDid:account.did
                            collection:collection
                                 limit:1
                                offset:0
                                 error:nil];
          if (records.count > 0) {
            [repos addObject:@{@"did" : account.did}];
          }
        }
      }
      scanIndex += 1;
    }

    NSMutableDictionary *result =
        [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
    if (scanIndex < (NSInteger)accounts.count) {
      result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  // com.atproto.sync.listBlobs
  [dispatcher registerComAtprotoSyncListBlobs:^(HttpRequest *request,
                                                HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                   jwtMinter:jwtMinter
                                             adminController:adminController
                                                     request:request
                                                    response:response];
    if (!did) {
      if (response.statusCode == HttpStatusOK) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
          @"error" : @"AuthRequired",
          @"message" : @"Valid authorization required"
        }];
      }
      return;
    }

    NSString *limitStr = [request queryParamForKey:@"limit"];
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSUInteger limit = limitStr ? [limitStr integerValue] : 500;
    if (limit > 1000) {
      limit = 1000;
    }

    NSError *error = nil;
    NSArray *blobs = [blobService listBlobsForDID:did
                                            limit:limit
                                           cursor:cursor
                                            error:&error];
    if (error) {
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"ListBlobsFailed",
        @"message" : error.localizedDescription
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"blobs" : blobs ?: @[]}];
  }];

  // com.atproto.sync.getBlob
  [dispatcher registerComAtprotoSyncGetBlob:^(HttpRequest *request,
                                              HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    NSString *cid = [request queryParamForKey:@"cid"];
    if (did.length == 0 || cid.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did or cid"
      }];
      return;
    }

    // Check if CDN redirect is enabled (Phase 5)
    NSString *cdnURL = config.cdnURL;
    if (cdnURL && cdnURL.length > 0) {
      // Return 302 Found redirect to CDN URL
      NSString *cdnBlobURL = [NSString stringWithFormat:@"%@/%@", cdnURL, cid];
      response.statusCode = 302; // Found (temporary redirect)
      [response setHeader:cdnBlobURL forKey:@"Location"];
      [response setJsonBody:@{
        @"message" : @"Blob available at CDN",
        @"location" : cdnBlobURL
      }];
      return;
    }

    NSError *blobError = nil;
    NSDictionary *result =
        [blobService getBlobStreamWithCID:cid did:did error:&blobError];
    if (!result && !blobError) {
      result = [blobService getBlobWithCID:cid did:did error:&blobError];
    }
    if (!result) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"BlobRetrievalFailed",
        @"message" : blobError.localizedDescription ?: @"Blob not found"
      }];
      return;
    }

    NSString *mimeType = result[@"mimeType"] ?: @"application/octet-stream";
    NSString *filePath = result[@"filePath"];
    NSData *blobData = result[@"blob"];
    unsigned long long totalLength = [result[@"size"] unsignedLongLongValue];

    if (totalLength == 0 && [filePath isKindOfClass:[NSString class]] &&
        filePath.length > 0) {
      NSDictionary *attributes =
          [[NSFileManager defaultManager] attributesOfItemAtPath:filePath
                                                           error:nil];
      totalLength = [attributes[NSFileSize] unsignedLongLongValue];
    }
    if (totalLength == 0 && [blobData isKindOfClass:[NSData class]]) {
      totalLength = blobData.length;
    }

    response.contentType = mimeType;

    // Use shared blob response handler with Range support (Phase 1.2)
    NSError *responseError = nil;
    if (![blobService.blobStorage respondWithBlobData:blobData
                                             filePath:filePath
                                          totalLength:totalLength
                                           forRequest:request
                                             response:response
                                                error:&responseError]) {
      if (response.statusCode == HttpStatusOK) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error" : @"BlobReadFailed",
                                @"message" : @"Failed to send blob"}];
      }
    }
  }];

  // com.atproto.sync.subscribeRepos
  [dispatcher registerComAtprotoSyncSubscribeRepos:^(HttpRequest *request,
                                                     HttpResponse *response) {
    setSubscribeReposUpgradeRequired(request, response);
  }];

  // com.atproto.sync.getRecord
  [dispatcher registerComAtprotoSyncGetRecord:^(HttpRequest *request,
                                                HttpResponse *response) {
    if (request.method != HttpMethodGET) {
      response.statusCode = HttpStatusMethodNotAllowed;
      [response setHeader:@"GET" forKey:@"Allow"];
      [response setJsonBody:@{
        @"error" : @"MethodNotAllowed",
        @"message" : @"Expected GET"
      }];
      return;
    }

    NSString *did = [request queryParamForKey:@"did"];
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *rkey = [request queryParamForKey:@"rkey"];
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did, collection, or rkey"
      }];
      return;
    }

    NSString *uri =
        [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSError *recordError = nil;
    NSDictionary *record =
        [recordService getRecord:uri forDid:did error:&recordError];
    if (!record) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RecordNotFound",
        @"message" : recordError.localizedDescription ?: @"Record not found"
      }];
      return;
    }

    // Build a lightweight CAR with just the commit block + record block.
    // This matches the reference TS PDS behaviour where getRecord returns
    // a narrow slice of the repo containing only the requested record.
    NSError *commitError = nil;
    NSDictionary *latestCommit =
        [repositoryService getLatestCommitForDid:did error:&commitError];
    if (!latestCommit) {
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : @"Repository not found"
      }];
      return;
    }

    CID *commitCID = [CID cidFromString:latestCommit[@"cid"]];
    if (!commitCID) {
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"InternalError",
        @"message" : @"Invalid commit CID"
      }];
      return;
    }

    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];

    // Add the commit block
    PDSActorStore *store = [userDatabasePool storeForDid:did error:nil];
    if (store) {
      NSData *commitBlock =
          [store getBlockForCID:[commitCID bytes] forDid:did error:nil];
      if (commitBlock) {
        [writer addBlock:[CARBlock blockWithCID:commitCID data:commitBlock]];
      }
    }

    // Add the record block and MST proof path
    NSString *recordCIDStr = record[@"cid"];
    if (recordCIDStr) {
      CID *recordCID = [CID cidFromString:recordCIDStr];
      if (recordCID && store) {
        NSData *blockData =
            [store getBlockForCID:[recordCID bytes] forDid:did error:nil];
        if (!blockData) {
          // Fallback: encode the record value to DAG-CBOR
          id valueObj = record[@"value"];
          if (valueObj) {
            id jsonObj = nil;
            if ([valueObj respondsToSelector:@selector(dataUsingEncoding:)]) {
              NSData *jsonData = [valueObj dataUsingEncoding:NSUTF8StringEncoding];
              if (jsonData) {
                jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
              }
            } else if ([valueObj isKindOfClass:[NSDictionary class]]) {
              jsonObj = valueObj;
            }

            if (jsonObj) {
              blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:jsonObj error:nil];
            }
          }
        }
        if (blockData) {
          [writer addBlock:[CARBlock blockWithCID:recordCID data:blockData]];
        }

        // Add MST proof path
        MST *mst = [repositoryService loadMSTForDid:did error:nil];
        if (mst) {
          NSString *mstKey =
              [NSString stringWithFormat:@"%@/%@", collection, rkey];
          NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:mstKey];

          NSMapTable<MSTNode *, CID *> *cache =
              [NSMapTable strongToStrongObjectsMapTable];
          for (MSTNode *node in proofNodes) {
            CID *nodeCID = [node getCID:cache];
            if (nodeCID) {
              NSData *nodeData = [node serializeToCBOR:cache];
              if (nodeData) {
                [writer addBlock:[CARBlock blockWithCID:nodeCID data:nodeData]];
              }
            }
          }
        }
      }
    }

    NSData *carData = [writer serialize];
    response.statusCode = HttpStatusOK;
    response.contentType = @"application/vnd.ipld.car";
    [response setBodyData:carData];
  }];

  // com.atproto.sync.requestCrawl
  [dispatcher registerComAtprotoSyncRequestCrawl:^(HttpRequest *request,
                                                   HttpResponse *response) {
    NSDictionary *body = request.jsonBody ?: @{};
    NSString *hostname = body[@"hostname"];
    if (![hostname isKindOfClass:[NSString class]] ||
        [[hostname stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            length] == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing hostname"
      }];
      return;
    }

    NSString *requestedHost = normalizedHostnameString(hostname);
    NSString *localHost = config.canonicalHostname;
    if (![requestedHost isEqualToString:localHost]) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : [NSString
            stringWithFormat:@"hostname must match this PDS host (%@)",
                             localHost]
      }];
      return;
    }

    PDS_LOG_INFO_C(@"Sync",
                   @"requestCrawl accepted for local host %@ (no relay "
                   @"forwarding)",
                   requestedHost);

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  // com.atproto.sync.notifyOfUpdate
  [dispatcher registerComAtprotoSyncNotifyOfUpdate:^(HttpRequest *request,
                                                     HttpResponse *response) {
    NSDictionary *body = request.jsonBody ?: @{};
    NSString *hostname = body[@"hostname"];
    if (![hostname isKindOfClass:[NSString class]] ||
        [[hostname stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            length] == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing hostname"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  // com.atproto.sync.getRepoStatus
  [dispatcher registerComAtprotoSyncGetRepoStatus:^(HttpRequest *request,
                                                    HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    if (did.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing did parameter"
      }];
      return;
    }

    NSError *error = nil;
    id account = [serviceDatabases getAccountByDid:did error:&error];
    if (!account) {
      PDS_LOG_DEBUG_C(@"Sync", @"Account not registered globally for DID: %@",
                      did);
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : @"Repository not found"
      }];
      return;
    }

    PDSActorStore *store = [userDatabasePool storeForDid:did error:&error];
    if (!store) {
      PDS_LOG_DEBUG_C(@"Sync", @"Actor store not found for request DID: %@",
                      did);
      response.statusCode = HttpStatusNotFound;
      [response setJsonBody:@{
        @"error" : @"RepoNotFound",
        @"message" : @"Repo not found"
      }];
      return;
    }

    __block NSString *latestRev = nil;
    [store readWithBlock:^(
               id<PDSActorStoreReader> _Nonnull reader,
               NSError *_Nullable __autoreleasing *_Nullable innerError) {
      latestRev = [reader latestMutationRevisionWithError:innerError];
    }
                   error:&error];

    if (error) {
      PDS_LOG_ERROR_C(@"Sync", @"Error reading actor store: %@",
                      error.localizedDescription);
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"InternalServerError",
        @"message" : @"Internal server error"
      }];
      return;
    }

    NSMutableDictionary *jsonBody = [NSMutableDictionary dictionary];
    jsonBody[@"did"] = did;
    jsonBody[@"active"] = @YES;

    if (latestRev) {
      jsonBody[@"rev"] = latestRev;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:jsonBody];
  }];
}

@end
