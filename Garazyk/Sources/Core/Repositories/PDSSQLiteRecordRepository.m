#import "PDSSQLiteRecordRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <sqlite3.h>

@implementation PDSSQLiteRecordRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSRecordRepository

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:record.did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, created_at, rev, subject_did) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, record.uri.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, record.did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, record.collection.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, record.rkey.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, record.cid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 6, record.value.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 7, record.createdAt.timeIntervalSince1970);
        sqlite3_bind_text(stmt, 8, record.rev.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 9, record.subjectDid.UTF8String, -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable PDSDatabaseRecord *)recordForUri:(NSString *)uri error:(NSError **)error {
    // Parse AT-URI manually: at://did/collection/rkey
    // NSURL doesn't recognize "at://" as a valid scheme, so url.host returns nil
    if (![uri hasPrefix:@"at://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSSQLiteRecordRepository" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT-URI: missing at:// prefix"}];
        }
        return nil;
    }
    NSString *path = [uri substringFromIndex:5];  // Skip "at://"
    NSRange slashRange = [path rangeOfString:@"/"];
    NSString *did = slashRange.location == NSNotFound ? path : [path substringToIndex:slashRange.location];
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSSQLiteRecordRepository" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT-URI: missing DID"}];
        }
        return nil;
    }

    __block PDSDatabaseRecord *record = nil;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM records WHERE uri = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            record = [self recordFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return record;
}

- (nullable NSArray<PDSDatabaseRecord *> *)recordsForDid:(NSString *)did 
                                             collection:(nullable NSString *)collection 
                                                  error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = collection ? @"SELECT * FROM records WHERE did = ? AND collection = ?" : @"SELECT * FROM records WHERE did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (collection) {
            sqlite3_bind_text(stmt, 2, collection.UTF8String, -1, SQLITE_TRANSIENT);
        }

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseRecord *record = [self recordFromStatement:stmt];
            if (record) [records addObject:record];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return [records copy];
}

- (BOOL)deleteRecord:(NSString *)uri error:(NSError **)error {
    // Parse AT-URI manually: at://did/collection/rkey
    // NSURL doesn't recognize "at://" as a valid scheme, so url.host returns nil
    if (![uri hasPrefix:@"at://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSSQLiteRecordRepository"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT-URI: missing at:// prefix"}];
        }
        return NO;
    }
    NSString *path = [uri substringFromIndex:5];  // Skip "at://"
    NSRange slashRange = [path rangeOfString:@"/"];
    NSString *did = slashRange.location == NSNotFound ? path : [path substringToIndex:slashRange.location];
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSSQLiteRecordRepository"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT-URI: missing DID"}];
        }
        return NO;
    }

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        if (!store) return;
        
        NSString *sql = @"DELETE FROM records WHERE uri = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = sqlite3_changes(store.db) > 0;
        }
        [store finalizeStatement:stmt];
    } error:error];
    
    return success;
}

- (nullable PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = @((const char *)sqlite3_column_text(stmt, 0));
    record.did = @((const char *)sqlite3_column_text(stmt, 1));
    record.collection = @((const char *)sqlite3_column_text(stmt, 2));
    record.rkey = @((const char *)sqlite3_column_text(stmt, 3));
    record.cid = @((const char *)sqlite3_column_text(stmt, 4));
    record.value = @((const char *)sqlite3_column_text(stmt, 5));
    
    const char *subjectDidText = (const char *)sqlite3_column_text(stmt, 6);
    if (subjectDidText) {
        record.subjectDid = @(subjectDidText);
    }
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 7);
    if (createdAtText) {
        record.createdAt = [NSDateFormatter atproto_dateFromString:@(createdAtText)];
    }
    
    return record;
}

@end
