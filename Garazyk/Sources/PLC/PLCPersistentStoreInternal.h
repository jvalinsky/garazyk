// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCPersistentStoreInternal.h
 @abstract Internal interface for PLCPersistentStore and subclasses.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PLC/PLCPersistentStore.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLCPersistentStore ()

@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite, nullable) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *stmtCache;

@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readonly) dispatch_queue_t transactionQueue;

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
