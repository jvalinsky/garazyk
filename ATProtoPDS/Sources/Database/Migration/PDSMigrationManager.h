/*!
 @file PDSMigrationManager.h

 @abstract Database migration manager for schema upgrades.

 @discussion Handles migration from monolithic multi-tenant database to
 single-tenant per-user SQLite databases. Supports progress tracking
 and cancellation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@class PDSDatabaseBlob;
@class PDSActorStore;

/*! Error domain for migration operations. */
extern NSString * const PDSMigrationErrorDomain;

/*!
 @enum PDSMigrationError

 @abstract Error codes for migration operations.

 @constant PDSMigrationErrorSourceNotFound Source database not found.
 @constant PDSMigrationErrorDestinationExists Destination already exists.
 @constant PDSMigrationErrorMigrationFailed Migration failed.
 @constant PDSMigrationErrorCancelled Migration was cancelled.
 */
typedef NS_ENUM(NSInteger, PDSMigrationError) {
    PDSMigrationErrorSourceNotFound = 1000,
    PDSMigrationErrorDestinationExists,
    PDSMigrationErrorMigrationFailed,
    PDSMigrationErrorCancelled,
};

/*! Progress callback block (0.0-1.0 progress, status string). */
typedef void (^PDSMigrationProgressBlock)(double progress, NSString *status);

/*! Cancellation check block (return YES to cancel). */
typedef BOOL (^PDSMigrationCancellationBlock)(void);

/*!
 @class PDSMigrationManager

 @abstract Manages database schema migrations.
 */
@interface PDSMigrationManager : NSObject

/*! Block called to report progress. */
@property (nonatomic, copy, nullable) PDSMigrationProgressBlock progressBlock;

/*! Block called to check for cancellation. */
@property (nonatomic, copy, nullable) PDSMigrationCancellationBlock cancelBlock;

/*! Returns the shared migration manager. */
+ (instancetype)sharedManager;

/*! Migrates from monolithic database (synchronous). */
- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath 
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                  error:(NSError **)error;

/*! Migrates from monolithic database (asynchronous). */
- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath 
                        toSingleTenantDirectory:(NSString *)destinationDirectory
                                completion:(void (^)(NSError * _Nullable error))completion;

/*! Estimates migration time in seconds. */
- (NSUInteger)estimatedMigrateTimeWithSourcePath:(NSString *)sourcePath;

@end

NS_ASSUME_NONNULL_END
