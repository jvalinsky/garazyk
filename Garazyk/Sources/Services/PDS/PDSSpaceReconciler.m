// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSSpaceReconciler.h"

#import "Auth/JWT.h"
#import "Compat/PDSTypes.h"
#import "Debug/GZLogger.h"
#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/NSDictionary+CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Repository/CAR.h"
#import "Security/Space/PDSSpaceURI.h"
#import "Services/PDS/PDSSpaceStore.h"

static const NSTimeInterval PDSSpaceReconcilerMinimumInterval = 60.0;

@interface PDSSpaceReconciler ()
@property(nonatomic, strong) PDSSpaceStore *spaceStore;
@property(nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property(nonatomic, strong) JWTMinter *jwtMinter;
@property(nonatomic, assign) NSTimeInterval interval;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG, nullable) dispatch_source_t timer;
@property(nonatomic, assign) BOOL stopped;
@end

@implementation PDSSpaceReconciler

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                   userDatabasePool:(PDSDatabasePool *)userDatabasePool
                         jwtMinter:(JWTMinter *)jwtMinter
                intervalInSeconds:(NSTimeInterval)interval {
  self = [super init];
  if (!self) return nil;
  _spaceStore = spaceStore;
  _userDatabasePool = userDatabasePool;
  _jwtMinter = jwtMinter;
  _interval = MAX(interval, PDSSpaceReconcilerMinimumInterval);
  _queue = dispatch_queue_create("com.garazyk.pds.permissioned-spaces.reconcile", DISPATCH_QUEUE_SERIAL);
  _stopped = YES;
  return self;
}

- (void)start {
  dispatch_async(self.queue, ^{
    if (!self.stopped) return;
    self.stopped = NO;
    dispatch_async(self.queue, ^{ [self reconcileOnQueue]; });
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    uint64_t intervalNanos = (uint64_t)(self.interval * (NSTimeInterval)NSEC_PER_SEC);
    dispatch_source_set_timer(self.timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNanos),
                              intervalNanos,
                              (uint64_t)(5 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.timer, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf && !strongSelf.stopped) [strongSelf reconcileOnQueue];
    });
    dispatch_resume(self.timer);
  });
}

- (void)stop {
  dispatch_sync(self.queue, ^{
    self.stopped = YES;
    if (self.timer) {
      dispatch_source_cancel(self.timer);
      self.timer = nil;
    }
  });
}

- (void)reconcileNow {
  dispatch_async(self.queue, ^{ [self reconcileOnQueue]; });
}

- (void)reconcileOnQueue {
  if (self.stopped) return;
  NSArray<NSDictionary<NSString *, id> *> *heads = [self.spaceStore repositoriesForReconciliation:nil];
  for (NSDictionary<NSString *, id> *head in heads) {
    [self replayHead:head];
    NSString *selector = [self syncRemoteRepo:head requestCounts:nil];
    if (selector) {
      GZ_LOG_SYNC_INFO(@"permissioned-space event=recovery_path selector=%@", selector);
    }
  }
}

#pragma mark - Outbound: notify authority

- (void)replayHead:(NSDictionary<NSString *, id> *)head {
  PDSSpaceURI *space = [PDSSpaceURI URIWithString:head[@"space"] error:nil];
  NSString *author = head[@"author"];
  NSString *rev = head[@"rev"];
  NSData *hash = head[@"hash"];
  if (!space || space.recordURI || author.length == 0 || rev.length == 0 || hash.length != 32 ||
      [space.authorityDID isEqualToString:author]) return;

  DIDDocument *authorityDocument = [[DIDResolver sharedResolver] resolveDIDSync:space.authorityDID error:nil];
  NSURL *endpoint = [NSURL URLWithString:[ATProtoDIDDocumentFields spaceHostEndpointFromDocument:authorityDocument] ?: @""];
  PDSActorStore *actor = [self.userDatabasePool storeForDid:author error:nil];
  NSString *token = [self.jwtMinter mintServiceAuthJWTForDID:author
                                                          aud:space.authorityDID
                                                          lxm:@"com.atproto.space.notifyWrite"
                                           actorKeyManager:actor.keyManager
                                                      error:nil];
  if (!endpoint || !token) return;

  GZ_LOG_SYNC_INFO(@"permissioned-space event=replay_attempt");

  NSURL *url = [NSURL URLWithString:@"xrpc/com.atproto.space.notifyWrite" relativeToURL:endpoint];
  if (!url) return;
  NSError *encodeError = nil;
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{
      @"space" : space.spaceURI,
      @"repo" : author,
      @"rev" : rev,
      @"hash" : [hash base64EncodedStringWithOptions:0],
  } options:0 error:&encodeError];
  if (!body) return;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:nil completion:
      ^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || response.statusCode < 200 || response.statusCode >= 300) {
          GZ_LOG_SYNC_WARN(@"permissioned-space event=replay_failed status=%ld error=%@",
                           (long)response.statusCode, error.localizedDescription ?: @"none");
        } else {
          GZ_LOG_SYNC_INFO(@"permissioned-space event=replay_succeeded");
        }
      }];
}

