// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcSpacePack.h"

#import "Auth/JWT.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/TID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Repository/CAR.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Security/Space/PDSSpaceScope.h"
#import "Security/Space/PDSSpaceCommit.h"
#import "Security/Space/PDSSpaceJWT.h"
#import "Security/Space/PDSSpaceLtHash.h"
#import "Security/Space/PDSSpaceURI.h"
#import "Services/PDS/PDSSpaceStore.h"
#import "Network/Generated/GZXrpcNSID.h"

static const NSTimeInterval PDSSpaceNotificationRegistrationLifetime = 24 * 60 * 60;

static void SpaceError(HttpResponse *response, HttpStatusCode status, NSString *code,
                       NSString *message) {
  response.statusCode = status;
  [response setJsonBody:@{ @"error" : code, @"message" : message }];
}

static NSString *SpaceAuthorizationToken(HttpRequest *request) {
  NSString *header = [request headerForKey:@"Authorization"];
  if ([header hasPrefix:@"Bearer "]) return [header substringFromIndex:7];
  if ([header hasPrefix:@"DPoP "]) return [header substringFromIndex:5];
  return nil;
}

/* Authenticates using the normal PDS OAuth access-token verifier, then parses
 * only the structured `space:` resources from its already verified scope. */
static NSDictionary *SpaceOAuthAuthentication(HttpRequest *request, HttpResponse *response,
                                              id<XrpcRoutePackServices> services) {
  NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:[request headerForKey:@"Authorization"]
                                                  services:services request:request response:response];
  if (!did) return nil;
  JWT *jwt = [JWT jwtWithToken:SpaceAuthorizationToken(request) error:nil];
  NSMutableArray<PDSSpaceScope *> *scopes = [NSMutableArray array];
  for (NSString *candidate in [jwt.payload.scope componentsSeparatedByCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
    if (![candidate hasPrefix:@"space:"]) continue;
    PDSSpaceScope *scope = [PDSSpaceScope scopeWithString:candidate error:nil];
    scope = [scope scopeByResolvingSelfAuthorityForDID:did];
    if (scope) [scopes addObject:scope];
  }
  if (scopes.count == 0) {
    SpaceError(response, HttpStatusForbidden, @"InsufficientScope",
               @"An OAuth space: scope is required");
    return nil;
  }
  return @{ @"did" : did, @"scopes" : scopes };
}

static BOOL SpaceAllows(NSDictionary *auth, PDSSpaceURI *space, NSString *action,
                        NSString *collection) {
  for (PDSSpaceScope *scope in auth[@"scopes"]) {
    if ([scope matchesSpace:space action:action collection:collection]) return YES;
  }
  return NO;
}

static BOOL SpaceAllowsManage(NSDictionary *auth, PDSSpaceURI *space, NSString *operation) {
  for (PDSSpaceScope *scope in auth[@"scopes"]) {
    if ([scope matchesSpace:space manageOperation:operation]) return YES;
  }
  return NO;
}

static PDSSpaceURI *SpaceURIFromString(id value, HttpResponse *response) {
  PDSSpaceURI *space = [PDSSpaceURI URIWithString:value error:nil];
  if (!space || space.recordURI) {
    SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"space must be a valid space URI");
    return nil;
  }
  return space;
}

static NSString *SpaceString(id value) {
  return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0 ? value : nil;
}

static NSUInteger SpaceLimit(HttpRequest *request, NSUInteger fallback, NSUInteger maximum,
                             HttpResponse *response) {
  NSString *value = [request queryParamForKey:@"limit"];
  if (value.length == 0) return fallback;
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long parsed = 0;
  if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed < 1 || parsed > (long long)maximum) {
    SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"limit is out of range");
    return 0;
  }
  return (NSUInteger)parsed;
}

static NSDictionary *SpaceConfig(NSDictionary *info) {
  NSString *access = info[@"appAccessType"] ?: @"open";
  NSDictionary *appAccess = [access isEqualToString:@"allowList"]
      ? @{ @"$type" : @"com.atproto.simplespace.defs#allowList",
           @"allowed" : info[@"appAllowed"] ?: @[] }
      : @{ @"$type" : @"com.atproto.simplespace.defs#open" };
  NSMutableDictionary *config = [@{ @"$type" : @"com.atproto.simplespace.defs#spaceConfig",
                                    @"policy" : info[@"policy"] ?: @"member-list",
                                    @"appAccess" : appAccess } mutableCopy];
  if ([info[@"managingApp"] isKindOfClass:[NSString class]]) config[@"managingApp"] = info[@"managingApp"];
  return config;
}

static NSString *SpaceRecordURI(PDSSpaceURI *space, NSString *repo, NSString *collection,
                                NSString *rkey) {
  return [NSString stringWithFormat:@"%@/%@/%@/%@", space.spaceURI, repo, collection, rkey];
}

static NSDictionary *SpaceRecordView(PDSSpaceURI *space, NSString *repo, NSDictionary *record,
                                     BOOL includeValue) {
  NSMutableDictionary *result = [@{ @"uri" : SpaceRecordURI(space, repo, record[@"collection"], record[@"rkey"]),
                                    @"cid" : record[@"cid"] ?: @"" } mutableCopy];
  if (includeValue) {
    id value = [ATProtoDagCBOR decodeDataAsJSON:record[@"value"] error:nil];
    if (value) result[@"value"] = value;
  }
  return result;
}

static PDSSpaceWrite *SpaceWriteFromDictionary(NSDictionary *item, BOOL createDefaultRkey,
                                                HttpResponse *response) {
  NSString *action = SpaceString(item[@"$type"]);
  NSRange typeSeparator = [action rangeOfString:@"#" options:NSBackwardsSearch];
  if (typeSeparator.location != NSNotFound) action = [action substringFromIndex:NSMaxRange(typeSeparator)];
  if (!action) action = SpaceString(item[@"action"]);
  PDSSpaceWriteAction writeAction = 0;
  if ([action isEqualToString:@"create"]) writeAction = PDSSpaceWriteActionCreate;
  if ([action isEqualToString:@"update"]) writeAction = PDSSpaceWriteActionUpdate;
  if ([action isEqualToString:@"delete"]) writeAction = PDSSpaceWriteActionDelete;
  NSString *collection = SpaceString(item[@"collection"]);
  NSString *rkey = SpaceString(item[@"rkey"]);
  if (writeAction == PDSSpaceWriteActionCreate && !rkey && createDefaultRkey) rkey = TID.tid.stringValue;
  if (!writeAction || ![ATProtoValidator validateNSID:collection error:nil] || rkey.length == 0 || rkey.length > 512) {
    SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"Invalid space write");
    return nil;
  }
  if (writeAction == PDSSpaceWriteActionDelete) {
    return [PDSSpaceWrite writeWithAction:writeAction collection:collection rkey:rkey cid:nil value:nil];
  }
  id value = item[@"value"] ?: item[@"record"];
  if (![value isKindOfClass:[NSDictionary class]] || ![SpaceString(value[@"$type"]) length]) {
    SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"A record object with $type is required");
    return nil;
  }
  NSError *encodeError = nil;
  NSData *cbor = [ATProtoDagCBOR encodeJSONObject:value error:&encodeError];
  CID *cid = [CID cidWithDigest:[CID sha256Digest:cbor] codec:0x71];
  if (!cbor || !cid) {
    SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"Record cannot be encoded as DAG-CBOR");
    return nil;
  }
  return [PDSSpaceWrite writeWithAction:writeAction collection:collection rkey:rkey
                                    cid:cid.stringValue value:cbor];
}

