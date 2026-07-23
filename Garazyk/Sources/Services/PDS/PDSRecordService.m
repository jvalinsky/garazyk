// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService_Internal.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Core/ATProtoBase32.h"
#import "Core/GZPerDidWriteDispatcher.h"
#import "Core/MSTCacheManager.h"
#import "Core/Repositories/PDSSQLiteRecordRepository.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import <CommonCrypto/CommonDigest.h>

#import "PDSRecordService+Validation.h"
#import "PDSRecordService+Authorization.h"
#import "PDSRecordService+RecordCRUD.h"
#import "PDSRecordService+BatchWrites.h"
#import "PDSRecordService+CommitPlumbing.h"
#import "PDSRecordService+Stats.h"

@implementation PDSRecordService

#pragma mark - Initialization

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        self.databasePool = databasePool;
        self.recordRepository = [[PDSSQLiteRecordRepository alloc] initWithDatabasePool:databasePool];
        _statsCacheByDid = [NSMutableDictionary dictionary];
        _statsCacheQueue = dispatch_queue_create("com.atproto.pds.recordservice.stats", DISPATCH_QUEUE_SERIAL);
        _writeDispatcher = [[GZPerDidWriteDispatcher alloc] initWithConcurrencyLimit:32
                                                               idleEvictionSeconds:60];
    }
    return self;
}

#pragma mark - Synchronous Write Dispatch

- (void)_dispatchWriteForDid:(NSString *)did block:(void (^)(void))block {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [self.writeDispatcher dispatchWriteForDid:did block:^{
        block();
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
}

#pragma mark - Private Helpers

- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    NSMutableData *cidData = [NSMutableData dataWithCapacity:4 + CC_SHA256_DIGEST_LENGTH];
    const unsigned char prefix[] = {0x01, 0x71, 0x12, 0x20};
    [cidData appendBytes:prefix length:4];
    [cidData appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    NSString *base32 = [ATProtoBase32 encodeData:cidData];
    return [NSString stringWithFormat:@"b%@", base32];
}

@end
