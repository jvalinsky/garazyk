// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/ATProtoPermissionScope.h"
#import "Core/ATProtoValidator.h"

NSString *const ATProtoPermissionScopeErrorDomain = @"com.garazyk.permission.scope";

@interface ATProtoPermissionScope ()
@property (nonatomic, readwrite) ATProtoPermissionScopeResourceType resourceType;
@property (nonatomic, readwrite, copy) NSString *resourceTypeString;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSString *> *collections;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSString *> *actions;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSString *> *lxm;
@property (nonatomic, readwrite, copy, nullable) NSString *aud;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSString *> *accept;
@property (nonatomic, readwrite, copy, nullable) NSString *attr;
@property (nonatomic, readwrite, copy, nullable) NSString *accountAction;
@property (nonatomic, readwrite, copy, nullable) NSString *identityAttr;
@property (nonatomic, readwrite, copy, nullable) NSString *permissionSetNSID;
@end

@implementation ATProtoPermissionScope

+ (nullable instancetype)scopeWithString:(NSString *)scope error:(NSError **)error {
  if (![scope isKindOfClass:[NSString class]] || scope.length == 0) {
    return [self error:@"Scope string is empty" code:ATProtoPermissionScopeErrorInvalidSyntax error:error];
  }
  if ([scope rangeOfString:@" "].location != NSNotFound) {
    return [self error:@"Scope string must not contain spaces" code:ATProtoPermissionScopeErrorInvalidSyntax error:error];
  }

  NSRange colon = [scope rangeOfString:@":"];
  NSRange question = [scope rangeOfString:@"?"];

  NSString *resourceStr;
  NSString *positional = nil;
  NSString *queryStr = nil;

  if (colon.location == NSNotFound && question.location == NSNotFound) {
    resourceStr = scope;
  } else if (colon.location == NSNotFound && question.location != NSNotFound) {
    resourceStr = [scope substringToIndex:question.location];
    queryStr = [scope substringFromIndex:NSMaxRange(question)];
  } else if (question.location != NSNotFound && question.location < colon.location) {
    resourceStr = [scope substringToIndex:question.location];
    queryStr = [scope substringFromIndex:NSMaxRange(question)];
  } else {
    resourceStr = [scope substringToIndex:colon.location];
    NSUInteger positionalEnd = (question.location != NSNotFound) ? question.location : scope.length;
    positional = [scope substringWithRange:NSMakeRange(NSMaxRange(colon), positionalEnd - NSMaxRange(colon))];
    if (question.location != NSNotFound) {
      queryStr = [scope substringFromIndex:NSMaxRange(question)];
    }
  }

  NSString *resourceTypeKey = [resourceStr lowercaseString];
  ATProtoPermissionScopeResourceType rtype;
  if ([resourceTypeKey isEqualToString:@"repo"]) {
    rtype = ATProtoPermissionScopeResourceRepo;
  } else if ([resourceTypeKey isEqualToString:@"rpc"]) {
    rtype = ATProtoPermissionScopeResourceRPC;
  } else if ([resourceTypeKey isEqualToString:@"blob"]) {
    rtype = ATProtoPermissionScopeResourceBlob;
  } else if ([resourceTypeKey isEqualToString:@"account"]) {
    rtype = ATProtoPermissionScopeResourceAccount;
  } else if ([resourceTypeKey isEqualToString:@"identity"]) {
    rtype = ATProtoPermissionScopeResourceIdentity;
  } else if ([resourceTypeKey isEqualToString:@"include"]) {
    rtype = ATProtoPermissionScopeResourceInclude;
  } else {
    return [self error:[NSString stringWithFormat:@"Unknown resource type: %@", resourceStr]
                  code:ATProtoPermissionScopeErrorInvalidSyntax
                 error:error];
  }

  ATProtoPermissionScope *result = [[ATProtoPermissionScope alloc] init];
  result.resourceType = rtype;
  result.resourceTypeString = resourceTypeKey;

  NSMutableDictionary<NSString *, NSMutableArray *> *params = [NSMutableDictionary dictionary];
  if (queryStr.length > 0) {
    for (NSString *entry in [queryStr componentsSeparatedByString:@"&"]) {
      if (entry.length == 0) continue;
      NSRange eq = [entry rangeOfString:@"="];
      NSString *key, *value;
      if (eq.location == NSNotFound) {
        key = entry;
        value = @"";
      } else {
        key = [entry substringToIndex:eq.location];
        value = [entry substringFromIndex:NSMaxRange(eq)];
        value = [value stringByRemovingPercentEncoding] ?: value;
      }
      if (!params[key]) params[key] = [NSMutableArray array];
      [params[key] addObject:value];
    }
  }

  switch (rtype) {
    case ATProtoPermissionScopeResourceRepo:
      return [result parseRepo:positional params:params error:error];
    case ATProtoPermissionScopeResourceRPC:
      return [result parseRPC:positional params:params error:error];
    case ATProtoPermissionScopeResourceBlob:
      return [result parseBlob:positional params:params error:error];
    case ATProtoPermissionScopeResourceAccount:
      return [result parseAccount:positional params:params error:error];
    case ATProtoPermissionScopeResourceIdentity:
      return [result parseIdentity:positional params:params error:error];
    case ATProtoPermissionScopeResourceInclude:
      return [result parseInclude:positional params:params error:error];
  }
}

