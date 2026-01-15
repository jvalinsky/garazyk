#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @function pds_sqlite_finalize_wrapper
 
 @abstract Cleanup function for PDS_SQLITE_AUTORELEASE_STMT.
 
 @discussion safe to call on NULL. Finalizes the statement and sets the pointer to NULL.
 */
static inline void pds_sqlite_finalize_wrapper(sqlite3_stmt * _Nullable * _Nonnull stmt) {
    if (*stmt) {
        sqlite3_finalize(*stmt);
        *stmt = NULL;
    }
}

/*!
 @macro PDS_SQLITE_AUTORELEASE_STMT
 
 @abstract Declares a sqlite3_stmt* that is automatically finalized when it goes out of scope.
 
 @discussion
 Usage:
 PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
 sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
 // ... use stmt ...
 // stmt is automatically finalized here
 */
#define PDS_SQLITE_AUTORELEASE_STMT __attribute__((cleanup(pds_sqlite_finalize_wrapper)))

NS_ASSUME_NONNULL_END
