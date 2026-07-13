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

@class ATProtoConnectionManagerSerial;
@class ATProtoDatabaseQueryRunner;

NS_ASSUME_NONNULL_BEGIN

@interface PLCPersistentStore ()

/**
 * @abstract Exposes the db path value.
 */
@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;

/// Serial connection manager that owns the SQLite connection, replacing the previously
/// hand-rolled transaction queue + raw sqlite3 handle. Subclasses may use it for raw
/// multi-statement work via -execute:/-transact:.
@property (nonatomic, strong, readonly) ATProtoConnectionManagerSerial *connectionManager;

/// Deep module over the connection for prepare/bind/step; subclasses run their queries
/// through this instead of touching a raw sqlite3 *.
@property (nonatomic, strong, readonly) ATProtoDatabaseQueryRunner *queryRunner;

@end

NS_ASSUME_NONNULL_END
