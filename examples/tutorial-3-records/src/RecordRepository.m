#import "RecordRepository.h"
#import <sqlite3.h>

@interface RecordRepository ()
@property (nonatomic, assign) sqlite3 *database;
@end

@implementation RecordRepository

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [path stringByAppendingPathComponent:@"records.db"];
    int rc = sqlite3_open([dbPath UTF8String], &_database);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_database));
        return nil;
    }
    
    [self createTablesIfNeeded];
    
    return self;
}

- (void)createTablesIfNeeded {
    const char *sql = "CREATE TABLE IF NOT EXISTS records ("
        "uri TEXT PRIMARY KEY,"
        "did TEXT NOT NULL,"
        "collection TEXT NOT NULL,"
        "rkey TEXT NOT NULL,"
        "cid TEXT NOT NULL,"
        "value TEXT NOT NULL,"
        "created_at REAL NOT NULL,"
        "UNIQUE(did, collection, rkey)"
        ");";
    
    char *errMsg = NULL;
    int rc = sqlite3_exec(_database, sql, NULL, NULL, &errMsg);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

- (BOOL)saveRecord:(Record *)record forDid:(NSString *)did error:(NSError **)error {
    NSArray *parts = [record.uri componentsSeparatedByString:@"/"];
    if (parts.count < 4) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid URI format"}];
        }
        return NO;
    }
    
    NSString *collection = parts[parts.count - 2];
    NSString *rkey = parts[parts.count - 1];
    
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:record.value options:0 error:error];
    if (!valueData) return NO;
    
    NSString *valueJson = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    
    const char *sql = "INSERT OR REPLACE INTO records "
        "(uri, did, collection, rkey, cid, value, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [record.uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, [rkey UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, [record.cid UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, [valueJson UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 7, record.createdAt);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (nullable Record *)getRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    Record *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
    }
    
    sqlite3_finalize(stmt);
    return record;
}

- (nullable NSArray<Record *> *)listRecords:(NSString *)collection 
                                     forDid:(NSString *)did 
                                      limit:(NSUInteger)limit 
                                      error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records "
        "WHERE did = ? AND collection = ? ORDER BY created_at DESC LIMIT ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, limit);
    
    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Record *record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
        [records addObject:record];
    }
    
    sqlite3_finalize(stmt);
    return records;
}

- (BOOL)deleteRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "DELETE FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