static BOOL SpaceCanWrite(NSDictionary *auth, PDSSpaceURI *space, NSString *repo,
                          NSArray<PDSSpaceWrite *> *writes, HttpResponse *response) {
  if (![repo isEqualToString:auth[@"did"]]) {
    SpaceError(response, HttpStatusForbidden, @"Forbidden", @"A user may write only their own space repo");
    return NO;
  }
  for (PDSSpaceWrite *write in writes) {
    NSString *action = write.action == PDSSpaceWriteActionCreate ? PDSSpaceActionCreate :
        write.action == PDSSpaceWriteActionUpdate ? PDSSpaceActionUpdate : PDSSpaceActionDelete;
    if (!SpaceAllows(auth, space, action, write.collection)) {
      SpaceError(response, HttpStatusForbidden, @"InsufficientScope", @"OAuth scope does not permit this write");
      return NO;
    }
  }
  return YES;
}

static NSData *SpacePublicKeyFromDIDKey(NSString *value) {
  NSString *multibase = [value hasPrefix:@"did:key:"] ? [value substringFromIndex:8] : value;
  if (![multibase hasPrefix:@"z"]) return nil;
  NSData *decoded = [CID base58btcDecode:[multibase substringFromIndex:1]];
  if (decoded.length != 35) return nil;
  const uint8_t *bytes = decoded.bytes;
  if (bytes[0] != 0xe7 || bytes[1] != 0x01) return nil;
  return [decoded subdataWithRange:NSMakeRange(2, 33)];
}

static DIDDocument *SpaceResolveDID(NSString *did, BOOL refresh, HttpResponse *response) {
  NSError *error = nil;
  DIDDocument *document = [[DIDResolver sharedResolver] resolveDIDSync:did forceRefresh:refresh error:&error];
  if (!document) SpaceError(response, HttpStatusUnauthorized, @"InvalidToken", @"Unable to resolve signing DID");
  return document;
}

/* Use the dedicated signer only after the DID document publishes its exact
 * public key.  A #atproto_space kid must never be attached to an account-key
 * signature merely because a DID document happens to contain that fragment. */
static id<PDSActorKeyManager> SpaceCredentialSignerForAuthorityDocument(PDSActorStore *authority,
                                                                          DIDDocument *document,
                                                                          NSString **keyID) {
  NSString *spaceKey = [ATProtoDIDDocumentFields dedicatedSpaceSigningKeyMultibaseFromDocument:document];
  NSString *localSpaceKey = [authority spaceSigningDIDKeyStringWithError:nil];
  if ([localSpaceKey hasPrefix:@"did:key:"]) {
    localSpaceKey = [localSpaceKey substringFromIndex:@"did:key:".length];
  }
  if (spaceKey.length > 0 && [spaceKey isEqualToString:localSpaceKey]) {
    if (keyID) *keyID = @"#atproto_space";
    return authority.spaceKeyManager;
  }
  if (keyID) *keyID = @"#atproto";
  return authority.keyManager;
}

static NSDictionary *SpaceCredentialAuthentication(HttpRequest *request, HttpResponse *response,
                                                    PDSSpaceURI *space) {
  NSString *token = SpaceAuthorizationToken(request);
  JWT *jwt = [JWT jwtWithToken:token error:nil];
  if (![jwt.header.typ isEqualToString:PDSSpaceCredentialJWTType]) return nil;
  NSString *keyID = jwt.header.kid;
  if (!([keyID isEqualToString:@"#atproto_space"] || [keyID isEqualToString:@"#atproto"])) {
    SpaceError(response, HttpStatusUnauthorized, @"InvalidCredential", @"Credential key ID is invalid"); return @{};
  }
  DIDDocument *doc = SpaceResolveDID(space.authorityDID, NO, response); if (!doc) return @{};
  NSString *key = [keyID isEqualToString:@"#atproto_space"]
      ? [ATProtoDIDDocumentFields dedicatedSpaceSigningKeyMultibaseFromDocument:doc]
      : [ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:doc];
  NSData *publicKey = SpacePublicKeyFromDIDKey(key);
  NSDictionary *claims = publicKey ? [PDSSpaceJWT verifyCredential:token publicKey:publicKey
      expectedIssuer:space.authorityDID expectedSubject:space.spaceURI keyID:keyID now:nil error:nil] : nil;
  if (!claims) {
    /* A key rotation can invalidate a cached DID document; retry once fresh. */
    doc = SpaceResolveDID(space.authorityDID, YES, response); if (!doc) return @{};
    key = [keyID isEqualToString:@"#atproto_space"] ? [ATProtoDIDDocumentFields dedicatedSpaceSigningKeyMultibaseFromDocument:doc] : [ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:doc];
    publicKey = SpacePublicKeyFromDIDKey(key);
    claims = publicKey ? [PDSSpaceJWT verifyCredential:token publicKey:publicKey expectedIssuer:space.authorityDID expectedSubject:space.spaceURI keyID:keyID now:nil error:nil] : nil;
  }
  if (!claims) { SpaceError(response, HttpStatusUnauthorized, @"InvalidCredential", @"Credential did not verify"); return @{}; }
  return claims;
}

static NSString *SpaceServiceAuthentication(HttpRequest *request, HttpResponse *response,
                                            NSString *expectedAudience, NSString *expectedMethod);

