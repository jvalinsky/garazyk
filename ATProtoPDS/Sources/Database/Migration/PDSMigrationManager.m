#import "PDSMigrationManager.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/ActorStore/ActorStore.h"
#import "Debug/PDSLogger.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import <sqlite3.h>

NSString * const PDSMigrationErrorDomain = @"com.atproto.pds.migration";

@implementation PDSMigrationManager

+ (instancetype)sharedManager {
    static PDSMigrationManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSMigrationManager alloc] init];
    });
    return shared;
}

- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath 
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                  error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:sourcePath]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:PDSMigrationErrorSourceNotFound
                                    userInfo:@{NSLocalizedDescriptionKey: @"Source database not found"}];
        }
        return NO;
    }
    
    [self updateProgress:0 status:@"Opening source database"];
    
    sqlite3 *sourceDb;
    int result = sqlite3_open(sourcePath.UTF8String, &sourceDb);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to open source database"}];
        }
        return NO;
    }
    
    PDSDatabasePool *destinationPool = [[PDSDatabasePool alloc] initWithDbDirectory:destinationDirectory maxSize:30000];
    PDSServiceDatabases *serviceDb = [[PDSServiceDatabases alloc] initWithDirectory:destinationDirectory 
                                                                       serviceMaxSize:100 
                                                                     didCacheMaxSize:1000 
                                                                   sequencerMaxSize:100];
    
    NSMutableArray<NSString *> *accountDids = [NSMutableArray array];
    NSInteger totalAccounts = 0;
    NSInteger totalRepos = 0;
    NSInteger totalRecords = 0;
    NSInteger totalBlocks = 0;
    
    [self updateProgress:0.05 status:@"Counting records to migrate"];
    
    [self updateProgress:0.05 status:@"Counting records to migrate"];
    
    {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
        sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM accounts", -1, &countStmt, NULL);
        if (sqlite3_step(countStmt) == SQLITE_ROW) {
            totalAccounts = sqlite3_column_int64(countStmt, 0);
        }
    }
    
    {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
        sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM repos", -1, &countStmt, NULL);
        if (sqlite3_step(countStmt) == SQLITE_ROW) {
            totalRepos = sqlite3_column_int64(countStmt, 0);
        }
    }
    
    {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
        sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM records", -1, &countStmt, NULL);
        if (sqlite3_step(countStmt) == SQLITE_ROW) {
            totalRecords = sqlite3_column_int64(countStmt, 0);
        }
    }
    
    {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
        sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM blocks", -1, &countStmt, NULL);
        if (sqlite3_step(countStmt) == SQLITE_ROW) {
            totalBlocks = sqlite3_column_int64(countStmt, 0);
        }
    }
    
    NSInteger totalItems = totalAccounts + totalRepos + totalRecords + totalBlocks;
    NSInteger migratedItems = 0;
    
    [self updateProgress:0.1 status:@"Migrating accounts"];
    
    // Collect all accounts for batch processing
    NSMutableArray<PDSDatabaseAccount *> *allAccounts = [NSMutableArray array];
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *accountStmt;
    sqlite3_prepare_v2(sourceDb,
        "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at, updated_at "
        "FROM accounts", -1, &accountStmt, NULL);

    while (sqlite3_step(accountStmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 1)];

        int col = 2;
        if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
            account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, col)];
        }
        col++;

        if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
            account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                                  length:sqlite3_column_bytes(accountStmt, col)];
        }
        col++;

        if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
            account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                                  length:sqlite3_column_bytes(accountStmt, col)];
        }
        col++;

        if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
            account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                               length:sqlite3_column_bytes(accountStmt, col)];
        }
        col++;

        if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
            account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                                length:sqlite3_column_bytes(accountStmt, col)];
        }
        col++;

        account.createdAt = sqlite3_column_double(accountStmt, col);
        col++;
        account.updatedAt = sqlite3_column_double(accountStmt, col);

        [allAccounts addObject:account];
        [accountDids addObject:account.did];
    }

    // Create accounts in batches for better performance
    const NSUInteger batchSize = 100;
    for (NSUInteger i = 0; i < allAccounts.count; i += batchSize) {
        if (self.cancelBlock && self.cancelBlock()) {
            sqlite3_close(sourceDb);
            if (error) {
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                            code:PDSMigrationErrorCancelled
                                        userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
            }
            return NO;
        }

        NSUInteger endIndex = MIN(i + batchSize, allAccounts.count);
        NSArray<PDSDatabaseAccount *> *batch = [allAccounts subarrayWithRange:NSMakeRange(i, endIndex - i)];

        NSError *createError = nil;
        BOOL batchSuccess = [serviceDb createAccounts:batch error:&createError];
        if (!batchSuccess) {
            PDS_LOG_DB_ERROR(@"Migration failed to create account batch starting at index %lu: %@",
                             (unsigned long)i, createError);
        }

        migratedItems += batch.count;
        [self updateProgress:(0.1 + 0.3 * ((double)migratedItems / totalItems))
                      status:[NSString stringWithFormat:@"Migrating accounts (%ld/%ld)", (long)migratedItems, (long)totalAccounts]];
    }
    
    [self updateProgress:0.4 status:@"Migrating repos and records"];
    
    for (NSInteger i = 0; i < accountDids.count; i++) {
        NSString *did = accountDids[i];
        
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *repoStmt;
        sqlite3_prepare_v2(sourceDb, 
            "SELECT owner_did, root_cid, collection_data, created_at, updated_at FROM repos WHERE owner_did = ?",
            -1, &repoStmt, NULL);
        sqlite3_bind_text(repoStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        PDSDatabaseRepo *repo = nil;
        if (sqlite3_step(repoStmt) == SQLITE_ROW) {
            repo = [[PDSDatabaseRepo alloc] init];
            repo.ownerDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(repoStmt, 0)];
            
            if (sqlite3_column_type(repoStmt, 1) != SQLITE_NULL) {
                repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(repoStmt, 1) 
                                              length:sqlite3_column_bytes(repoStmt, 1)];
            }
            
            if (sqlite3_column_type(repoStmt, 2) != SQLITE_NULL) {
                repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(repoStmt, 2) 
                                                     length:sqlite3_column_bytes(repoStmt, 2)];
            }
            
            repo.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(repoStmt, 3)];
            repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(repoStmt, 4)];
        }
        
        __block NSError *repoError = nil;
        if (repo) {
            [destinationPool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
                PDSActorStore *store = (PDSActorStore *)transactor;
                [store createRepo:repo error:&repoError];
            } error:&repoError];
        }
        
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *recordStmt;
        sqlite3_prepare_v2(sourceDb, 
            "SELECT uri, did, collection, rkey, cid, created_at FROM records WHERE did = ?",
            -1, &recordStmt, NULL);
        sqlite3_bind_text(recordStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(recordStmt) == SQLITE_ROW) {
            PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
            record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 0)];
            record.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 1)];
            record.collection = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 2)];
            record.rkey = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 3)];
            record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(recordStmt, 4)];
            record.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(recordStmt, 5)];
            
            __block NSError *recordError = nil;
            [destinationPool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
                PDSActorStore *store = (PDSActorStore *)transactor;
                [store putRecord:record forDid:did error:&recordError];
            } error:&recordError];
        }
        
        migratedItems++;
        double progress = 0.4 + 0.3 * ((double)i / accountDids.count);
        [self updateProgress:progress 
                      status:[NSString stringWithFormat:@"Migrating repos (%ld/%ld)", (long)(i + 1), (long)accountDids.count]];
    }
    
    [self updateProgress:0.7 status:@"Migrating blocks"];
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *blockStmt;
    sqlite3_prepare_v2(sourceDb, 
        "SELECT cid, repo_did, block_data, content_type, size, created_at FROM blocks",
        -1, &blockStmt, NULL);
    
    NSInteger blockIndex = 0;
    while (sqlite3_step(blockStmt) == SQLITE_ROW) {
        if (self.cancelBlock && self.cancelBlock()) {
            sqlite3_close(sourceDb);
            if (error) {
                *error = [NSError errorWithDomain:PDSMigrationErrorDomain
                                            code:PDSMigrationErrorCancelled
                                        userInfo:@{NSLocalizedDescriptionKey: @"Migration cancelled"}];
            }
            return NO;
        }
        
        NSData *cid = [NSData dataWithBytes:sqlite3_column_blob(blockStmt, 0) 
                                     length:sqlite3_column_bytes(blockStmt, 0)];
        NSString *repoDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(blockStmt, 1)];
        
        PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
        block.cid = cid;
        block.repoDid = repoDid;
        
        if (sqlite3_column_type(blockStmt, 2) != SQLITE_NULL) {
            block.blockData = [NSData dataWithBytes:sqlite3_column_blob(blockStmt, 2) 
                                             length:sqlite3_column_bytes(blockStmt, 2)];
        }
        
        if (sqlite3_column_type(blockStmt, 3) != SQLITE_NULL) {
            block.contentType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(blockStmt, 3)];
        }
        
        block.size = sqlite3_column_int64(blockStmt, 4);
        block.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(blockStmt, 5)];
        
        __block NSError *blockError = nil;
        [destinationPool transactWithDid:repoDid block:^(id<PDSActorStoreTransactor> transactor) {
            PDSActorStore *store = (PDSActorStore *)transactor;
            [store putBlock:block forDid:repoDid error:&blockError];
        } error:&blockError];
        
        blockIndex++;
        if (blockIndex % 100 == 0) {
            double progress = 0.7 + 0.3 * ((double)blockIndex / totalBlocks);
            [self updateProgress:progress 
                          status:[NSString stringWithFormat:@"Migrating blocks (%ld/%ld)", (long)blockIndex, (long)totalBlocks]];
        }
    }
    
    [self updateProgress:0.95 status:@"Finalizing migration"];
    
    sqlite3_close(sourceDb);
    
    [self updateProgress:1.0 status:@"Migration complete"];
    
    return YES;
}

- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath 
                        toSingleTenantDirectory:(NSString *)destinationDirectory
                                completion:(void (^)(NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [self migrateFromMonolithicDatabase:sourcePath 
                        toSingleTenantDirectory:destinationDirectory 
                                      error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    });
}

- (NSUInteger)estimatedMigrateTimeWithSourcePath:(NSString *)sourcePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:sourcePath error:nil];
    NSUInteger fileSize = [attrs[NSFileSize] unsignedIntegerValue];
    
    NSUInteger estimatedSeconds = fileSize / (1024 * 1024);
    return estimatedSeconds;
}

- (void)updateProgress:(double)progress status:(NSString *)status {
    if (self.progressBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(progress, status);
        });
    }
}

@end
