// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAObjectLifecycle.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Core/CID.h"
#import "Core/NSDateFormatter+ATProto.h"

NSErrorDomain const ATProtoCAObjectLifecycleErrorDomain = @"com.atproto.ca.lifecycle";

static const NSTimeInterval kATProtoCAObjectLifecycleDefaultGrace = 6 * 60 * 60;
static const NSTimeInterval kATProtoCAObjectLifecycleMinGrace = 60 * 60;

static NSError *CALifeError(ATProtoCAObjectLifecycleErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoCAObjectLifecycleErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void CALifeSetError(NSError **error, ATProtoCAObjectLifecycleErrorCode code, NSString *message) {
    if (error) {
        *error = CALifeError(code, message);
    }
}

@interface ATProtoCAObjectLifecycle ()
@property (nonatomic, strong, readwrite) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong) ATProtoConnectionManagerSerial *connectionManager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *queryRunner;
@end

@implementation ATProtoCAObjectLifecycle

+ (NSTimeInterval)clampedGracePeriodSeconds:(NSTimeInterval)seconds {
    if (seconds < kATProtoCAObjectLifecycleMinGrace) {
        return kATProtoCAObjectLifecycleMinGrace;
    }
    return seconds;
}

- (nullable instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                                       error:(NSError **)error {
    self = [super init];
    if (self) {
        if (![objectStore isKindOfClass:[ATProtoCAObjectStore class]]) {
            CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"objectStore is required");
            return nil;
        }
        _objectStore = objectStore;
        _gracePeriodSeconds = kATProtoCAObjectLifecycleDefaultGrace;
        _sweepEnabled = NO;
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.ca.lifecycle"];

        NSString *dbPath = [objectStore.rootDirectory stringByAppendingPathComponent:@"lifecycle.db"];
        if (![_connectionManager openWithPath:dbPath config:ATProtoDBConfigDefault error:error]) {
            return nil;
        }
        _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                         errorDomain:ATProtoCAObjectLifecycleErrorDomain];
        if (![self createSchemaWithError:error]) {
            [_connectionManager close];
            return nil;
        }
    }
    return self;
}

- (void)setGracePeriodSeconds:(NSTimeInterval)gracePeriodSeconds {
    _gracePeriodSeconds = [ATProtoCAObjectLifecycle clampedGracePeriodSeconds:gracePeriodSeconds];
}

- (NSDate *)currentDate {
    if (self.nowProvider) {
        return self.nowProvider();
    }
    return [NSDate date];
}

- (BOOL)createSchemaWithError:(NSError **)error {
    NSArray<NSString *> *statements = @[
        @"CREATE TABLE IF NOT EXISTS manifests (manifest_cid TEXT PRIMARY KEY, published_at TEXT NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS manifest_refs (manifest_cid TEXT NOT NULL, object_cid TEXT NOT NULL, PRIMARY KEY (manifest_cid, object_cid))",
        @"CREATE TABLE IF NOT EXISTS object_refs (object_cid TEXT PRIMARY KEY, refcount INTEGER NOT NULL, zero_since TEXT)",
        @"CREATE INDEX IF NOT EXISTS idx_manifest_refs_object ON manifest_refs(object_cid)",
        @"CREATE INDEX IF NOT EXISTS idx_object_refs_zero ON object_refs(zero_since)",
    ];
    for (NSString *sql in statements) {
        if ([self.queryRunner executeUpdate:sql params:nil error:error] < 0) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)publishManifestCID:(ATProtoCID *)manifestCID
     referencedObjectCIDs:(NSArray<ATProtoCID *> *)objectCIDs
                    error:(NSError **)error {
    if (![manifestCID isKindOfClass:[ATProtoCID class]]) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"manifestCID is required");
        return NO;
    }
    if (![objectCIDs isKindOfClass:[NSArray class]]) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"referencedObjectCIDs is required");
        return NO;
    }

    NSString *manifestKey = manifestCID.stringValue;
    NSArray *existing = [self.queryRunner executeQuery:@"SELECT manifest_cid FROM manifests WHERE manifest_cid = ?"
                                                params:@[manifestKey]
                                                 error:error];
    if (!existing) {
        return NO;
    }
    if (existing.count > 0) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorAlreadyPublished, @"Manifest already published");
        return NO;
    }

    NSMutableSet<NSString *> *unique = [NSMutableSet set];
    [unique addObject:manifestKey];
    for (ATProtoCID *cid in objectCIDs) {
        if (![cid isKindOfClass:[ATProtoCID class]]) {
            CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"referencedObjectCIDs must contain CIDs");
            return NO;
        }
        [unique addObject:cid.stringValue];
    }

    NSString *now = [NSDateFormatter atproto_stringFromDate:[self currentDate]];
    if ([self.queryRunner executeUpdate:@"INSERT INTO manifests (manifest_cid, published_at) VALUES (?, ?)"
                                 params:@[manifestKey, now]
                                  error:error] < 0) {
        return NO;
    }

    for (NSString *objectKey in unique) {
        if ([self.queryRunner executeUpdate:@"INSERT INTO manifest_refs (manifest_cid, object_cid) VALUES (?, ?)"
                                     params:@[manifestKey, objectKey]
                                      error:error] < 0) {
            return NO;
        }
        if (![self incrementObjectCID:objectKey error:error]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)incrementObjectCID:(NSString *)objectKey error:(NSError **)error {
    NSArray *rows = [self.queryRunner executeQuery:@"SELECT refcount FROM object_refs WHERE object_cid = ?"
                                            params:@[objectKey]
                                             error:error];
    if (!rows) {
        return NO;
    }
    if (rows.count == 0) {
        return [self.queryRunner executeUpdate:@"INSERT INTO object_refs (object_cid, refcount, zero_since) VALUES (?, 1, NULL)"
                                        params:@[objectKey]
                                         error:error] >= 0;
    }
    NSInteger refcount = [rows.firstObject[@"refcount"] integerValue];
    return [self.queryRunner executeUpdate:@"UPDATE object_refs SET refcount = ?, zero_since = NULL WHERE object_cid = ?"
                                    params:@[@(refcount + 1), objectKey]
                                     error:error] >= 0;
}

- (BOOL)retractManifestCID:(ATProtoCID *)manifestCID error:(NSError **)error {
    if (![manifestCID isKindOfClass:[ATProtoCID class]]) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"manifestCID is required");
        return NO;
    }
    NSString *manifestKey = manifestCID.stringValue;
    NSArray *existing = [self.queryRunner executeQuery:@"SELECT manifest_cid FROM manifests WHERE manifest_cid = ?"
                                                params:@[manifestKey]
                                                 error:error];
    if (!existing) {
        return NO;
    }
    if (existing.count == 0) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorNotPublished, @"Manifest is not published");
        return NO;
    }

    NSArray *refs = [self.queryRunner executeQuery:@"SELECT object_cid FROM manifest_refs WHERE manifest_cid = ?"
                                            params:@[manifestKey]
                                             error:error];
    if (!refs) {
        return NO;
    }

    NSString *now = [NSDateFormatter atproto_stringFromDate:[self currentDate]];
    for (NSDictionary *row in refs) {
        NSString *objectKey = row[@"object_cid"];
        if (![self decrementObjectCID:objectKey now:now error:error]) {
            return NO;
        }
    }

    if ([self.queryRunner executeUpdate:@"DELETE FROM manifest_refs WHERE manifest_cid = ?"
                                 params:@[manifestKey]
                                  error:error] < 0) {
        return NO;
    }
    return [self.queryRunner executeUpdate:@"DELETE FROM manifests WHERE manifest_cid = ?"
                                    params:@[manifestKey]
                                     error:error] >= 0;
}

