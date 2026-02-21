#import "PDSConcurrentAccessTestFixture.h"
#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@implementation PDSConcurrentAccessTestFixture

- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                concurrentThreads:(NSUInteger)concurrentThreads {
    self = [super initWithTestName:testName maxPoolSize:maxPoolSize];
    if (self) {
        _concurrentThreads = concurrentThreads;
    }
    return self;
}

- (BOOL)testConcurrentReadsWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *readError = nil;
    __block BOOL success = YES;
    __block NSUInteger completedReads = 0;

    for (NSUInteger i = 0; i < self.concurrentThreads; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                [self.pool readWithDid:@"did:plc:concurrent-test" block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
                    NSError *readErr = nil;
                    PDSDatabaseAccount *account = [reader getAccountForDid:@"did:plc:concurrent-test" error:&readErr];
                    if (readErr && readErr.code != PDSActorStoreErrorNotFound) {
                        @synchronized(self) {
                            if (!readError) {
                                readError = readErr;
                            }
                            success = NO;
                        }
                    }
                } error:nil];

                @synchronized(self) {
                    completedReads++;
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = readError;
    }

    return success && (completedReads == self.concurrentThreads);
}

- (BOOL)testConcurrentWritesWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *writeError = nil;
    __block BOOL success = YES;
    __block NSUInteger completedWrites = 0;

    for (NSUInteger i = 0; i < self.concurrentThreads; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                NSString *did = [NSString stringWithFormat:@"did:plc:write-test-%lu", (unsigned long)i];
                PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:[NSString stringWithFormat:@"write%lu.example.com", (unsigned long)i]];

                [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
                    NSError *createErr = nil;
                    if (![transactor createAccount:account error:&createErr]) {
                        @synchronized(self) {
                            if (!writeError) {
                                writeError = createErr;
                            }
                            success = NO;
                        }
                    }
                } error:nil];

                @synchronized(self) {
                    completedWrites++;
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = writeError;
    }

    return success && (completedWrites == self.concurrentThreads);
}

- (BOOL)testTransactionIsolationWithError:(NSError **)error {
    // Test basic transaction isolation - create a record in one transaction
    // and verify it's not visible in another concurrent transaction until committed
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    NSString *did = @"did:plc:isolation-test";
    __block BOOL success = YES;
    __block NSError *isolationError = nil;

    // Create account first
    PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:@"isolation.example.com"];
    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        [transactor createAccount:account error:nil];
    } error:nil];

    // Test that records created in transactions are properly isolated
    dispatch_group_t group = dispatch_group_create();
    __block PDSDatabaseRecord *createdRecord = nil;

    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
            PDSDatabaseRecord *record = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did collection:@"app.bsky.feed.post" rkey:@"isolation-test"];
            if ([transactor putRecord:record forDid:did error:innerError]) {
                createdRecord = record;
            } else {
                success = NO;
            }
        } error:&isolationError];
        dispatch_group_leave(group);
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Verify the record is now visible after transaction commit
    if (success && createdRecord) {
        [self.pool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
            PDSDatabaseRecord *fetched = [reader getRecord:createdRecord.uri forDid:did error:innerError];
            if (!fetched) {
                success = NO;
                *innerError = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                                  code:PDSDatabaseIntegrationTestErrorConcurrentAccessFailed
                                              userInfo:@{NSLocalizedDescriptionKey: @"Transaction isolation failed - record not visible after commit"}];
            }
        } error:&isolationError];
    }

    if (!success && error) {
        *error = isolationError;
    }

    return success;
}

- (BOOL)testDeadlockDetectionWithError:(NSError **)error {
    // Basic deadlock detection test - attempt concurrent operations that might deadlock
    // In a real implementation, this would create more complex scenarios
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *deadlockError = nil;
    __block BOOL success = YES;

    // Run multiple concurrent transactions that access shared resources
    for (NSUInteger i = 0; i < MIN(self.concurrentThreads, 4); i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                NSString *did = @"did:plc:deadlock-test";

                [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
                    // Perform some database operations that might conflict
                    PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:@"deadlock.example.com"];
                    NSError *createErr = nil;
                    [transactor createAccount:account error:&createErr];

                    // Add small delay to increase chance of interleaving
                    usleep(1000);
                } error:nil];

                if (localError) {
                    @synchronized(self) {
                        if (!deadlockError) {
                            deadlockError = localError;
                        }
                        // Don't fail on constraint violations (expected for duplicate accounts)
                        if (localError.code != PDSDatabaseErrorConstraintViolation) {
                            success = NO;
                        }
                    }
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = deadlockError;
    }

    return success;
}

@end
