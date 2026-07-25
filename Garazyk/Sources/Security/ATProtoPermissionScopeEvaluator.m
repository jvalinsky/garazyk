// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/ATProtoPermissionScopeEvaluator.h"
#import "Security/ATProtoPermissionScope.h"
#import "Security/Space/PDSSpaceScope.h"
#import "Auth/JWT.h"

@implementation ATProtoPermissionScopeEvaluator

#pragma mark - Extraction

+ (NSArray<ATProtoPermissionScope *> *)scopesFromScopeString:(NSString *)scopeString {
  if (![scopeString isKindOfClass:[NSString class]] || scopeString.length == 0) return @[];

  NSMutableArray<ATProtoPermissionScope *> *result = [NSMutableArray array];
  NSArray<NSString *> *candidates = [scopeString componentsSeparatedByCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

  for (NSString *candidate in candidates) {
    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) continue;
    if ([trimmed hasPrefix:@"space:"]) continue;
    ATProtoPermissionScope *scope = [ATProtoPermissionScope scopeWithString:trimmed error:nil];
    if (scope) [result addObject:scope];
  }

  return [result copy];
}

+ (NSArray<ATProtoPermissionScope *> *)scopesFromJWT:(JWT *)jwt {
  NSString *scopeString = jwt.payload.scope;
  return [self scopesFromScopeString:scopeString];
}

+ (BOOL)validateOAuthScopeString:(NSString *)scopeString {
  if (![scopeString isKindOfClass:[NSString class]] || scopeString.length == 0) {
    return NO;
  }

  BOOL containsAtproto = NO;
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSSet<NSString *> *transitionScopes = [NSSet setWithArray:@[
      @"transition:generic", @"transition:chat.bsky", @"transition:email",
  ]];
  for (NSString *scope in [scopeString componentsSeparatedByCharactersInSet:whitespace]) {
    if (scope.length == 0) continue;
    if ([scope isEqualToString:@"atproto"]) {
      containsAtproto = YES;
      continue;
    }
    if ([transitionScopes containsObject:scope]) continue;
    if ([scope hasPrefix:@"space:"]) {
      if (![PDSSpaceScope scopeWithString:scope error:nil]) return NO;
      continue;
    }
    ATProtoPermissionScope *parsed = [ATProtoPermissionScope scopeWithString:scope error:nil];
    if (!parsed) return NO;
    /* `include:` is syntactically valid here. OAuth token issuance resolves it
       through ATProtoPermissionSetResolver before minting an access token. */
  }
  return containsAtproto;
}

#pragma mark - RPC Scope Evaluation

+ (BOOL)evaluateRPCScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                forMethod:(NSString *)methodNSID
                  audience:(nullable NSString *)audience {
  if (scopes.count == 0) return YES;

  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceRPC) {
      if (methodNSID.length > 0 && [scope matchesMethod:methodNSID aud:audience]) return YES;
    }
  }

  BOOL hasRPCScopes = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceRPC) {
      hasRPCScopes = YES;
      break;
    }
  }
  return !hasRPCScopes;
}

#pragma mark - Repo Scope Evaluation

+ (BOOL)evaluateRepoScopes:(NSArray<ATProtoPermissionScope *> *)scopes
              forCollection:(NSString *)collection
                     action:(NSString *)action {
  if (scopes.count == 0 || collection.length == 0) return YES;

  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceRepo) {
      if ([scope matchesCollection:collection action:action]) return YES;
    }
  }

  BOOL hasRepoScopes = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceRepo) {
      hasRepoScopes = YES;
      break;
    }
  }
  return !hasRepoScopes;
}

#pragma mark - Blob Scope Evaluation

+ (BOOL)evaluateBlobScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                   forMIME:(NSString *)mimeType {
  if (scopes.count == 0 || mimeType.length == 0) return YES;

  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceBlob) {
      if ([scope matchesBlobAccept:mimeType]) return YES;
    }
  }

  BOOL hasBlobScopes = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceBlob) {
      hasBlobScopes = YES;
      break;
    }
  }
  return !hasBlobScopes;
}

#pragma mark - Account Scope Evaluation

+ (BOOL)evaluateAccountScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                 forAttribute:(NSString *)attribute
                       action:(nullable NSString *)action {
  if (scopes.count == 0 || attribute.length == 0) return YES;

  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceAccount) {
      if ([scope matchesAccountAttr:attribute action:action ?: @"read"]) return YES;
    }
  }

  BOOL hasAccountScopes = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceAccount) {
      hasAccountScopes = YES;
      break;
    }
  }
  return !hasAccountScopes;
}

#pragma mark - Identity Scope Evaluation

+ (BOOL)evaluateIdentityScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                  forAttribute:(NSString *)attribute {
  if (scopes.count == 0 || attribute.length == 0) return YES;

  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceIdentity) {
      if ([scope matchesIdentityAttr:attribute]) return YES;
    }
  }

  BOOL hasIdentityScopes = NO;
  for (ATProtoPermissionScope *scope in scopes) {
    if (scope.resourceType == ATProtoPermissionScopeResourceIdentity) {
      hasIdentityScopes = YES;
      break;
    }
  }
  return !hasIdentityScopes;
}

@end