#pragma mark - Repo

- (nullable instancetype)parseRepo:(NSString *)positional
                            params:(NSDictionary<NSString *, NSMutableArray *> *)params
                             error:(NSError **)error {
  NSMutableArray<NSString *> *collections = [NSMutableArray array];
  if (positional.length > 0) {
    [collections addObject:positional];
  }
  for (NSString *val in params[@"collection"] ?: @[]) {
    [collections addObject:val];
  }
  if (collections.count == 0) {
    return [ATProtoPermissionScope error:@"repo scope requires at least one collection"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  for (NSString *c in collections) {
    if (![c isEqualToString:@"*"] && ![ATProtoValidator validateNSID:c error:nil]) {
      return [ATProtoPermissionScope error:[NSString stringWithFormat:@"Invalid collection NSID: %@", c]
                                     code:ATProtoPermissionScopeErrorInvalidValue
                                    error:error];
    }
  }
  if ([collections containsObject:@"*"]) {
    self.collections = @[@"*"];
  } else {
    self.collections = [[NSSet setWithArray:collections] allObjects];
  }

  NSArray<NSString *> *rawActions = params[@"action"] ?: @[];
  NSMutableArray<NSString *> *actions = [NSMutableArray array];
  for (NSString *a in rawActions) {
    if ([a isEqualToString:@"create"] || [a isEqualToString:@"update"] || [a isEqualToString:@"delete"]) {
      if (![actions containsObject:a]) [actions addObject:a];
    } else {
      return [ATProtoPermissionScope error:[NSString stringWithFormat:@"Invalid repo action: %@", a]
                                     code:ATProtoPermissionScopeErrorInvalidValue
                                    error:error];
    }
  }
  self.actions = actions.count > 0 ? [actions copy] : nil;
  return self;
}

#pragma mark - RPC

- (nullable instancetype)parseRPC:(NSString *)positional
                           params:(NSDictionary<NSString *, NSMutableArray *> *)params
                            error:(NSError **)error {
  NSMutableArray<NSString *> *methods = [NSMutableArray array];
  if (positional.length > 0) {
    [methods addObject:positional];
  }
  for (NSString *val in params[@"lxm"] ?: @[]) {
    [methods addObject:val];
  }
  if (methods.count == 0) {
    return [ATProtoPermissionScope error:@"rpc scope requires at least one lxm"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  for (NSString *m in methods) {
    if (![m isEqualToString:@"*"] && ![ATProtoValidator validateNSID:m error:nil]) {
      return [ATProtoPermissionScope error:[NSString stringWithFormat:@"Invalid lxm NSID: %@", m]
                                     code:ATProtoPermissionScopeErrorInvalidValue
                                    error:error];
    }
  }
  self.lxm = [[NSSet setWithArray:methods] allObjects];

  NSString *audVal = params[@"aud"] ? params[@"aud"].firstObject : nil;
  if (audVal.length > 0) {
    self.aud = audVal;
  } else {
    self.aud = @"*";
  }

  if ([self.lxm containsObject:@"*"] && [self.aud isEqualToString:@"*"]) {
    return [ATProtoPermissionScope error:@"rpc scope must restrict at least one of lxm or aud"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  return self;
}

#pragma mark - Blob

- (nullable instancetype)parseBlob:(NSString *)positional
                            params:(NSDictionary<NSString *, NSMutableArray *> *)params
                             error:(NSError **)error {
  NSMutableArray<NSString *> *types = [NSMutableArray array];
  if (positional.length > 0) {
    [types addObject:positional];
  }
  for (NSString *val in params[@"accept"] ?: @[]) {
    [types addObject:val];
  }
  if (types.count == 0) {
    return [ATProtoPermissionScope error:@"blob scope requires at least one accept type"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  self.accept = [[NSSet setWithArray:types] allObjects];
  return self;
}

#pragma mark - Account

- (nullable instancetype)parseAccount:(NSString *)positional
                               params:(NSDictionary<NSString *, NSMutableArray *> *)params
                                error:(NSError **)error {
  NSString *attrVal = positional ?: params[@"attr"] ? params[@"attr"].firstObject : nil;
  if (attrVal.length == 0) {
    return [ATProtoPermissionScope error:@"account scope requires an attr parameter"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  if (!([attrVal isEqualToString:@"email"] || [attrVal isEqualToString:@"repo"])) {
    return [ATProtoPermissionScope error:[NSString stringWithFormat:@"Unknown account attr: %@", attrVal]
                                   code:ATProtoPermissionScopeErrorInvalidValue
                                  error:error];
  }
  self.attr = attrVal;

  NSString *act = params[@"action"] ? params[@"action"].firstObject : nil;
  if (act.length > 0 && !([act isEqualToString:@"read"] || [act isEqualToString:@"manage"])) {
    return [ATProtoPermissionScope error:[NSString stringWithFormat:@"Invalid account action: %@", act]
                                   code:ATProtoPermissionScopeErrorInvalidValue
                                  error:error];
  }
  self.accountAction = act ?: @"read";
  return self;
}

#pragma mark - Identity

- (nullable instancetype)parseIdentity:(NSString *)positional
                                params:(NSDictionary<NSString *, NSMutableArray *> *)params
                                 error:(NSError **)error {
  NSString *attrVal = positional ?: params[@"attr"] ? params[@"attr"].firstObject : nil;
  if (attrVal.length == 0) {
    return [ATProtoPermissionScope error:@"identity scope requires an attr parameter"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  self.identityAttr = attrVal;
  return self;
}

#pragma mark - Include

- (nullable instancetype)parseInclude:(NSString *)positional
                               params:(NSDictionary<NSString *, NSMutableArray *> *)params
                                error:(NSError **)error {
  NSString *nsid = positional ?: params[@"set"] ? params[@"set"].firstObject : nil;
  if (nsid.length == 0 || (![nsid isEqualToString:@"*"] && ![ATProtoValidator validateNSID:nsid error:nil])) {
    return [ATProtoPermissionScope error:@"include scope requires a valid permission set NSID"
                                   code:ATProtoPermissionScopeErrorInvalidSyntax
                                  error:error];
  }
  self.permissionSetNSID = nsid;
  NSString *audVal = params[@"aud"] ? params[@"aud"].firstObject : nil;
  if (audVal.length > 0) self.aud = audVal;
  return self;
}

#pragma mark - Matching

- (BOOL)matchesCollection:(nullable NSString *)collection action:(nullable NSString *)action {
  if (self.resourceType != ATProtoPermissionScopeResourceRepo) return NO;
  if (collection.length == 0 || self.collections.count == 0) return NO;
  if (![self.collections containsObject:@"*"] && ![self.collections containsObject:collection]) return NO;
  if (action.length == 0) return YES;
  if (self.actions == nil) return YES;
  return [self.actions containsObject:action];
}

- (BOOL)matchesMethod:(NSString *)methodNSID aud:(nullable NSString *)audience {
  if (self.resourceType != ATProtoPermissionScopeResourceRPC) return NO;
  if (methodNSID.length == 0 || self.lxm.count == 0) return NO;
  if (![self.lxm containsObject:@"*"] && ![self.lxm containsObject:methodNSID]) return NO;
  if (self.aud == nil || [self.aud isEqualToString:@"*"]) return YES;
  return audience.length > 0 && [self.aud isEqualToString:audience];
}

- (BOOL)matchesBlobAccept:(NSString *)mimeType {
  if (self.resourceType != ATProtoPermissionScopeResourceBlob) return NO;
  if (mimeType.length == 0 || self.accept.count == 0) return NO;
  for (NSString *pattern in self.accept) {
    if ([pattern isEqualToString:@"*/*"]) return YES;
    NSRange slash = [pattern rangeOfString:@"/"];
    if (slash.location != NSNotFound && [[pattern substringFromIndex:slash.location + 1] isEqualToString:@"*"]) {
      NSString *typePrefix = [pattern substringToIndex:slash.location];
      NSRange mimeSlash = [mimeType rangeOfString:@"/"];
      if (mimeSlash.location != NSNotFound) {
        NSString *mimePrefix = [mimeType substringToIndex:mimeSlash.location];
        if ([typePrefix caseInsensitiveCompare:mimePrefix] == NSOrderedSame) return YES;
      }
    } else {
      if ([pattern caseInsensitiveCompare:mimeType] == NSOrderedSame) return YES;
    }
  }
  return NO;
}

- (BOOL)matchesAccountAttr:(NSString *)attribute action:(nullable NSString *)action {
  if (self.resourceType != ATProtoPermissionScopeResourceAccount) return NO;
  if (attribute.length == 0 || self.attr.length == 0) return NO;
  if (![self.attr isEqualToString:attribute]) return NO;
  if (action == nil || [action isEqualToString:@"read"]) return YES;
  if ([action isEqualToString:@"manage"] && [self.accountAction isEqualToString:@"manage"]) return YES;
  return NO;
}

- (BOOL)matchesIdentityAttr:(NSString *)attribute {
  if (self.resourceType != ATProtoPermissionScopeResourceIdentity) return NO;
  if (attribute.length == 0 || self.identityAttr.length == 0) return NO;
  return [self.identityAttr isEqualToString:@"*"] || [self.identityAttr isEqualToString:attribute];
}

#pragma mark - Helpers

+ (instancetype)error:(NSString *)message code:(ATProtoPermissionScopeError)code error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:ATProtoPermissionScopeErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message}];
  }
  return nil;
}

@end