static NSDictionary *SpaceReadAuthentication(HttpRequest *request, HttpResponse *response,
                                             id<XrpcRoutePackServices> services, PDSSpaceURI *space,
                                             NSString *repo, NSString *collection) {
  JWT *unverified = [JWT jwtWithToken:SpaceAuthorizationToken(request) error:nil];
  if (unverified.payload.lxm.length > 0) {
    /* The reconciler mints this single, writer-bound service capability once
     * and uses it for its read-only recovery sequence.  Keep it bound to the
     * authority host and to the same writer repo; it must not authorize an
     * arbitrary service or a different repository. */
    NSString *issuer = SpaceServiceAuthentication(request, response, space.authorityDID,
                                                  @"com.atproto.space.getLatestCommit");
    if (!issuer) return nil;
    if (![issuer isEqualToString:repo]) {
      SpaceError(response, HttpStatusForbidden, @"InvalidToken", @"Service token is not bound to this repo");
      return nil;
    }
    return @{ @"service" : issuer };
  }
  NSDictionary *credential = SpaceCredentialAuthentication(request, response, space);
  if (credential) return credential.count ? @{ @"credential" : credential } : nil;
  NSDictionary *auth = SpaceOAuthAuthentication(request, response, services); if (!auth) return nil;
  /* Protocol read methods are whole-space reads. `read_self` remains a valid
   * scope primitive, but is intentionally not silently upgraded here. */
  if (!SpaceAllows(auth, space, PDSSpaceActionRead, nil)) {
    SpaceError(response, HttpStatusForbidden, @"InsufficientScope", @"OAuth scope does not permit this read"); return nil;
  }
  return auth;
}

static void SpaceApplyPrivateBlobResponseHeaders(HttpResponse *response) {
  [response setHeader:@"no-store, private" forKey:@"Cache-Control"];
  [response setHeader:@"nosniff" forKey:@"X-Content-Type-Options"];
  [response setHeader:@"attachment; filename=space-blob" forKey:@"Content-Disposition"];
  [response setHeader:@"default-src 'none'; sandbox" forKey:@"Content-Security-Policy"];
}

static NSDictionary *SpaceSignedCommit(PDSSpaceStore *store, PDSDatabasePool *pool,
                                       PDSSpaceURI *space, NSString *repo, NSError **error) {
  NSDictionary *state = [store repositoryStateForSpace:space.spaceURI author:repo error:error];
  if (!state || ![state[@"rev"] isKindOfClass:[NSString class]]) return nil;
  PDSSpaceLtHash *setHash = [[PDSSpaceLtHash alloc] initWithState:state[@"state"] error:error];
  // The authority hosts the isolated repository and signs its exported
  // reconciliation commit. Remote writers do not have actor key material on
  // the authority PDS, and import verifies against this authority key.
  PDSActorStore *actor = [pool storeForDid:space.authorityDID error:error];
  PDSSpaceCommit *commit = [PDSSpaceCommit commitForSetHash:setHash space:space.spaceURI author:repo
      rev:state[@"rev"] actorKeyManager:actor.keyManager error:error];
  if (!commit) return nil;
  NSString *(^b64)(NSData *) = ^NSString *(NSData *bytes) { return [bytes base64EncodedStringWithOptions:0]; };
  return @{ @"ver" : @(commit.version), @"hash" : b64(commit.commitHash), @"mac" : b64(commit.mac),
            @"ikm" : b64(commit.ikm), @"sig" : b64(commit.signature), @"rev" : commit.rev };
}

static PDSSpaceCommit *SpaceCommitObject(PDSSpaceStore *store, PDSDatabasePool *pool,
                                         PDSSpaceURI *space, NSString *repo, NSError **error) {
  NSDictionary *state = [store repositoryStateForSpace:space.spaceURI author:repo error:error];
  if (!state || ![state[@"rev"] isKindOfClass:[NSString class]]) return nil;
  PDSSpaceLtHash *setHash = [[PDSSpaceLtHash alloc] initWithState:state[@"state"] error:error];
  PDSActorStore *actor = [pool storeForDid:space.authorityDID error:error];
  PDSSpaceCommit *commit = [PDSSpaceCommit commitForSetHash:setHash space:space.spaceURI author:repo
      rev:state[@"rev"] actorKeyManager:actor.keyManager error:error];
  return commit;
}

static void SpaceAppendVarint(NSMutableData *data, NSUInteger value) {
  do { uint8_t byte = value & 0x7f; value >>= 7; if (value) byte |= 0x80; [data appendBytes:&byte length:1]; } while (value);
}