#pragma mark - Inbound: sync from authority

- (void)reconcileOnceForSpace:(NSString *)space
                       author:(NSString *)author
                   completion:(void (^)(NSDictionary<NSString *, id> *result))completion {
  dispatch_async(self.queue, ^{
    NSDictionary<NSString *, id> *head = nil;
    for (NSDictionary<NSString *, id> *candidate in [self.spaceStore repositoriesForReconciliation:nil]) {
      if ([candidate[@"space"] isEqualToString:space] && [candidate[@"author"] isEqualToString:author]) {
        head = candidate;
        break;
      }
    }
    if (!head) {
      if (completion) completion(@{ @"selector" : @"unavailable", @"requests" : @{} });
      return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *requestCounts = [NSMutableDictionary dictionary];
    NSString *selector = [self syncRemoteRepo:head requestCounts:requestCounts];
    if (selector) {
      GZ_LOG_SYNC_INFO(@"permissioned-space event=recovery_path selector=%@", selector);
    }
    if (completion) completion(@{ @"selector" : selector ?: @"unavailable", @"requests" : [requestCounts copy] });
  });
}

- (nullable NSString *)syncRemoteRepo:(NSDictionary<NSString *, id> *)head
                         requestCounts:(NSMutableDictionary<NSString *, NSNumber *> *)requestCounts {
  PDSSpaceURI *space = [PDSSpaceURI URIWithString:head[@"space"] error:nil];
  NSString *author = head[@"author"];
  NSString *localRev = head[@"rev"];
  if (!space || space.recordURI || author.length == 0 || localRev.length == 0 ||
      [space.authorityDID isEqualToString:author]) return nil;

  DIDDocument *authorityDocument = [[DIDResolver sharedResolver] resolveDIDSync:space.authorityDID error:nil];
  NSURL *endpoint = [NSURL URLWithString:[ATProtoDIDDocumentFields spaceHostEndpointFromDocument:authorityDocument] ?: @""];
  PDSActorStore *actor = [self.userDatabasePool storeForDid:author error:nil];
  NSString *token = [self.jwtMinter mintServiceAuthJWTForDID:author
                                                          aud:space.authorityDID
                                                          lxm:@"com.atproto.space.getLatestCommit"
                                           actorKeyManager:actor.keyManager
                                                      error:nil];
  if (!endpoint || endpoint.absoluteString.length == 0 || !token) return nil;

  GZ_LOG_SYNC_INFO(@"permissioned-space event=reconcile_attempt");

  NSDictionary *remoteCommitResponse = [self xrpcGet:@"com.atproto.space.getLatestCommit"
                                     endpoint:endpoint
                                        token:token
                                    parameters:@{ @"space" : space.spaceURI, @"repo" : author }
                                 requestCounts:requestCounts
                                        error:nil];
  NSDictionary *remoteCommit = [remoteCommitResponse[@"commit"] isKindOfClass:[NSDictionary class]]
      ? remoteCommitResponse[@"commit"] : remoteCommitResponse;
  if (![remoteCommit isKindOfClass:[NSDictionary class]]) return nil;
  NSString *remoteRev = remoteCommit[@"rev"];
  if (remoteRev.length == 0) return nil;

  if ([remoteRev isEqualToString:localRev]) return @"incremental";

  id opsResponse = [self xrpcGet:@"com.atproto.space.listRepoOps"
                         endpoint:endpoint
                            token:token
                        parameters:@{ @"space" : space.spaceURI, @"repo" : author, @"since" : localRev, @"limit" : @(1000) }
                     requestCounts:requestCounts
                             error:nil];
  NSArray *ops = [opsResponse isKindOfClass:[NSArray class]] ? opsResponse :
      ([opsResponse[@"ops"] isKindOfClass:[NSArray class]] ? opsResponse[@"ops"] : nil);
  if (![ops isKindOfClass:[NSArray class]]) return nil;

  /* listRepoOps already applies the `since` revision cursor. Its `prev`
   * field is the prior record CID (not a repository revision), so comparing
   * it to localRev would falsely turn every update into a recovery gap. */
  BOOL gapDetected = ops.count == 0;
  if (gapDetected) {
    GZ_LOG_SYNC_INFO(@"permissioned-space event=reconciliation_gap_detected");
  }

  if (!gapDetected) {
    NSMutableArray<PDSSpaceWrite *> *writes = [NSMutableArray array];
    for (NSDictionary *op in ops) {
      if (![op isKindOfClass:[NSDictionary class]]) continue;
      NSString *action = op[@"action"], *collection = op[@"collection"], *rkey = op[@"rkey"];
      NSString *cid = [op cidStringForKey:@"cid"];
      if (!action || !collection || !rkey) continue;
      PDSSpaceWriteAction writeAction;
      if ([action isEqualToString:@"create"]) writeAction = PDSSpaceWriteActionCreate;
      else if ([action isEqualToString:@"update"]) writeAction = PDSSpaceWriteActionUpdate;
      else if ([action isEqualToString:@"delete"]) writeAction = PDSSpaceWriteActionDelete;
      else continue;
      PDSSpaceWrite *write = [PDSSpaceWrite writeWithAction:writeAction
                                                 collection:collection
                                                       rkey:rkey
                                                        cid:cid
                                                      value:nil];
      [writes addObject:write];
    }
    if (writes.count > 0) {
      [self.spaceStore applyWrites:writes toSpace:space.spaceURI author:author rev:nil error:nil];
    }
    return @"incremental";
  }

  NSDictionary *repoState = [self.spaceStore repositoryStateForSpace:space.spaceURI author:author error:nil];
  BOOL localEmpty = ![repoState isKindOfClass:[NSDictionary class]] || repoState[@"rev"] == [NSNull null];
  if (localEmpty) {
    return [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token requestCounts:requestCounts]
        ? @"fullCAR" : nil;
  }

  NSDictionary *localIndex = [self.spaceStore recordIndexForSpace:space.spaceURI author:author error:nil];
  if (!localIndex) {
    return [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token requestCounts:requestCounts]
        ? @"fullCAR" : nil;
  }

  NSDictionary *remoteIndex = [self fetchRemoteRecordIndexForSpace:space.spaceURI
                                                            author:author
                                                         endpoint:endpoint
                                                            token:token
                                                     requestCounts:requestCounts
                                                             error:nil];
  if (!remoteIndex) {
    return [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token requestCounts:requestCounts]
        ? @"fullCAR" : nil;
  }

  NSMutableArray *toAdd = [NSMutableArray array], *toUpdate = [NSMutableArray array], *toDelete = [NSMutableArray array];
  [self computeDiffLocal:localIndex remote:remoteIndex toAdd:toAdd toUpdate:toUpdate toDelete:toDelete];

  NSUInteger totalChanges = toAdd.count + toUpdate.count + toDelete.count;
  NSUInteger threshold = MIN((NSUInteger)50, MAX((NSUInteger)1, remoteIndex.count / 4));
  if (totalChanges <= threshold) {
    [self lightweightRecoveryForSpace:space
                               author:author
                            endpoint:endpoint
                               token:token
                                toAdd:toAdd
                             toUpdate:toUpdate
                              toDelete:toDelete
                         requestCounts:requestCounts];
    return @"lightweight";
  } else {
    return [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token requestCounts:requestCounts]
        ? @"fullCAR" : nil;
  }
}

#pragma mark - Full CAR recovery

- (BOOL)fullCARRecoveryForSpace:(PDSSpaceURI *)space
                         author:(NSString *)author
                      endpoint:(NSURL *)endpoint
                          token:(NSString *)token
                  requestCounts:(NSMutableDictionary<NSString *, NSNumber *> *)requestCounts {
  if (requestCounts) requestCounts[@"com.atproto.space.getRepo"] = @([requestCounts[@"com.atproto.space.getRepo"] unsignedIntegerValue] + 1);
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
      [NSURL URLWithString:[NSString stringWithFormat:@"xrpc/com.atproto.space.getRepo?space=%@&repo=%@",
                             space.spaceURI, author] relativeToURL:endpoint]];
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  NSError *fetchError = nil;
  NSData *carData = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                        options:nil
                                                                       response:nil
                                                                          error:&fetchError];
  if (!carData || carData.length == 0) return NO;

  NSString *authorityDID = space.authorityDID;
  NSData *publicKey = [self publicKeyForDID:authorityDID];
  if (!publicKey) return NO;

  NSError *importError = nil;
  BOOL imported = [self.spaceStore importRepoFromCAR:carData
                                                space:space.spaceURI
                                               author:author
                                      commitPublicKey:publicKey
                                                error:&importError];
  if (!imported) {
    GZ_LOG_WARN(@"Permissioned-space CAR recovery failed for %@/%@: %@", space.spaceURI, author,
                importError.localizedDescription ?: @"unknown error");
  }
  return imported;
}

