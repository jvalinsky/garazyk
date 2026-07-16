// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Services/PDS/PDSSpaceReconciler.h"

#import "Auth/JWT.h"
#import "Compat/PDSTypes.h"
#import "Core/ATProtoDIDDocumentFields.h"
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
    [self syncRemoteRepo:head];
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
        /* The next durable pass retries transport and non-2xx failures. */
      }];
}

#pragma mark - Inbound: sync from authority

- (void)syncRemoteRepo:(NSDictionary<NSString *, id> *)head {
  PDSSpaceURI *space = [PDSSpaceURI URIWithString:head[@"space"] error:nil];
  NSString *author = head[@"author"];
  NSString *localRev = head[@"rev"];
  if (!space || space.recordURI || author.length == 0 || localRev.length == 0 ||
      [space.authorityDID isEqualToString:author]) return;

  DIDDocument *authorityDocument = [[DIDResolver sharedResolver] resolveDIDSync:space.authorityDID error:nil];
  NSURL *endpoint = [NSURL URLWithString:[ATProtoDIDDocumentFields spaceHostEndpointFromDocument:authorityDocument] ?: @""];
  PDSActorStore *actor = [self.userDatabasePool storeForDid:author error:nil];
  NSString *token = [self.jwtMinter mintServiceAuthJWTForDID:author
                                                          aud:space.authorityDID
                                                          lxm:@"com.atproto.space.getLatestCommit"
                                           actorKeyManager:actor.keyManager
                                                      error:nil];
  if (!endpoint || endpoint.absoluteString.length == 0 || !token) return;

  NSDictionary *remoteCommit = [self xrpcGet:@"com.atproto.space.getLatestCommit"
                                     endpoint:endpoint
                                        token:token
                                    parameters:@{ @"space" : space.spaceURI, @"repo" : author }
                                        error:nil];
  if (![remoteCommit isKindOfClass:[NSDictionary class]]) return;
  NSString *remoteRev = remoteCommit[@"rev"];
  if (![remoteCommit isKindOfClass:[NSDictionary class]] || remoteRev.length == 0) return;

  if ([remoteRev isEqualToString:localRev]) return;

  NSArray *ops = [self xrpcGet:@"com.atproto.space.listRepoOps"
                      endpoint:endpoint
                         token:token
                     parameters:@{ @"space" : space.spaceURI, @"repo" : author, @"since" : localRev, @"limit" : @(1000) }
                         error:nil];
  if (![ops isKindOfClass:[NSArray class]]) return;

  BOOL gapDetected = NO;
  if (ops.count > 0) {
    NSDictionary *firstOp = ops.firstObject;
    NSString *prev = [firstOp isKindOfClass:[NSDictionary class]] ? firstOp[@"prev"] : nil;
    if ([prev isKindOfClass:[NSString class]] && prev.length > 0 && ![prev isEqualToString:localRev]) {
      gapDetected = YES;
    } else if (![prev isKindOfClass:[NSString class]] || prev.length == 0) {
      gapDetected = YES;
    }
  } else {
    gapDetected = YES;
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
    return;
  }

  NSDictionary *repoState = [self.spaceStore repositoryStateForSpace:space.spaceURI author:author error:nil];
  BOOL localEmpty = ![repoState isKindOfClass:[NSDictionary class]] || repoState[@"rev"] == [NSNull null];
  if (localEmpty) {
    [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token];
    return;
  }

  NSDictionary *localIndex = [self.spaceStore recordIndexForSpace:space.spaceURI author:author error:nil];
  if (!localIndex) {
    [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token];
    return;
  }

  NSDictionary *remoteIndex = [self fetchRemoteRecordIndexForSpace:space.spaceURI
                                                            author:author
                                                         endpoint:endpoint
                                                            token:token
                                                             error:nil];
  if (!remoteIndex) {
    [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token];
    return;
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
                              toDelete:toDelete];
  } else {
    [self fullCARRecoveryForSpace:space author:author endpoint:endpoint token:token];
  }
}

#pragma mark - Full CAR recovery

