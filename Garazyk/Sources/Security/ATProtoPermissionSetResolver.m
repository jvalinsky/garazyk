// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/ATProtoPermissionSetResolver.h"

#import "App/ATProtoServiceConfiguration.h"
#import "Security/ATProtoPermissionScope.h"

#include <float.h>

NSErrorDomain const ATProtoPermissionSetResolverErrorDomain = @"com.garazyk.permission-set";

@implementation ATProtoPermissionSetResolver

+ (NSMutableDictionary<NSString *, NSDictionary *> *)schemaCache {
  static NSMutableDictionary<NSString *, NSDictionary *> *cache;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
  return cache;
}

+ (nullable NSString *)error:(NSString *)message error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:ATProtoPermissionSetResolverErrorDomain
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey: message }];
  }
  return nil;
}

+ (NSString *)encodedValue:(NSString *)value {
  NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
  [allowed addCharactersInString:@"-._:"];
  return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

+ (nullable NSArray<NSString *> *)permissionsFromSchema:(NSDictionary *)schema
                                              includeAud:(nullable NSString *)includeAud
                                                   error:(NSError **)error {
  NSDictionary *main = [schema[@"defs"] isKindOfClass:[NSDictionary class]] ? schema[@"defs"][@"main"] : nil;
  if (![main isKindOfClass:[NSDictionary class]] || ![main[@"type"] isEqualToString:@"permission-set"]) {
    [self error:@"Resolved Lexicon is not a permission-set" error:error];
    return nil;
  }
  NSArray *permissions = [main[@"permissions"] isKindOfClass:[NSArray class]] ? main[@"permissions"] : nil;
  if (!permissions) {
    [self error:@"Permission set has no permissions array" error:error];
    return nil;
  }

  NSMutableArray<NSString *> *expanded = [NSMutableArray array];
  for (id item in permissions) {
    if (![item isKindOfClass:[NSDictionary class]]) continue; // Unknown declarations are ignored by the spec.
    NSDictionary *permission = item;
    if (![permission[@"type"] isEqualToString:@"permission"]) continue;
    NSString *resource = permission[@"resource"];
    if ([resource isEqualToString:@"repo"]) {
      NSArray *collections = [permission[@"collection"] isKindOfClass:[NSArray class]] ? permission[@"collection"] : nil;
      NSArray *actions = [permission[@"action"] isKindOfClass:[NSArray class]] ? permission[@"action"] : @[];
      if (collections.count == 0) {
        [self error:@"repo permission requires a collection" error:error];
        return nil;
      }
      NSMutableArray *parts = [NSMutableArray array];
      for (id collection in collections) {
        if (![collection isKindOfClass:[NSString class]]) {
          [self error:@"repo permission collection is invalid" error:error];
          return nil;
        }
        [parts addObject:[NSString stringWithFormat:@"collection=%@", [self encodedValue:collection]]];
      }
      for (id action in actions) {
        if (![action isKindOfClass:[NSString class]]) {
          [self error:@"repo permission action is invalid" error:error];
          return nil;
        }
        [parts addObject:[NSString stringWithFormat:@"action=%@", [self encodedValue:action]]];
      }
      NSString *scope = [NSString stringWithFormat:@"repo?%@", [parts componentsJoinedByString:@"&"]];
      if (![ATProtoPermissionScope scopeWithString:scope error:nil]) {
        [self error:@"Permission set contains an invalid repo permission" error:error];
        return nil;
      }
      [expanded addObject:scope];
    } else if ([resource isEqualToString:@"rpc"]) {
      NSArray *methods = [permission[@"lxm"] isKindOfClass:[NSArray class]] ? permission[@"lxm"] : nil;
      NSString *aud = [permission[@"aud"] isKindOfClass:[NSString class]] ? permission[@"aud"] : nil;
      if ([permission[@"inheritAud"] boolValue]) aud = includeAud;
      if (methods.count == 0 || aud.length == 0) {
        [self error:@"rpc permission requires lxm and an audience" error:error];
        return nil;
      }
      NSMutableArray *parts = [NSMutableArray array];
      for (id method in methods) {
        if (![method isKindOfClass:[NSString class]]) {
          [self error:@"rpc permission lxm is invalid" error:error];
          return nil;
        }
        [parts addObject:[NSString stringWithFormat:@"lxm=%@", [self encodedValue:method]]];
      }
      [parts addObject:[NSString stringWithFormat:@"aud=%@", [self encodedValue:aud]]];
      NSString *scope = [NSString stringWithFormat:@"rpc?%@", [parts componentsJoinedByString:@"&"]];
      if (![ATProtoPermissionScope scopeWithString:scope error:nil]) {
        [self error:@"Permission set contains an invalid rpc permission" error:error];
        return nil;
      }
      [expanded addObject:scope];
    } else {
      [self error:@"Permission sets may contain only repo or rpc permissions" error:error];
      return nil;
    }
  }
  return expanded;
}

+ (nullable NSString *)effectiveScopeForScope:(NSString *)scope
                         permissionSetSchemas:(NSDictionary<NSString *,NSDictionary *> *)schemas
                                        error:(NSError **)error {
  if (![scope isKindOfClass:[NSString class]] || scope.length == 0) return [self error:@"Scope is empty" error:error];
  NSMutableArray<NSString *> *effective = [NSMutableArray array];
  for (NSString *part in [scope componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
    if (part.length == 0) continue;
    ATProtoPermissionScope *parsed = [ATProtoPermissionScope scopeWithString:part error:nil];
    if (!parsed || parsed.resourceType != ATProtoPermissionScopeResourceInclude) {
      [effective addObject:part];
      continue;
    }
    NSDictionary *schema = schemas[parsed.permissionSetNSID];
    if (![schema isKindOfClass:[NSDictionary class]]) return [self error:@"Permission set could not be resolved" error:error];
    NSArray *permissions = [self permissionsFromSchema:schema includeAud:parsed.aud error:error];
    if (!permissions) return nil;
    [effective addObjectsFromArray:permissions];
  }
  return [effective componentsJoinedByString:@" "];
}

+ (nullable NSString *)effectiveScopeForScope:(NSString *)scope
                                configuration:(ATProtoServiceConfiguration *)configuration
                                        error:(NSError **)error {
  NSMutableDictionary<NSString *, NSDictionary *> *schemas = [NSMutableDictionary dictionary];
  for (NSString *part in [scope componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
    ATProtoPermissionScope *parsed = [ATProtoPermissionScope scopeWithString:part error:nil];
    if (!parsed || parsed.resourceType != ATProtoPermissionScopeResourceInclude || schemas[parsed.permissionSetNSID]) continue;
    /* Keep the security parser independent of the XRPC target. The resolver is
       present in every server runtime, but calling it dynamically avoids a
       Core -> XRPC static-library dependency cycle. */
    NSDictionary *cached = nil;
    @synchronized(self) {
      cached = [[self schemaCache][parsed.permissionSetNSID] copy];
    }
    NSDate *cachedAt = cached[@"cachedAt"];
    NSDictionary *cachedSchema = cached[@"schema"];
    NSTimeInterval cacheAge = cachedAt ? -[cachedAt timeIntervalSinceNow] : DBL_MAX;
    if ([cachedSchema isKindOfClass:[NSDictionary class]] && cacheAge <= 24 * 60 * 60) {
      schemas[parsed.permissionSetNSID] = cachedSchema;
      continue;
    }

    Class resolverClass = NSClassFromString(@"XrpcLexiconResolver");
    SEL selector = @selector(resolveLexiconResponseForNSID:configuration:error:);
    if (!resolverClass || ![resolverClass respondsToSelector:selector]) {
      return [self error:@"Permission-set resolver is unavailable" error:error];
    }
    typedef NSDictionary *(*ResolveIMP)(id, SEL, NSString *, ATProtoServiceConfiguration *, NSError **);
    ResolveIMP resolve = (ResolveIMP)[resolverClass methodForSelector:selector];
    NSError *resolveError = nil;
    NSDictionary *response = resolve(resolverClass, selector, parsed.permissionSetNSID, configuration, &resolveError);
    NSDictionary *schema = response[@"schema"];
    if (![schema isKindOfClass:[NSDictionary class]]) {
      /* A resolution failure can use a recently verified schema, but never an
         unbounded stale grant. The underlying XRPC resolver also persists
         fetched Lexicons across process restarts. */
      if ([cachedSchema isKindOfClass:[NSDictionary class]] && cacheAge <= 90 * 24 * 60 * 60) {
        schemas[parsed.permissionSetNSID] = cachedSchema;
        continue;
      }
      if (error) *error = resolveError;
      return [self error:@"Permission set could not be resolved" error:error];
    }
    schemas[parsed.permissionSetNSID] = schema;
    @synchronized(self) {
      [self schemaCache][parsed.permissionSetNSID] = @{ @"schema" : schema, @"cachedAt" : [NSDate date] };
    }
  }
  return [self effectiveScopeForScope:scope permissionSetSchemas:schemas error:error];
}

@end
