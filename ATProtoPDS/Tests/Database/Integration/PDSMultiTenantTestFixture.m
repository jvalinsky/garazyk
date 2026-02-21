#import "PDSMultiTenantTestFixture.h"
#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@interface PDSMultiTenantTestFixture ()
@property (nonatomic, readwrite) NSArray<NSString *> *testDIDs;
@end

@implementation PDSMultiTenantTestFixture

- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                         testDIDs:(NSArray<NSString *> *)testDIDs {
    self = [super initWithTestName:testName maxPoolSize:maxPoolSize];
    if (self) {
        _testDIDs = [testDIDs copy];
    }
    return self;
}

- (BOOL)setupTenantsWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    // Create test accounts for each tenant DID
    for (NSString *did in self.testDIDs) {
        PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:[NSString stringWithFormat:@"%@.example.com", did.lastPathComponent]];
        __block BOOL createSuccess = YES;
        [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
            NSError *createError = nil;
            if (![transactor createAccount:account error:&createError]) {
                createSuccess = NO;
            }
        } error:error];
        if (!createSuccess) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)verifyTenantIsolationWithError:(NSError **)error {
    if (!self.pool || self.testDIDs.count < 2) {
        return YES; // Need at least 2 tenants to test isolation
    }

    NSString *did1 = self.testDIDs[0];
    NSString *did2 = self.testDIDs[1];

    // Create a record in tenant 1
    PDSDatabaseRecord *record1 = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did1 collection:@"app.bsky.feed.post" rkey:@"isolation-test"];

    __block BOOL success = YES;
    __block NSError *isolationError = nil;

    [self.pool transactWithDid:did1 block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        if (![transactor putRecord:record1 forDid:did1 error:innerError]) {
            success = NO;
        }
    } error:&isolationError];

    if (!success) {
        if (error) *error = isolationError;
        return NO;
    }

    // Try to access the record from tenant 2 - should not be visible
    [self.pool readWithDid:did2 block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        PDSDatabaseRecord *fetched = [reader getRecord:record1.uri forDid:did1 error:innerError];
        if (fetched) {
            success = NO;
            *innerError = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                              code:PDSDatabaseIntegrationTestErrorConcurrentAccessFailed
                                          userInfo:@{NSLocalizedDescriptionKey: @"Tenant isolation breached - record accessible from wrong tenant"}];
        }
    } error:&isolationError];

    if (!success && error) {
        *error = isolationError;
    }

    return success;
}

- (BOOL)createTestDataForTenant:(NSString *)did error:(NSError **)error {
    __block BOOL success = YES;
    __block NSError *dataError = nil;

    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        // Create a test repo
        PDSDatabaseRepo *repo = [PDSDatabaseIntegrationTestUtilities createTestRepoWithOwnerDID:did];
        if (![transactor createRepo:repo error:innerError]) {
            success = NO;
            return;
        }

        // Create a test record
        PDSDatabaseRecord *record = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did collection:@"app.bsky.feed.post" rkey:@"tenant-test"];
        if (![transactor putRecord:record forDid:did error:innerError]) {
            success = NO;
            return;
        }

        // Create a test block
        PDSDatabaseBlock *block = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:did];
        if (![transactor putBlock:block forDid:did error:&dataError]) {
            success = NO;
        }
    } error:&dataError];

    if (!success && error) {
        *error = dataError;
    }

    return success;
}

@end
