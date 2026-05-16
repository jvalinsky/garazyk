// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Database/Utils/ATProtoDatabaseUtilities.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Supplies database connections to storage components.
 */
@protocol ATProtoConnectionManager <NSObject>

@property (nonatomic, readonly, getter=isOpen) BOOL open;
@property (nonatomic, readonly, copy) NSString *databasePath;

- (BOOL)openWithPath:(NSString *)path config:(ATProtoDBConfig)config error:(NSError **)error;
- (void)close;

/**
 * @abstract Execute.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)execute:(void(^)(sqlite3 *db))block error:(NSError **)error;
- (BOOL)transact:(void(^)(sqlite3 *db, BOOL *rollback))block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
