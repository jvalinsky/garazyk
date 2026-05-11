// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSServiceMigration001.h
 @brief Initial service database migration.

 @discussion Migration 1 establishes schema version tracking infrastructure.
 The main database schema already exists via CREATE IF NOT EXISTS statements,
 so this migration is primarily responsible for creating the schema_version table.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Empty interface - just conforms to PDSDatabaseMigration protocol in implementation
@interface PDSServiceMigration001 : NSObject
@end

NS_ASSUME_NONNULL_END
