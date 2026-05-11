// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabasePoolTestFixture.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"

@interface PDSDatabasePoolTestFixture ()
@property (nonatomic, readwrite, nullable) PDSDatabasePool *pool;
@end

@implementation PDSDatabasePoolTestFixture

- (instancetype)initWithTestName:(NSString *)testName maxPoolSize:(NSUInteger)maxPoolSize {
    self = [super initWithTestName:testName];
    if (self) {
        _maxPoolSize = maxPoolSize;
    }
    return self;
}

- (BOOL)setupPoolWithError:(NSError **)error {
    if (!self.database) {
        if (![self setupDatabaseWithError:error]) {
            return NO;
        }
    }

    // Create pool directory within test directory
    NSString *poolDir = [self.testDirectory stringByAppendingPathComponent:@"pool"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:poolDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:poolDir maxSize:self.maxPoolSize];
    return YES;
}

- (BOOL)teardownPoolWithError:(NSError **)error {
    if (self.pool) {
        [self.pool closeAll];
        self.pool = nil;
    }
    return YES;
}

- (BOOL)testConcurrentPoolAccessWithBlock:(void (^)(PDSActorStore *store, NSError **error))block
                                    error:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *concurrentError = nil;
    __block BOOL success = YES;

    for (NSUInteger i = 0; i < self.maxPoolSize; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                PDSActorStore *store = [self.pool storeForDid:[NSString stringWithFormat:@"did:plc:test%lu", (unsigned long)i] error:&localError];
                if (store) {
                    block(store, &localError);
                }
                if (localError) {
                    @synchronized(self) {
                        if (!concurrentError) {
                            concurrentError = localError;
                        }
                        success = NO;
                    }
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = concurrentError;
    }

    return success;
}

@end
