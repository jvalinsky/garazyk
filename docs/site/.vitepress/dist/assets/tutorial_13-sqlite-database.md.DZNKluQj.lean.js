import{C as r,c as E,o as d,ag as h,G as t,j as i,a as l}from"./chunks/framework.EuUYIJ38.js";const c=JSON.parse('{"title":"Chapter 13: SQLite Database Layer","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/13-sqlite-database.md","filePath":"tutorial/13-sqlite-database.md"}'),g={name:"tutorial/13-sqlite-database.md"},C=Object.assign(g,{setup(y){const a=`#import <Foundation/Foundation.h>

// --- Mock SQLite C API ---

typedef void* sqlite3;
typedef void* sqlite3_stmt;
#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_TRANSIENT (void*)-1

// Mock State
static NSString *lastPreparedSQL = nil;
static NSMutableDictionary *currentBindings = nil;

int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail) {
    lastPreparedSQL = @(zSql);
    currentBindings = [NSMutableDictionary dictionary];
    *ppStmt = (void*)123; // Fake pointer
    return SQLITE_OK;
}

int sqlite3_bind_text(sqlite3_stmt* stmt, int idx, const char* val, int len, void(*d)(void*)) {
    if (val) currentBindings[@(idx)] = @(val);
    return SQLITE_OK;
}

int sqlite3_bind_int(sqlite3_stmt* stmt, int idx, int val) {
    currentBindings[@(idx)] = @(val);
    return SQLITE_OK;
}

int sqlite3_step(sqlite3_stmt* stmt) {
    return SQLITE_DONE;
}

int sqlite3_finalize(sqlite3_stmt* stmt) {
    return SQLITE_OK;
}

int sqlite3_changes(sqlite3 *db) {
    return 1; // Simulate 1 row changed
}

// Helper for Mock DB Class
@interface PDSDatabase : NSObject {
    sqlite3 *_db;
}
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
@end

@implementation PDSDatabase
- (instancetype)init { if(self=[super init]) _db = (void*)1; return self; }
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    return stmt;
}
@end
`,k=a+`
// --- EXERCISE 1: Update Handle ---

@implementation PDSDatabase (Exercise1)
- (BOOL)updateHandle:(NSString *)newHandle forDID:(NSString *)did error:(NSError **)error {
    // TODO: Write SQL: "UPDATE accounts SET handle = ? WHERE did = ?"
    // Prepare, Bind (1=handle, 2=did), Step, Finalize
    
    // Example:
    // NSString *sql = @"...";
    // sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    // ...
    // sqlite3_finalize(stmt);
    
    return NO;
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db updateHandle:@"bob.bsky.social" forDID:@"did:plc:123" error:nil];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    printf("Bind 1: %s\\n", [currentBindings[@1] UTF8String]);
    printf("Bind 2: %s\\n", [currentBindings[@2] UTF8String]);
    
    if ([lastPreparedSQL containsString:@"UPDATE accounts"] && 
        [currentBindings[@1] isEqualToString:@"bob.bsky.social"]) {
        printf("PASS: Correct SQL and bindings.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,p=a+`
// --- EXERCISE 2: Block Count ---

@implementation PDSDatabase (Exercise2)
- (NSInteger)blockCountForDID:(NSString *)did {
    // TODO: Select Count ("SELECT COUNT(*) FROM blocks WHERE did = ?")
    // Bind DID to 1
    // Step, if SQLITE_ROW, read column 0 (mocked return 0 for now)
    
    return 0;
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db blockCountForDID:@"did:plc:123"];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    if ([lastPreparedSQL containsString:@"SELECT COUNT(*)"] && 
        [lastPreparedSQL containsString:@"blocks"]) {
        printf("PASS: Correct SQL.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,e=a+`
// --- EXERCISE 3: Pagination ---

@implementation PDSDatabase (Exercise3)
- (void)listRecords:(NSString *)did {
    // TODO: Just write the SQL string for "WHERE rkey > cursor"
    // To simplify: we'll check if your SQL includes cursor logic.
    NSString *sql = @"SELECT * FROM records WHERE did = ? AND collection = ? AND rkey > ? ORDER BY rkey ASC LIMIT ?";
    
    // Call prepare (mocking the check)
    [self prepareStatement:sql error:nil];
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db listRecords:@"did:plc:123"];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    if ([lastPreparedSQL containsString:@"rkey > ?"] && 
        [lastPreparedSQL containsString:@"ORDER BY rkey"]) {
        printf("PASS: Correct pagination clauses.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;return(o,s)=>{const n=r("ObjcRunner");return d(),E("div",null,[s[0]||(s[0]=h("",56)),t(n,{initialCode:k}),s[1]||(s[1]=i("p",null,[l("📝 "),i("strong",null,"Exercise 2: Implement Block Count")],-1)),s[2]||(s[2]=i("p",null,"Write a method to count blocks for a specific DID:",-1)),t(n,{initialCode:p}),s[3]||(s[3]=i("p",null,[l("📝 "),i("strong",null,"Exercise 3: Add Record Listing with Pagination")],-1)),s[4]||(s[4]=i("p",null,"Implement paginated record listing:",-1)),t(n,{initialCode:e}),s[5]||(s[5]=h("",18))])}}});export{c as __pageData,C as default};