static NSData *SpaceRepoCAR(PDSSpaceStore *store, PDSDatabasePool *pool, PDSSpaceURI *space,
                            NSString *repo, NSError **error) {
  PDSSpaceCommit *commit = SpaceCommitObject(store, pool, space, repo, error); if (!commit) return nil;
  NSDictionary *commitObject = @{ @"ver" : @(commit.version), @"hash" : commit.commitHash, @"mac" : commit.mac,
                                  @"ikm" : commit.ikm, @"sig" : commit.signature, @"rev" : commit.rev };
  NSData *commitData = [ATProtoDagCBOR encodeObject:commitObject error:error];
  CID *commitCID = [CID cidWithDigest:[CID sha256Digest:commitData] codec:0x71]; if (!commitData || !commitCID) return nil;
  NSMutableArray *records = [NSMutableArray array]; NSString *cursor = nil;
  while (YES) { NSArray *page = [store recordsForSpace:space.spaceURI author:repo collection:nil limit:100 cursor:cursor reverse:NO error:error]; if (!page) return nil; [records addObjectsFromArray:page]; if (page.count < 100) break; NSDictionary *last = page.lastObject; cursor = [NSString stringWithFormat:@"%@/%@", last[@"collection"], last[@"rkey"]]; }
  NSMutableDictionary *index = [NSMutableDictionary dictionary]; NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
  for (NSDictionary *record in records) { CID *cid = [CID cidFromString:record[@"cid"]]; if (!cid) { if (error) *error = [NSError errorWithDomain:@"com.garazyk.space" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Stored record CID is invalid"}]; return nil; } NSString *path = [NSString stringWithFormat:@"%@/%@", record[@"collection"], record[@"rkey"]]; index[path] = cid; [blocks addObject:[CARBlock blockWithCID:cid data:record[@"value"]]]; }
  NSData *indexData = [ATProtoDagCBOR encodeObject:index error:error]; CID *indexCID = [CID cidWithDigest:[CID sha256Digest:indexData] codec:0x71]; if (!indexData || !indexCID) return nil;
  NSMutableData *output = [NSMutableData data]; NSData *header = [ATProtoDagCBOR encodeObject:@{ @"version" : @1, @"roots" : @[commitCID, indexCID] } error:error]; if (!header) return nil;
  SpaceAppendVarint(output, header.length); [output appendData:header];
  for (CARBlock *block in @[[CARBlock blockWithCID:commitCID data:commitData], [CARBlock blockWithCID:indexCID data:indexData]]) { NSData *encoded = [CARWriter encodedBlock:block error:error]; if (!encoded) return nil; [output appendData:encoded]; }
  for (CARBlock *block in blocks) { NSData *encoded = [CARWriter encodedBlock:block error:error]; if (!encoded) return nil; [output appendData:encoded]; }
  return output;
}

static NSString *SpaceServiceAuthentication(HttpRequest *request, HttpResponse *response,
                                            NSString *expectedAudience, NSString *expectedMethod) {
  JWT *jwt = [JWT jwtWithToken:SpaceAuthorizationToken(request) error:nil];
  NSString *issuer = jwt.payload.iss;
  if (![ATProtoValidator validateDID:issuer error:nil] ||
      (expectedAudience.length > 0 && ![jwt.payload.aud isEqualToString:expectedAudience]) ||
      ![jwt.payload.lxm isEqualToString:expectedMethod]) {
    SpaceError(response, HttpStatusUnauthorized, @"InvalidToken", @"Invalid service authentication claims"); return nil;
  }
  DIDDocument *doc = SpaceResolveDID(issuer, NO, response); if (!doc) return nil;
  NSData *key = SpacePublicKeyFromDIDKey([ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:doc]);
  JWTVerifier *verifier = [[JWTVerifier alloc] init]; verifier.publicKey = key; verifier.expectedIssuer = issuer;
  verifier.expectedAudience = expectedAudience; verifier.allowedAlgorithms = @[ @"ES256K" ];
  // Inter-service auth tokens (iss/aud/lxm) carry no subject claim — matching
  // the service-auth verification in XrpcServerPack.
  verifier.allowMissingSubject = YES;
  if (!key || ![verifier verifyJWT:jwt error:nil]) { SpaceError(response, HttpStatusUnauthorized, @"InvalidToken", @"Service token did not verify"); return nil; }
  return issuer;
}

static void SpacePostJSON(NSURL *baseURL, NSString *method, NSDictionary *body, NSString *token) {
  NSURL *url = [NSURL URLWithString:[@"xrpc/" stringByAppendingString:method] relativeToURL:baseURL];
  if (!url || !token) return;
  NSError *encodeError = nil; NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError]; if (!data) return;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url]; request.HTTPMethod = @"POST";
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"]; request.HTTPBody = data;
  [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:nil completion:
      ^(NSData *responseData, NSHTTPURLResponse *response, NSError *error) {
        /* The persistent reconciler retries best-effort notification failures. */
      }];
}

static void SpaceNotifyAuthority(id<XrpcRoutePackServices> services, PDSSpaceURI *space,
                                 NSString *writer, NSDictionary *writeState) {
  if ([space.authorityDID isEqualToString:writer]) {
    [services.spaceStore recordWriter:writer forSpace:space.spaceURI rev:writeState[@"rev"] hash:writeState[@"hash"] error:nil];
    return;
  }
  DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:space.authorityDID error:nil];
  NSURL *endpoint = [NSURL URLWithString:[ATProtoDIDDocumentFields spaceHostEndpointFromDocument:doc] ?: @""];
  PDSActorStore *actor = [services.userDatabasePool storeForDid:writer error:nil];
  NSString *token = [services.jwtMinter mintServiceAuthJWTForDID:writer aud:space.authorityDID
      lxm:@"com.atproto.space.notifyWrite" actorKeyManager:actor.keyManager error:nil];
  if (!endpoint || !token || !writeState[@"hash"] || !writeState[@"rev"]) return;
  SpacePostJSON(endpoint, @"com.atproto.space.notifyWrite", @{ @"space" : space.spaceURI, @"repo" : writer,
      @"rev" : writeState[@"rev"], @"hash" : [writeState[@"hash"] base64EncodedStringWithOptions:0] }, token);
}

static void SpaceNotifyDeletion(id<XrpcRoutePackServices> services, PDSSpaceURI *space) {
  PDSActorStore *actor = [services.userDatabasePool storeForDid:space.authorityDID error:nil];
  if (!actor) return;
  for (NSDictionary *recipient in [services.spaceStore credentialRecipientsForSpace:space.spaceURI error:nil]) {
    NSString *token = [services.jwtMinter mintServiceAuthJWTForDID:space.authorityDID
                                                                 aud:recipient[@"serviceDID"]
                                                                 lxm:@"com.atproto.space.notifySpaceDeleted"
                                                  actorKeyManager:actor.keyManager
                                                             error:nil];
    if (!token) continue;
    SpacePostJSON([NSURL URLWithString:recipient[@"serviceEndpoint"]],
                  @"com.atproto.space.notifySpaceDeleted", @{ @"space" : space.spaceURI }, token);
  }
}

@implementation XrpcSpacePack

