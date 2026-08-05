// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Services/PDS/PDSRASLResolver.h"
#import "Core/CID.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabaseAccount.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSBlobService.h"

@interface PDSRASLResolver ()
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSBlobService *blobService;
@property (nonatomic, strong) id<PDSAccountService> accountService;
@end

@implementation PDSRASLResolver

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool
                          blobService:(PDSBlobService *)blobService
                        accountService:(id<PDSAccountService>)accountService {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
        _blobService = blobService;
        _accountService = accountService;
    }
    return self;
}

- (nullable NSData *)dataForCID:(ATProtoCID *)cid maxAccountsToScan:(NSUInteger)maxAccountsToScan {
    if (!cid) {
        return nil;
    }
    NSData *cidBytes = [cid bytes];
    if (cidBytes.length == 0) {
        return nil;
    }

    NSArray<PDSDatabaseAccount *> *accounts = [self.accountService getAllAccountsWithError:nil];
    if (accounts.count == 0) {
        return nil;
    }

    NSUInteger scanLimit = MIN(accounts.count, maxAccountsToScan);
    for (NSUInteger i = 0; i < scanLimit; i++) {
        NSString *did = accounts[i].did;
        if (did.length == 0) {
            continue;
        }

        PDSActorStore *store = [self.databasePool storeForDid:did error:nil];
        if (store) {
            NSData *blockData = [store getBlockForCID:cidBytes forDid:did error:nil];
            if (blockData.length > 0) {
                return blockData;
            }
        }

        NSData *blobData = [self.blobService getBlob:cidBytes forDid:did error:nil];
        if (blobData.length > 0) {
            return blobData;
        }
    }

    return nil;
}

@end
