// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Database/Utils/PDSDatabaseUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PDSConnectionManager <NSObject>

@property (nonatomic, readonly, getter=isOpen) BOOL open;
@property (nonatomic, readonly, copy) NSString *databasePath;

- (BOOL)openWithPath:(NSString *)path config:(PDSDBConfig)config error:(NSError **)error;
- (void)close;

- (BOOL)execute:(void(^)(sqlite3 *db))block error:(NSError **)error;
- (BOOL)transact:(void(^)(sqlite3 *db, BOOL *rollback))block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