+ (NSString *)routePackIdentifier { return @"com.atproto.space"; }

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  PDSSpaceStore *store = services.spaceStore;
  if (!store) return; // Feature flag is off: no experimental API surface.
  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getSpace handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:[request headerForKey:@"Authorization"]
                                                     services:resolvedServices request:request response:response];
    if (!did) return;
    if (![did isEqualToString:space.authorityDID]) {
      SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return;
    }
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil];
    if (!info || ![info[@"isOwner"] boolValue] || info[@"deletedAt"] != [NSNull null]) {
      SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return;
    }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"uri" : space.spaceURI, @"config" : SpaceConfig(info) }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getRecord handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *repo = SpaceString([request queryParamForKey:@"repo"]), *collection = SpaceString([request queryParamForKey:@"collection"]), *rkey = SpaceString([request queryParamForKey:@"rkey"]);
    if (![ATProtoValidator validateDID:repo error:nil] || ![ATProtoValidator validateNSID:collection error:nil] || rkey.length == 0) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo, collection, and rkey are required"); return; }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, collection)) return;
    NSDictionary *record = [store recordForSpace:space.spaceURI author:repo collection:collection rkey:rkey error:nil];
    if (!record) { SpaceError(response, HttpStatusNotFound, @"RecordNotFound", @"Record not found"); return; }
    response.statusCode = HttpStatusOK; [response setJsonBody:SpaceRecordView(space, repo, record, YES)];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_listRecords handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *repo = SpaceString([request queryParamForKey:@"repo"]), *collection = SpaceString([request queryParamForKey:@"collection"]);
    if (![ATProtoValidator validateDID:repo error:nil] || (collection && ![ATProtoValidator validateNSID:collection error:nil])) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo and collection are invalid"); return; }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, collection)) return;
    NSUInteger limit = SpaceLimit(request, 50, 100, response); if (!limit) return;
    BOOL reverse = [[request queryParamForKey:@"reverse"] boolValue], excluded = [[request queryParamForKey:@"excludeValues"] boolValue];
    NSArray *records = [store recordsForSpace:space.spaceURI author:repo collection:collection limit:limit cursor:[request queryParamForKey:@"cursor"] reverse:reverse error:nil];
    NSMutableArray *views = [NSMutableArray array]; for (NSDictionary *record in records) [views addObject:SpaceRecordView(space, repo, record, !excluded)];
    NSMutableDictionary *result = [@{ @"records" : views } mutableCopy];
    if (records.count == limit) { NSDictionary *last = records.lastObject; result[@"cursor"] = [NSString stringWithFormat:@"%@/%@", last[@"collection"], last[@"rkey"]]; }
    response.statusCode = HttpStatusOK; [response setJsonBody:result];
  }];

  void (^applyWrites)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSString *repo = SpaceString(body[@"repo"]); NSArray *items = [body[@"writes"] isKindOfClass:[NSArray class]] ? body[@"writes"] : nil;
    if (!repo || !items || items.count == 0 || items.count > 200) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo and 1-200 writes are required"); return; }
    NSDictionary *credential = SpaceCredentialAuthentication(request, response, space);
    NSDictionary *auth = credential ? nil : SpaceOAuthAuthentication(request, response, resolvedServices);
    if (!credential && !auth) return;
    NSMutableArray *writes = [NSMutableArray array]; for (id item in items) { PDSSpaceWrite *write = [item isKindOfClass:[NSDictionary class]] ? SpaceWriteFromDictionary(item, YES, response) : nil; if (!write) return; [writes addObject:write]; }
    if (!credential && !SpaceCanWrite(auth, space, repo, writes, response)) return;
    NSError *error = nil; NSDictionary *commit = [store applyWrites:writes toSpace:space.spaceURI author:repo rev:nil error:&error];
    if (!commit) { SpaceError(response, error.code == PDSSpaceStoreErrorSpaceNotFound ? HttpStatusNotFound : HttpStatusBadRequest, error.code == PDSSpaceStoreErrorSpaceNotFound ? @"SpaceNotFound" : @"InvalidRequest", error.localizedDescription ?: @"Write rejected"); return; }
    SpaceNotifyAuthority(resolvedServices, space, repo, commit);
    NSMutableArray *results = [NSMutableArray array]; for (PDSSpaceWrite *write in writes) { NSMutableDictionary *result = [@{ @"$type" : [NSString stringWithFormat:@"com.atproto.space.applyWrites#%@Result", write.action == PDSSpaceWriteActionCreate ? @"create" : write.action == PDSSpaceWriteActionUpdate ? @"update" : @"delete"], @"uri" : SpaceRecordURI(space, repo, write.collection, write.rkey) } mutableCopy]; if (write.cid) result[@"cid"] = write.cid; [results addObject:result]; }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"results" : results }];
  };
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_applyWrites handler:^(HttpRequest *request, HttpResponse *response) { applyWrites(request, response); }];

  void (^singleWrite)(HttpRequest *, HttpResponse *, PDSSpaceWriteAction) = ^(HttpRequest *request, HttpResponse *response, PDSSpaceWriteAction action) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSString *repo = SpaceString(body[@"repo"]); NSMutableDictionary *item = [body mutableCopy] ?: [NSMutableDictionary dictionary]; item[@"action"] = action == PDSSpaceWriteActionCreate ? @"create" : action == PDSSpaceWriteActionUpdate ? @"update" : @"delete"; item[@"value"] = body[@"record"];
    PDSSpaceWrite *write = SpaceWriteFromDictionary(item, action == PDSSpaceWriteActionCreate, response); if (!repo || !write) { if (!write && response.statusCode == HttpStatusOK) SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo is required"); return; }
    NSDictionary *credential = SpaceCredentialAuthentication(request, response, space);
    NSDictionary *auth = credential ? nil : SpaceOAuthAuthentication(request, response, resolvedServices);
    if (!credential && !auth) return;
    if (!credential && action == PDSSpaceWriteActionUpdate && !SpaceAllows(auth, space, PDSSpaceActionCreate, write.collection)) { SpaceError(response, HttpStatusForbidden, @"InsufficientScope", @"putRecord requires create and update scope"); return; }
    if (!credential && !SpaceCanWrite(auth, space, repo, @[write], response)) return;
    NSError *error = nil; NSDictionary *writeState = [store applyWrites:@[write] toSpace:space.spaceURI author:repo rev:nil error:&error]; if (!writeState) { SpaceError(response, error.code == PDSSpaceStoreErrorSpaceNotFound ? HttpStatusNotFound : HttpStatusBadRequest, error.code == PDSSpaceStoreErrorSpaceNotFound ? @"SpaceNotFound" : @"InvalidRequest", error.localizedDescription ?: @"Write rejected"); return; }
    SpaceNotifyAuthority(resolvedServices, space, repo, writeState);
    response.statusCode = HttpStatusOK; if (action == PDSSpaceWriteActionDelete) [response setJsonBody:@{}]; else [response setJsonBody:@{ @"uri" : SpaceRecordURI(space, repo, write.collection, write.rkey), @"cid" : write.cid, @"validationStatus" : @"unknown" }];
  };
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_createRecord handler:^(HttpRequest *r, HttpResponse *p) { singleWrite(r, p, PDSSpaceWriteActionCreate); }];
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_putRecord handler:^(HttpRequest *r, HttpResponse *p) { singleWrite(r, p, PDSSpaceWriteActionUpdate); }];
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_deleteRecord handler:^(HttpRequest *r, HttpResponse *p) { singleWrite(r, p, PDSSpaceWriteActionDelete); }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_createSpace handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; NSString *did = SpaceString(body[@"did"]), *type = SpaceString(body[@"type"]), *skey = SpaceString(body[@"skey"] ?: TID.tid.stringValue);
    if (![ATProtoValidator validateDID:did error:nil] || ![ATProtoValidator validateNSID:type error:nil]) { SpaceError(response, HttpStatusBadRequest, @"InvalidType", @"did and type must be valid"); return; }
    PDSSpaceURI *space = [PDSSpaceURI URIWithString:[NSString stringWithFormat:@"at://%@/space/%@/%@", did, type, skey] error:nil]; if (!space) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"Invalid space key"); return; }
    NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return; if (!SpaceAllowsManage(auth, space, @"create")) { SpaceError(response, HttpStatusForbidden, @"Forbidden", @"manage=create scope is required"); return; }
    NSDictionary *config = [body[@"config"] isKindOfClass:[NSDictionary class]] ? body[@"config"] : @{}; NSString *policy = SpaceString(config[@"policy"] ?: @"member-list"); NSDictionary *access = [config[@"appAccess"] isKindOfClass:[NSDictionary class]] ? config[@"appAccess"] : @{}; BOOL allowList = [SpaceString(access[@"$type"]) hasSuffix:@"#allowList"];
    if (!([policy isEqualToString:@"public"] || [policy isEqualToString:@"member-list"]) || allowList || config[@"managingApp"]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"managing-app and app allow-lists are not enabled in this experimental build"); return; }
    BOOL isOwner = [auth[@"did"] isEqualToString:did];
    NSError *error = nil; if (![store createSpace:space.spaceURI owner:isOwner policy:policy managingApp:nil appAccessType:@"open" appAllowed:@[] error:&error]) { SpaceError(response, HttpStatusConflict, @"SpaceAlreadyExists", error.localizedDescription ?: @"Space already exists"); return; }
    if (isOwner) [store addMember:did toSpace:space.spaceURI error:nil]; response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"uri" : space.spaceURI }];
  }];

  void (^members)(HttpRequest *, HttpResponse *, BOOL) = ^(HttpRequest *request, HttpResponse *response, BOOL add) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return; NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    if (![auth[@"did"] isEqualToString:space.authorityDID] || !SpaceAllowsManage(auth, space, @"update")) { SpaceError(response, HttpStatusForbidden, @"NotSpaceOwner", @"Owner manage=update scope is required"); return; }
    NSString *member = SpaceString(body[@"did"]); if (![ATProtoValidator validateDID:member error:nil]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"did is required"); return; }
    BOOL ok = add ? [store addMember:member toSpace:space.spaceURI error:nil] : [store removeMember:member fromSpace:space.spaceURI error:nil]; if (!ok) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; } response.statusCode = HttpStatusOK; [response setJsonBody:@{}];
  };
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_addMember handler:^(HttpRequest *r, HttpResponse *p) { members(r, p, YES); }];
  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_removeMember handler:^(HttpRequest *r, HttpResponse *p) { members(r, p, NO); }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_deleteSpace handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    if (![auth[@"did"] isEqualToString:space.authorityDID] || !SpaceAllowsManage(auth, space, @"delete")) { SpaceError(response, HttpStatusForbidden, @"NotSpaceOwner", @"Owner manage=delete scope is required"); return; }
    if (![store markSpaceDeleted:space.spaceURI error:nil]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; }
    SpaceNotifyDeletion(resolvedServices, space);
    response.statusCode = HttpStatusOK; [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getDelegationToken handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    if (!SpaceAllows(auth, space, PDSSpaceActionRead, nil)) { SpaceError(response, HttpStatusForbidden, @"InsufficientScope", @"Delegation requires whole-space read access"); return; }
    PDSActorStore *actor = [resolvedServices.userDatabasePool storeForDid:auth[@"did"] error:nil];
    NSString *token = [PDSSpaceJWT mintDelegationWithIssuer:auth[@"did"] audience:[space.authorityDID stringByAppendingString:@"#atproto_space_host"] space:space.spaceURI actorKeyManager:actor.keyManager now:nil expiration:nil error:nil];
    if (!token) { SpaceError(response, HttpStatusInternalServerError, @"InternalError", @"Unable to mint delegation token"); return; }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"token" : token }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getSpaceCredential handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    if (body[@"clientAttestation"]) { SpaceError(response, HttpStatusBadRequest, @"InvalidClientAttestation", @"Client attestation is not enabled for this host"); return; }
    NSString *token = SpaceAuthorizationToken(request); JWT *unverified = [JWT jwtWithToken:token error:nil];
    NSString *issuer = unverified.payload.iss; if (![ATProtoValidator validateDID:issuer error:nil]) { SpaceError(response, HttpStatusUnauthorized, @"InvalidDelegationToken", @"Delegation issuer is invalid"); return; }
    DIDDocument *userDocument = SpaceResolveDID(issuer, NO, response); if (!userDocument) return;
    NSData *key = SpacePublicKeyFromDIDKey([ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:userDocument]);
    NSDictionary *claims = key ? [PDSSpaceJWT verifyDelegation:token publicKey:key expectedIssuer:issuer expectedAudience:[space.authorityDID stringByAppendingString:@"#atproto_space_host"] expectedSubject:space.spaceURI now:nil error:nil] : nil;
    if (!claims) { userDocument = SpaceResolveDID(issuer, YES, response); key = SpacePublicKeyFromDIDKey([ATProtoDIDDocumentFields strictAtprotoSigningKeyMultibaseFromDocument:userDocument]); claims = key ? [PDSSpaceJWT verifyDelegation:token publicKey:key expectedIssuer:issuer expectedAudience:[space.authorityDID stringByAppendingString:@"#atproto_space_host"] expectedSubject:space.spaceURI now:nil error:nil] : nil; }
    if (!claims) { SpaceError(response, HttpStatusUnauthorized, @"InvalidDelegationToken", @"Delegation token did not verify"); return; }
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil];
    if (!info) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; }
    if (info[@"deletedAt"] != [NSNull null]) { SpaceError(response, HttpStatusGone, @"SpaceDeleted", @"Space has been deleted"); return; }
    BOOL authorized = [info[@"policy"] isEqualToString:@"public"] || [store isMember:issuer ofSpace:space.spaceURI error:nil];
    if (!authorized || ![info[@"appAccessType"] isEqualToString:@"open"]) { SpaceError(response, HttpStatusForbidden, @"UserNotAuthorized", @"User is not authorized for this space"); return; }
    NSDate *expires = [NSDate dateWithTimeIntervalSince1970:[claims[@"exp"] doubleValue]];
    if (![store consumeDelegationID:claims[@"jti"] expiresAt:expires now:[NSDate date] error:nil]) { SpaceError(response, HttpStatusUnauthorized, @"InvalidDelegationToken", @"Delegation token has already been used"); return; }
    PDSActorStore *authority = [resolvedServices.userDatabasePool storeForDid:space.authorityDID error:nil];
    if (!authority) { SpaceError(response, HttpStatusInternalServerError, @"InternalError", @"Authority signing store is unavailable"); return; }
    DIDDocument *authorityDocument = SpaceResolveDID(space.authorityDID, NO, response); if (!authorityDocument) return;
    NSString *credentialKeyID = nil;
    id<PDSActorKeyManager> credentialSigner = SpaceCredentialSignerForAuthorityDocument(authority, authorityDocument, &credentialKeyID);
    NSString *credential = [PDSSpaceJWT mintCredentialWithAuthority:space.authorityDID space:space.spaceURI keyID:credentialKeyID actorKeyManager:credentialSigner now:nil expiration:nil error:nil];
    if (!credential) { SpaceError(response, HttpStatusInternalServerError, @"InternalError", @"Unable to mint space credential"); return; }
    NSString *endpoint = [ATProtoDIDDocumentFields pdsEndpointFromDocument:userDocument];
    if (endpoint.length > 0) [store recordCredentialRecipientForSpace:space.spaceURI serviceDID:issuer serviceEndpoint:endpoint expiresAt:[[NSDate date] dateByAddingTimeInterval:PDSSpaceNotificationRegistrationLifetime] error:nil];
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"credential" : credential }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getLatestCommit handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *repo = SpaceString([request queryParamForKey:@"repo"]); if (!repo) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo is required"); return; }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, nil)) return;
    NSError *error = nil; NSDictionary *commit = SpaceSignedCommit(store, resolvedServices.userDatabasePool, space, repo, &error);
    response.statusCode = HttpStatusOK; [response setJsonBody:commit ? @{ @"commit" : commit } : @{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getRepo handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *repo = SpaceString([request queryParamForKey:@"repo"]); if (!repo) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo is required"); return; }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, nil)) return;
    NSData *car = SpaceRepoCAR(store, resolvedServices.userDatabasePool, space, repo, nil);
    if (!car) { SpaceError(response, HttpStatusNotFound, @"RepoNotFound", @"Space repository not found"); return; }
    response.statusCode = HttpStatusOK; response.contentType = @"application/vnd.ipld.car"; [response setBodyData:car];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_getBlob handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return;
    NSString *repo = SpaceString([request queryParamForKey:@"repo"]), *cid = SpaceString([request queryParamForKey:@"cid"]);
    if (![ATProtoValidator validateDID:repo error:nil] || ![CID cidFromString:cid]) {
      SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo and cid are required"); return;
    }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, nil)) return;
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil];
    if (!info || info[@"deletedAt"] != [NSNull null]) {
      SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return;
    }
    NSDictionary *blob = [store blobForCID:cid space:space.spaceURI author:repo error:nil];
    if (!blob) { SpaceError(response, HttpStatusNotFound, @"BlobNotFound", @"Space blob not found"); return; }
    response.statusCode = HttpStatusOK;
    response.contentType = blob[@"mimeType"] ?: @"application/octet-stream";
    SpaceApplyPrivateBlobResponseHeaders(response);
    [response setBodyData:blob[@"data"]];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_listRepoOps handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return; NSString *repo = SpaceString([request queryParamForKey:@"repo"]); if (!repo) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"repo is required"); return; }
    if (!SpaceReadAuthentication(request, response, resolvedServices, space, repo, nil)) return; NSUInteger limit = SpaceLimit(request, 100, 1000, response); if (!limit) return;
    NSArray *ops = [store repoOperationsForSpace:space.spaceURI author:repo since:[request queryParamForKey:@"since"] limit:limit error:nil]; NSMutableArray *views = [NSMutableArray array]; BOOL excluded = [[request queryParamForKey:@"excludeValues"] boolValue];
    for (NSDictionary *op in ops) { NSMutableDictionary *view = [@{ @"rev" : op[@"rev"], @"collection" : op[@"collection"], @"rkey" : op[@"rkey"], @"cid" : op[@"cid"] ?: [NSNull null], @"prev" : op[@"prev"] ?: [NSNull null] } mutableCopy]; if (!excluded && op[@"cid"] != [NSNull null]) { NSDictionary *record = [store recordForSpace:space.spaceURI author:repo collection:op[@"collection"] rkey:op[@"rkey"] error:nil]; if ([record[@"cid"] isEqual:op[@"cid"]]) { id value = [ATProtoDagCBOR decodeDataAsJSON:record[@"value"] error:nil]; if (value) view[@"value"] = value; } } [views addObject:view]; }
    NSMutableDictionary *result = [@{ @"ops" : views } mutableCopy]; if (ops.count < limit) { NSDictionary *commit = SpaceSignedCommit(store, resolvedServices.userDatabasePool, space, repo, nil); if (commit) result[@"commit"] = commit; }
    if (ops.count == limit) { result[@"cursor"] = [ops.lastObject[@"rev"] copy]; }
    response.statusCode = HttpStatusOK; [response setJsonBody:result];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_listRepos handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return; NSDictionary *credential = SpaceCredentialAuthentication(request, response, space); if (!credential || credential.count == 0) { if (response.statusCode == HttpStatusOK) SpaceError(response, HttpStatusUnauthorized, @"InvalidCredential", @"A valid space credential is required"); return; }
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil]; if (!info || ![info[@"isOwner"] boolValue] || info[@"deletedAt"] != [NSNull null]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; }
    NSUInteger limit = SpaceLimit(request, 100, 1000, response); if (!limit) return; NSArray *writers = [store writersForSpace:space.spaceURI limit:limit cursor:[request queryParamForKey:@"cursor"] error:nil];
    NSMutableArray *repos = [NSMutableArray array]; for (NSDictionary *writer in writers) [repos addObject:@{ @"did" : writer[@"did"], @"rev" : writer[@"rev"], @"hash" : [writer[@"hash"] base64EncodedStringWithOptions:0] }];
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"repos" : repos }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_listMembers handler:^(HttpRequest *request, HttpResponse *response) {
    PDSSpaceURI *space = SpaceURIFromString([request queryParamForKey:@"space"], response); if (!space) return; NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    if (![auth[@"did"] isEqualToString:space.authorityDID] || !SpaceAllowsManage(auth, space, @"update")) { SpaceError(response, HttpStatusForbidden, @"NotSpaceOwner", @"Owner manage=update scope is required"); return; }
    NSUInteger limit = SpaceLimit(request, 100, 1000, response); if (!limit) return; NSArray *membersList = [store listMembersForSpace:space.spaceURI limit:limit cursor:[request queryParamForKey:@"cursor"] error:nil]; NSMutableArray *membersViews = [NSMutableArray array]; for (NSString *did in membersList) [membersViews addObject:@{ @"did" : did }]; response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"members" : membersViews }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_updateSpace handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    if (![auth[@"did"] isEqualToString:space.authorityDID] || !SpaceAllowsManage(auth, space, @"update")) { SpaceError(response, HttpStatusForbidden, @"NotSpaceOwner", @"Owner manage=update scope is required"); return; }
    NSDictionary *old = [store spaceInfoForURI:space.spaceURI error:nil]; if (!old || old[@"deletedAt"] != [NSNull null] || ![old[@"isOwner"] boolValue]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; }
    NSString *policy = body[@"policy"]; NSDictionary *appAccess = [body[@"appAccess"] isKindOfClass:[NSDictionary class]] ? body[@"appAccess"] : nil;
    NSString *appType = nil; if (appAccess) appType = [SpaceString(appAccess[@"$type"]) hasSuffix:@"#open"] ? @"open" : @"invalid";
    if (policy && !([policy isEqualToString:@"public"] || [policy isEqualToString:@"member-list"])) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"managing-app is not enabled"); return; }
    if (appAccess && ![appType isEqualToString:@"open"]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"App allow-lists are not enabled"); return; }
    if (body[@"managingApp"] && ![body[@"managingApp"] isEqualToString:@""]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"managing-app is not enabled"); return; }
    if (![store updateSpace:space.spaceURI policy:policy managingApp:body[@"managingApp"] appAccessType:appType appAllowed:nil error:nil]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Space not found"); return; }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_listSpaces handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *auth = SpaceOAuthAuthentication(request, response, resolvedServices); if (!auth) return;
    NSString *type = SpaceString([request queryParamForKey:@"type"]), *owner = SpaceString([request queryParamForKey:@"did"]);
    if (type && ![ATProtoValidator validateNSID:type error:nil]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"type must be an NSID"); return; }
    if (owner && ![ATProtoValidator validateDID:owner error:nil]) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"did must be a DID"); return; }
    NSUInteger limit = SpaceLimit(request, 50, 100, response); if (!limit) return;
    NSArray *all = [store listSpacesWithLimit:limit cursor:[request queryParamForKey:@"cursor"] authority:owner type:type error:nil]; NSMutableArray *spaces = [NSMutableArray array];
    for (NSDictionary *candidate in all) { PDSSpaceURI *parsed = [PDSSpaceURI URIWithString:candidate[@"uri"] error:nil]; if (parsed && SpaceAllows(auth, parsed, PDSSpaceActionRead, nil)) [spaces addObject:@{ @"uri" : parsed.spaceURI, @"isOwner" : candidate[@"isOwner"] ?: @NO }]; }
    NSMutableDictionary *result = [@{ @"spaces" : spaces } mutableCopy]; if (spaces.count == limit) result[@"cursor"] = spaces.lastObject[@"uri"]; response.statusCode = HttpStatusOK; [response setJsonBody:result];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_notifyWrite handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil]; BOOL isAuthority = [info[@"isOwner"] boolValue];
    NSString *repo = SpaceString(body[@"repo"]), *rev = SpaceString(body[@"rev"]), *issuer = SpaceServiceAuthentication(request, response, isAuthority ? space.authorityDID : nil, @"com.atproto.space.notifyWrite"); if (!issuer) return;
    NSData *hash = [body[@"hash"] isKindOfClass:[NSString class]] ? [[NSData alloc] initWithBase64EncodedString:body[@"hash"] options:0] : nil;
    if (!repo || rev.length == 0 || hash.length != 32) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"notifyWrite body is invalid"); return; }
    if (!isAuthority) { if (![issuer isEqualToString:space.authorityDID]) { SpaceError(response, HttpStatusForbidden, @"Forbidden", @"Replica notifications must originate at the authority"); return; } [store recordWriter:repo forSpace:space.spaceURI rev:rev hash:hash error:nil]; response.statusCode = HttpStatusOK; [response setJsonBody:@{}]; return; }
    if (![issuer isEqualToString:repo] || ![ATProtoValidator validateDID:repo error:nil]) { SpaceError(response, HttpStatusForbidden, @"Forbidden", @"notifyWrite must be signed by its claimed writer"); return; }
    if (!info || info[@"deletedAt"] != [NSNull null]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Authority space not found"); return; }
    if (![store isMember:repo ofSpace:space.spaceURI error:nil]) { SpaceError(response, HttpStatusForbidden, @"Forbidden", @"Writer is not a member of this space"); return; }
    if (![store recordWriter:repo forSpace:space.spaceURI rev:rev hash:hash error:nil]) { SpaceError(response, HttpStatusInternalServerError, @"InternalError", @"Unable to record writer state"); return; }
    for (NSDictionary *recipient in [store credentialRecipientsForSpace:space.spaceURI error:nil]) {
      PDSActorStore *actor = [resolvedServices.userDatabasePool storeForDid:space.authorityDID error:nil];
      NSString *token = [resolvedServices.jwtMinter mintServiceAuthJWTForDID:space.authorityDID aud:recipient[@"serviceDID"] lxm:@"com.atproto.space.notifyWrite" actorKeyManager:actor.keyManager error:nil];
      SpacePostJSON([NSURL URLWithString:recipient[@"serviceEndpoint"]], @"com.atproto.space.notifyWrite", @{ @"space" : space.spaceURI, @"repo" : repo, @"rev" : rev, @"hash" : body[@"hash"] }, token);
    }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_notifySpaceDeleted handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSString *issuer = SpaceServiceAuthentication(request, response, nil, @"com.atproto.space.notifySpaceDeleted"); if (!issuer) return;
    if (![issuer isEqualToString:space.authorityDID]) { SpaceError(response, HttpStatusForbidden, @"UntrustedIss", @"Only the authority may delete a space replica"); return; }
    [store markReplicatedSpaceDeleted:space.spaceURI error:nil]; response.statusCode = HttpStatusOK; [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_space_registerNotify handler:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody; PDSSpaceURI *space = SpaceURIFromString(body[@"space"], response); if (!space) return;
    NSString *endpointString = SpaceString(body[@"endpoint"]); NSURLComponents *endpoint = [NSURLComponents componentsWithString:endpointString];
    if (!endpoint || !([endpoint.scheme isEqualToString:@"https"] || [endpoint.scheme isEqualToString:@"http"]) || endpoint.host.length == 0 || endpoint.user.length || endpoint.password.length) { SpaceError(response, HttpStatusBadRequest, @"InvalidRequest", @"endpoint must be an HTTP(S) URI"); return; }
    NSDictionary *credential = SpaceCredentialAuthentication(request, response, space);
    if (!credential || credential.count == 0) { if (response.statusCode == HttpStatusOK) SpaceError(response, HttpStatusUnauthorized, @"InvalidCredential", @"A valid space credential is required"); return; }
    NSDictionary *info = [store spaceInfoForURI:space.spaceURI error:nil]; if (!info || ![info[@"isOwner"] boolValue] || info[@"deletedAt"] != [NSNull null]) { SpaceError(response, HttpStatusNotFound, @"SpaceNotFound", @"Authority space not found"); return; }
    NSDate *expiresAt = [[NSDate date] dateByAddingTimeInterval:PDSSpaceNotificationRegistrationLifetime];
    if (![store recordCredentialRecipientForSpace:space.spaceURI serviceDID:endpointString serviceEndpoint:endpointString expiresAt:expiresAt error:nil]) { SpaceError(response, HttpStatusInternalServerError, @"InternalError", @"Unable to register notification"); return; }
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"expiresAt" : [NSDateFormatter atproto_stringFromDate:expiresAt] }];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_simplespace_checkUserAccess handler:^(HttpRequest *request, HttpResponse *response) {
    /* Generic PDS instances are not managing apps. A verified service request
     * receives the baseline deny decision; applications override this NSID. */
    NSString *spaceString = [request queryParamForKey:@"space"]; PDSSpaceURI *space = SpaceURIFromString(spaceString, response); if (!space) return;
    if (!SpaceServiceAuthentication(request, response, space.authorityDID, @"com.atproto.simplespace.checkUserAccess")) return;
    response.statusCode = HttpStatusOK; [response setJsonBody:@{ @"authorized" : @NO }];
  }];
} 

@end
