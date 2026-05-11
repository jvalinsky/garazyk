// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSDatabaseMigration.h
 @brief Protocol for database schema migrations.

 @discussion Defines the interface for implementing database migrations.
 Each migration represents a schema version change and is executed
 in version order, with tracking in the schema_version table.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSDatabase;

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSDatabaseMigration

 @abstract Protocol for database schema migrations.

 @discussion Each migration represents a schema version change. Migrations
 are executed in version order and tracked in the schema_version table.
 Implement this protocol to create custom migrations for schema evolution.
 */
@protocol PDSDatabaseMigration <NSObject>

/*! @brief Migration version number (must be unique and sequential). */
@property (nonatomic, readonly) NSInteger version;

/*! @brief Human-readable description of this migration. */
@property (nonatomic, readonly) NSString *description;

/*!
 @method applyToDatabase:error:

 @abstract Execute this migration on the given database.

 @param database Database to migrate.
 @param error Error output parameter.
 @return YES if migration succeeded, NO otherwise.

 @discussion The migration should execute all SQL statements within
 a transaction. If the transaction fails, it will be automatically
 rolled back by the calling code.
 */
- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