#pragma mark - Lightweight recovery

- (void)lightweightRecoveryForSpace:(PDSSpaceURI *)space
                              author:(NSString *)author
                           endpoint:(NSURL *)endpoint
                              token:(NSString *)token
                             toAdd:(NSArray<NSString *> *)toAdd
                          toUpdate:(NSArray<NSString *> *)toUpdate
                           toDelete:(NSArray<NSString *> *)toDelete
                      requestCounts:(NSMutableDictionary<NSString *, NSNumber *> *)requestCounts {
  NSMutableArray<PDSSpaceWrite *> *writes = [NSMutableArray array];
  for (NSString *path in [toAdd arrayByAddingObjectsFromArray:toUpdate]) {
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count != 2) continue;
    NSDictionary *record = [self xrpcGet:@"com.atproto.space.getRecord"
                                endpoint:endpoint
                                   token:token
                               parameters:@{ @"space" : space.spaceURI, @"repo" : author,
                                             @"collection" : parts[0], @"rkey" : parts[1] }
                            requestCounts:requestCounts
                                   error:nil];
    if (![record isKindOfClass:[NSDictionary class]]) continue;
    NSString *cid = [record cidStringForKey:@"cid"];
    id valueObj = record[@"value"];
    if (!cid || !valueObj) continue;
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:valueObj options:0 error:nil];
    if (!valueData) continue;
    PDSSpaceWriteAction action = [toAdd containsObject:path] ? PDSSpaceWriteActionCreate : PDSSpaceWriteActionUpdate;
    [writes addObject:[PDSSpaceWrite writeWithAction:action
                                          collection:parts[0]
                                                rkey:parts[1]
                                                 cid:cid
                                               value:valueData]];
  }
  for (NSString *path in toDelete) {
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count != 2) continue;
    [writes addObject:[PDSSpaceWrite writeWithAction:PDSSpaceWriteActionDelete
                                          collection:parts[0]
                                                rkey:parts[1]
                                                 cid:nil
                                               value:nil]];
  }
  if (writes.count > 0) {
    [self.spaceStore applyWrites:writes toSpace:space.spaceURI author:author rev:nil error:nil];
  }
}

