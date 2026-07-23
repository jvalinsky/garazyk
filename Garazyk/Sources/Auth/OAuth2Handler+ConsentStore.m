// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+ConsentStore.h"

@implementation OAuth2Handler (ConsentStore)

- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle {
  if (did.length == 0) {
    return nil;
  }

  NSString *sessionToken = [[NSUUID UUID] UUIDString];
  NSString *sessionHandle = handle.length > 0 ? handle : did;
  dispatch_sync(sAuthGlobalsQueue, ^{
    [self cleanupExpiredPendingConsentsLocked];
    [self enforcePendingConsentCapacityLocked];
    sPendingConsents[sessionToken] = @{
      @"did" : did,
      @"handle" : sessionHandle,
      @"created" : [NSDate date],
      @"expires" :
          [NSDate dateWithTimeIntervalSinceNow:kPendingConsentTTLSeconds]
    };
  });

  return sessionToken;
}

- (void)cleanupExpiredPendingConsentsLocked {
  if (!sPendingConsents || sPendingConsents.count == 0) {
    return;
  }

  NSDate *now = [NSDate date];
  NSMutableArray<NSString *> *expired = [NSMutableArray array];
  [sPendingConsents
      enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSDictionary *session = (NSDictionary *)obj;
        NSString *sessionKey = (NSString *)key;
        NSDate *expires = session[@"expires"];
        if (![expires isKindOfClass:[NSDate class]] ||
            [expires compare:now] != NSOrderedDescending) {
          [expired addObject:sessionKey];
        }
      }];
  [sPendingConsents removeObjectsForKeys:expired];
}

- (void)enforcePendingConsentCapacityLocked {
  if (sPendingConsents.count < kMaxPendingConsents) {
    return;
  }

  NSArray<NSString *> *sortedKeys = [sPendingConsents
      keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *obj1,
                                                           NSDictionary *obj2) {
        NSDate *created1 = obj1[@"created"] ?: obj1[@"expires"] ?: [NSDate distantPast];
        NSDate *created2 = obj2[@"created"] ?: obj2[@"expires"] ?: [NSDate distantPast];
        return [created1 compare:created2];
      }];

  NSUInteger overflow = (sPendingConsents.count - kMaxPendingConsents) + 1;
  for (NSUInteger i = 0; i < overflow && i < sortedKeys.count; i++) {
    [sPendingConsents removeObjectForKey:sortedKeys[i]];
  }
}

- (NSUInteger)pendingConsentCountForTesting {
  __block NSUInteger count = 0;
  dispatch_sync(sAuthGlobalsQueue, ^{
    [self cleanupExpiredPendingConsentsLocked];
    count = sPendingConsents.count;
  });
  return count;
}

- (void)clearPendingConsentsForTesting {
  dispatch_sync(sAuthGlobalsQueue, ^{
    [sPendingConsents removeAllObjects];
  });
}

@end
