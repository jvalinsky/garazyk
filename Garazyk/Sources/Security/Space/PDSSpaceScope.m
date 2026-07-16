// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceScope.h"

#import "Core/ATProtoValidator.h"
#import "Security/GZInputValidator.h"
#import "Security/Space/PDSSpaceURI.h"

NSString *const PDSSpaceScopeErrorDomain = @"com.garazyk.space.scope";
NSString *const PDSSpaceActionReadSelf = @"read_self";
NSString *const PDSSpaceActionRead = @"read";
NSString *const PDSSpaceActionCreate = @"create";
NSString *const PDSSpaceActionUpdate = @"update";
NSString *const PDSSpaceActionDelete = @"delete";

static NSArray<NSString *> *PDSSpaceActionOrder(void) {
  return @[PDSSpaceActionReadSelf, PDSSpaceActionRead, PDSSpaceActionCreate,
           PDSSpaceActionUpdate, PDSSpaceActionDelete];
}

static NSArray<NSString *> *PDSSpaceManageOrder(void) {
  return @[@"create", @"update", @"delete"];
}

static BOOL PDSSpaceScopeIsValidSkey(NSString *value) {
  return value.length > 0 && value.length <= 512;
}

static NSString *PDSSpaceScopeDecodeQueryComponent(NSString *value) {
  NSString *plusDecoded = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
  return [plusDecoded stringByRemovingPercentEncoding];
}

@interface PDSSpaceScope ()
@property(nonatomic, readwrite, copy) NSString *spaceType;
@property(nonatomic, readwrite, copy) NSString *authority;
@property(nonatomic, readwrite, copy) NSString *skey;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *collections;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *actions;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *manageOperations;
@end

@implementation PDSSpaceScope

+ (instancetype)scopeWithString:(NSString *)scope error:(NSError **)error {
  if (![scope isKindOfClass:[NSString class]] || ![scope hasPrefix:@"space:"] ||
      [scope rangeOfString:@"#"].location != NSNotFound ||
      [scope rangeOfString:@" "].location != NSNotFound) {
    return [self invalidSyntax:@"Not a single space: OAuth scope" error:error];
  }

  NSString *body = [scope substringFromIndex:6];
  NSRange queryMarker = [body rangeOfString:@"?"];
  NSString *encodedType = queryMarker.location == NSNotFound
      ? body
      : [body substringToIndex:queryMarker.location];
  NSString *type = [encodedType stringByRemovingPercentEncoding];
  if (type == nil || type.length == 0) {
    return [self invalidSyntax:@"Malformed space scope query" error:error];
  }
  if (![type isEqualToString:@"*"] && ![ATProtoValidator validateNSID:type error:nil]) {
    return [self invalidValue:@"space type must be an NSID or wildcard" error:error];
  }

  NSString *authority = @"self";
  NSString *skey = @"*";
  NSMutableArray<NSString *> *collections = [NSMutableArray array];
  NSMutableArray<NSString *> *actions = [NSMutableArray array];
  NSMutableArray<NSString *> *manage = [NSMutableArray array];
  NSMutableSet<NSString *> *singleParameters = [NSMutableSet set];

  if (queryMarker.location != NSNotFound) {
    NSString *query = [body substringFromIndex:NSMaxRange(queryMarker)];
    if (query.length == 0) {
      return [self invalidSyntax:@"A trailing scope query is invalid" error:error];
    }
    for (NSString *entry in [query componentsSeparatedByString:@"&"]) {
      if (entry.length == 0) {
        continue;
      }
      NSRange equals = [entry rangeOfString:@"="];
      if (equals.location == NSNotFound) {
        return [self invalidSyntax:@"Every scope parameter must have a name and value" error:error];
      }
      NSString *name = PDSSpaceScopeDecodeQueryComponent([entry substringToIndex:equals.location]);
      NSString *encodedValue = [entry substringFromIndex:NSMaxRange(equals)];
      NSString *value = PDSSpaceScopeDecodeQueryComponent(encodedValue);
      if (name == nil || name.length == 0 || value == nil) {
        return [self invalidSyntax:@"Invalid percent encoding in scope" error:error];
      }

      if ([name isEqualToString:@"authority"] || [name isEqualToString:@"skey"]) {
        if ([singleParameters containsObject:name]) {
          return [self invalidSyntax:@"Scope parameter may occur only once" error:error];
        }
        [singleParameters addObject:name];
      }

      if ([name isEqualToString:@"authority"]) {
        if (!([value isEqualToString:@"*"] || [value isEqualToString:@"self"] ||
              [ATProtoValidator validateDID:value error:nil])) {
          return [self invalidValue:@"Invalid authority selector" error:error];
        }
        authority = value;
      } else if ([name isEqualToString:@"skey"]) {
        if (!([value isEqualToString:@"*"] ||
              PDSSpaceScopeIsValidSkey(value))) {
          return [self invalidValue:@"Invalid space key selector" error:error];
        }
        skey = value;
      } else if ([name isEqualToString:@"collection"]) {
        if (!([value isEqualToString:@"*"] || [ATProtoValidator validateNSID:value error:nil])) {
          return [self invalidValue:@"Invalid collection selector" error:error];
        }
        [collections addObject:value];
      } else if ([name isEqualToString:@"action"]) {
        if (![PDSSpaceActionOrder() containsObject:value]) {
          return [self invalidValue:@"Invalid space action" error:error];
        }
        [actions addObject:value];
      } else if ([name isEqualToString:@"manage"]) {
        if (![PDSSpaceManageOrder() containsObject:value]) {
          return [self invalidValue:@"Invalid space management action" error:error];
        }
        [manage addObject:value];
      } else {
        return [self invalidSyntax:@"Unknown space scope parameter" error:error];
      }
    }
  }

  if ([collections containsObject:@"*"]) {
    collections = [NSMutableArray arrayWithObject:@"*"];
  } else {
    collections = [[[NSSet setWithArray:collections] allObjects] mutableCopy];
    [collections sortUsingSelector:@selector(compare:)];
  }
  actions = [self orderedDistinctValues:actions order:PDSSpaceActionOrder()];
  manage = [self orderedDistinctValues:manage order:PDSSpaceManageOrder()];
  if (actions.count == 0) {
    actions = [@[PDSSpaceActionRead, PDSSpaceActionCreate, PDSSpaceActionUpdate,
                 PDSSpaceActionDelete] mutableCopy];
  }

  PDSSpaceScope *result = [[self alloc] init];
  result.spaceType = type;
  result.authority = authority;
  result.skey = skey;
  result.collections = collections;
  result.actions = actions;
  result.manageOperations = manage;
  return result;
}