- (BOOL)decrementObjectCID:(NSString *)objectKey now:(NSString *)now error:(NSError **)error {
    NSArray *rows = [self.queryRunner executeQuery:@"SELECT refcount FROM object_refs WHERE object_cid = ?"
                                            params:@[objectKey]
                                             error:error];
    if (!rows || rows.count == 0) {
        return YES;
    }
    NSInteger refcount = [rows.firstObject[@"refcount"] integerValue];
    if (refcount <= 1) {
        return [self.queryRunner executeUpdate:@"UPDATE object_refs SET refcount = 0, zero_since = ? WHERE object_cid = ?"
                                        params:@[now, objectKey]
                                         error:error] >= 0;
    }
    return [self.queryRunner executeUpdate:@"UPDATE object_refs SET refcount = ?, zero_since = NULL WHERE object_cid = ?"
                                    params:@[@(refcount - 1), objectKey]
                                     error:error] >= 0;
}

- (NSInteger)refcountForCID:(ATProtoCID *)cid error:(NSError **)error {
    if (![cid isKindOfClass:[ATProtoCID class]]) {
        CALifeSetError(error, ATProtoCAObjectLifecycleErrorInvalidArgument, @"cid is required");
        return -1;
    }
    NSArray *rows = [self.queryRunner executeQuery:@"SELECT refcount FROM object_refs WHERE object_cid = ?"
                                            params:@[cid.stringValue]
                                             error:error];
    if (!rows) {
        return -1;
    }
    if (rows.count == 0) {
        return 0;
    }
    return [rows.firstObject[@"refcount"] integerValue];
}

- (NSInteger)sweepWithError:(NSError **)error {
    if (!self.sweepEnabled) {
        return 0;
    }

    NSTimeInterval grace = [ATProtoCAObjectLifecycle clampedGracePeriodSeconds:self.gracePeriodSeconds];
    NSDate *cutoff = [[self currentDate] dateByAddingTimeInterval:-grace];
    NSString *cutoffStr = [NSDateFormatter atproto_stringFromDate:cutoff];

    NSArray *candidates =
        [self.queryRunner executeQuery:@"SELECT object_cid FROM object_refs WHERE refcount = 0 AND zero_since IS NOT NULL AND zero_since <= ?"
                                params:@[cutoffStr]
                                 error:error];
    if (!candidates) {
        return -1;
    }

    NSInteger deleted = 0;
    for (NSDictionary *row in candidates) {
        NSString *objectKey = row[@"object_cid"];
        ATProtoCID *cid = [ATProtoCID cidFromString:objectKey];
        if (!cid) {
            continue;
        }
        NSError *deleteError = nil;
        // Object may already be absent; still drop the lifecycle row.
        [self.objectStore deleteCID:cid error:&deleteError];
        if ([self.queryRunner executeUpdate:@"DELETE FROM object_refs WHERE object_cid = ? AND refcount = 0"
                                     params:@[objectKey]
                                      error:error] < 0) {
            return -1;
        }
        deleted += 1;
    }
    return deleted;
}

@end