#pragma mark - Remote record index (paginated)

- (NSDictionary<NSString *, NSString *> *)fetchRemoteRecordIndexForSpace:(NSString *)space
                                                                  author:(NSString *)author
                                                                  endpoint:(NSURL *)endpoint
                                                                     token:(NSString *)token
                                                             requestCounts:(NSMutableDictionary<NSString *, NSNumber *> *)requestCounts
                                                                     error:(NSError **)error {
  NSMutableDictionary<NSString *, NSString *> *index = [NSMutableDictionary dictionary];
  NSString *cursor = nil;
  while (YES) {
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:
        @{ @"space" : space, @"repo" : author, @"excludeValues" : @"true", @"limit" : @"100" }];
    if (cursor) params[@"cursor"] = cursor;
    id recordsResponse = [self xrpcGet:@"com.atproto.space.listRecords"
                               endpoint:endpoint
                                  token:token
                              parameters:params
                           requestCounts:requestCounts
                                   error:error];
    NSArray *records = [recordsResponse isKindOfClass:[NSArray class]] ? recordsResponse :
        ([recordsResponse[@"records"] isKindOfClass:[NSArray class]] ? recordsResponse[@"records"] : nil);
    if (![records isKindOfClass:[NSArray class]]) break;
    for (NSDictionary *record in records) {
      if (![record isKindOfClass:[NSDictionary class]]) continue;
      NSString *collection = record[@"collection"], *rkey = record[@"rkey"];
      if (collection.length == 0 || rkey.length == 0) {
        NSString *uri = record[@"uri"];
        NSArray<NSString *> *components = [uri isKindOfClass:[NSString class]]
            ? [uri componentsSeparatedByString:@"/"] : @[];
        if (components.count >= 2) {
          collection = components[components.count - 2];
          rkey = components.lastObject;
        }
      }
      NSString *cid = [record cidStringForKey:@"cid"];
      if (collection && rkey && cid) {
        index[[NSString stringWithFormat:@"%@/%@", collection, rkey]] = cid;
      }
    }
    NSDictionary *last = records.lastObject;
    if ([last isKindOfClass:[NSDictionary class]] && last[@"cursor"]) {
      cursor = last[@"cursor"];
    } else {
      break;
    }
  }
  return [index copy];
}