- (void)fullCARRecoveryForSpace:(PDSSpaceURI *)space
                         author:(NSString *)author
                      endpoint:(NSURL *)endpoint
                          token:(NSString *)token {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
      [NSURL URLWithString:[NSString stringWithFormat:@"xrpc/com.atproto.space.getRepo?space=%@&repo=%@",
                             space.spaceURI, author] relativeToURL:endpoint]];
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  NSError *fetchError = nil;
  NSData *carData = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                        options:nil
                                                                       response:nil
                                                                          error:&fetchError];
  if (!carData || carData.length == 0) return;

  NSDictionary *spaceInfo = [self.spaceStore spaceInfoForURI:space.spaceURI error:nil];
  NSString *authorityDID = space.authorityDID;
  NSData *publicKey = [self publicKeyForDID:authorityDID];
  if (!publicKey) return;

  [self.spaceStore importRepoFromCAR:carData
                               space:space.spaceURI
                              author:author
                     commitPublicKey:publicKey
                               error:nil];
}

#pragma mark - Lightweight recovery

- (void)lightweightRecoveryForSpace:(PDSSpaceURI *)space
                              author:(NSString *)author
                           endpoint:(NSURL *)endpoint
                              token:(NSString *)token
                               toAdd:(NSArray<NSString *> *)toAdd
                            toUpdate:(NSArray<NSString *> *)toUpdate
                             toDelete:(NSArray<NSString *> *)toDelete {
  NSMutableArray<PDSSpaceWrite *> *writes = [NSMutableArray array];
  for (NSString *path in [toAdd arrayByAddingObjectsFromArray:toUpdate]) {
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count != 2) continue;
    NSDictionary *record = [self xrpcGet:@"com.atproto.space.getRecord"
                                endpoint:endpoint
                                   token:token
                               parameters:@{ @"space" : space.spaceURI, @"repo" : author,
                                             @"collection" : parts[0], @"rkey" : parts[1] }
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
                                                                   error:(NSError **)error {
  NSMutableDictionary<NSString *, NSString *> *index = [NSMutableDictionary dictionary];
  NSString *cursor = nil;
  while (YES) {
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:
        @{ @"space" : space, @"repo" : author, @"excludeValues" : @"true", @"limit" : @"100" }];
    if (cursor) params[@"cursor"] = cursor;
    NSArray *records = [self xrpcGet:@"com.atproto.space.listRecords"
                            endpoint:endpoint
                               token:token
                           parameters:params
                               error:error];
    if (![records isKindOfClass:[NSArray class]]) break;
    for (NSDictionary *record in records) {
      if (![record isKindOfClass:[NSDictionary class]]) continue;
      NSString *collection = record[@"collection"], *rkey = record[@"rkey"];
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
                 error:(NSError **)error {
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
  if (!document) return nil;
  NSArray *methods = document.jsonDictionary[@"verificationMethod"];
  if (![methods isKindOfClass:[NSArray class]]) return nil;
  for (id method in methods) {
    if (![method isKindOfClass:[NSDictionary class]]) continue;
    NSString *type = method[@"type"];
    if ([type isEqualToString:@"EcdsaSecp256k1VerificationKey2019"] ||
        [type isEqualToString:@"EcdsaSecp256k1RecoveryMethod2020"]) {
      NSString *publicKeyMultibase = method[@"publicKeyMultibase"];
      if ([publicKeyMultibase isKindOfClass:[NSString class]] && publicKeyMultibase.length > 0) {
        return [self multibaseToRawBytes:publicKeyMultibase];
      }
    }
  }
  return nil;
}

- (nullable NSData *)multibaseToRawBytes:(NSString *)multibase {
  if (multibase.length < 2) return nil;
  char prefix = [multibase characterAtIndex:0];
  NSString *encoded;
  int base;
  if (prefix == 'z') { encoded = [multibase substringFromIndex:1]; base = 58; }
  else if (prefix == 'm') { encoded = [multibase substringFromIndex:1]; base = 16; }
  else { encoded = multibase; base = 16; }
  if (base == 16) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < encoded.length; i += 2) {
      unsigned int byte;
      NSScanner *scanner = [NSScanner scannerWithString:[encoded substringWithRange:NSMakeRange(i, 2)]];
      if (![scanner scanHexInt:&byte]) return nil;
      uint8_t b = (uint8_t)byte;
      [data appendBytes:&b length:1];
    }
    return [data copy];
  }
  return nil;
}

@end