+ (NSMutableArray<NSString *> *)orderedDistinctValues:(NSArray<NSString *> *)values
                                                 order:(NSArray<NSString *> *)order {
  NSSet<NSString *> *set = [NSSet setWithArray:values];
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  for (NSString *value in order) {
    if ([set containsObject:value]) {
      [result addObject:value];
    }
  }
  return result;
}

- (instancetype)scopeByResolvingSelfAuthorityForDID:(NSString *)did {
  if (![self.authority isEqualToString:@"self"]) {
    return self;
  }
  if (![ATProtoValidator validateDID:did error:nil]) {
    return nil;
  }
  PDSSpaceScope *result = [[PDSSpaceScope alloc] init];
  result.spaceType = self.spaceType;
  result.authority = did;
  result.skey = self.skey;
  result.collections = self.collections;
  result.actions = self.actions;
  result.manageOperations = self.manageOperations;
  return result;
}

- (BOOL)matchesSpace:(PDSSpaceURI *)space
              action:(NSString *)action
          collection:(NSString *)collection {
  if (![self tupleMatchesSpace:space]) {
    return NO;
  }
  if ([action isEqualToString:PDSSpaceActionRead]) {
    return [self.actions containsObject:PDSSpaceActionRead];
  }
  if ([action isEqualToString:PDSSpaceActionReadSelf]) {
    if ([self.actions containsObject:PDSSpaceActionRead]) {
      return YES;
    }
    return [self.actions containsObject:PDSSpaceActionReadSelf] &&
           [self collectionAllows:collection];
  }
  if (!([action isEqualToString:PDSSpaceActionCreate] ||
        [action isEqualToString:PDSSpaceActionUpdate] ||
        [action isEqualToString:PDSSpaceActionDelete])) {
    return NO;
  }
  return [self.actions containsObject:action] && [self collectionAllows:collection];
}

- (BOOL)matchesSpace:(PDSSpaceURI *)space manageOperation:(NSString *)manageOperation {
  return [self tupleMatchesSpace:space] &&
         [self.manageOperations containsObject:manageOperation];
}

- (BOOL)tupleMatchesSpace:(PDSSpaceURI *)space {
  return space != nil &&
         ([self.spaceType isEqualToString:@"*"] || [self.spaceType isEqualToString:space.spaceType]) &&
         ![self.authority isEqualToString:@"self"] &&
         ([self.authority isEqualToString:@"*"] || [self.authority isEqualToString:space.authorityDID]) &&
         ([self.skey isEqualToString:@"*"] || [self.skey isEqualToString:space.skey]);
}

- (BOOL)collectionAllows:(NSString *)collection {
  return collection.length > 0 &&
         ([self.collections containsObject:@"*"] || [self.collections containsObject:collection]);
}

+ (instancetype)invalidSyntax:(NSString *)message error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:PDSSpaceScopeErrorDomain
                                 code:PDSSpaceScopeErrorInvalidSyntax
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
  return nil;
}

+ (instancetype)invalidValue:(NSString *)message error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:PDSSpaceScopeErrorDomain
                                 code:PDSSpaceScopeErrorInvalidValue
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
  return nil;
}

@end