#pragma mark - Diff computation

- (void)computeDiffLocal:(NSDictionary<NSString *, NSString *> *)localIndex
                  remote:(NSDictionary<NSString *, NSString *> *)remoteIndex
                  toAdd:(NSMutableArray<NSString *> *)toAdd
               toUpdate:(NSMutableArray<NSString *> *)toUpdate
                toDelete:(NSMutableArray<NSString *> *)toDelete {
  for (NSString *path in remoteIndex) {
    NSString *localCID = localIndex[path];
    NSString *remoteCID = remoteIndex[path];
    if (!localCID) {
      [toAdd addObject:path];
    } else if (![localCID isEqualToString:remoteCID]) {
      [toUpdate addObject:path];
    }
  }
  for (NSString *path in localIndex) {
    if (!remoteIndex[path]) {
      [toDelete addObject:path];
    }
  }
}

#pragma mark - XRPC helper

- (nullable id)xrpcGet:(NSString *)method
              endpoint:(NSURL *)endpoint
                 token:(NSString *)token
            parameters:(NSDictionary *)params
         requestCounts:(NSMutableDictionary<NSString *, NSNumber *> *)requestCounts
                 error:(NSError **)error {
  if (requestCounts) requestCounts[method] = @([requestCounts[method] unsignedIntegerValue] + 1);
  NSURLComponents *components = [NSURLComponents componentsWithURL:
      [NSURL URLWithString:[NSString stringWithFormat:@"xrpc/%@", method] relativeToURL:endpoint]
                                resolvingAgainstBaseURL:YES];
  if (!components) return nil;
  NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
  for (NSString *key in params) {
    id value = params[key];
    if ([value isKindOfClass:[NSString class]]) {
      [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    } else if ([value isKindOfClass:[NSNumber class]]) {
      [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:[value stringValue]]];
    }
  }
  components.queryItems = queryItems;
  NSURL *url = components.URL;
  if (!url) return nil;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  NSError *fetchError = nil;
  NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                    options:nil
                                                                   response:nil
                                                                      error:&fetchError];
  if (!data) {
    if (error) *error = fetchError;
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

- (nullable NSData *)publicKeyForDID:(NSString *)did {
  DIDDocument *document = [[DIDResolver sharedResolver] resolveDIDSync:did error:nil];
  NSString *key = document ? [ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:document] : nil;
  if ([key hasPrefix:@"did:key:"]) key = [key substringFromIndex:8];
  if (![key hasPrefix:@"z"]) return nil;
  NSData *decoded = [CID base58btcDecode:[key substringFromIndex:1]];
  if (decoded.length != 35) return nil;
  const uint8_t *bytes = decoded.bytes;
  if (bytes[0] != 0xe7 || bytes[1] != 0x01) return nil;
  return [decoded subdataWithRange:NSMakeRange(2, 33)];
}

@end
