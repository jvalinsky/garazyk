// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSServiceMigration002.h
 @brief Schema migration 002 — add missing columns for server compatibility.

 @discussion Migration 2 adds columns that were introduced after the initial
 server deployment (commit 82789dc5, Feb 25 2026). These columns already
 exist in the CREATE TABLE statements for fresh databases, but databases
 created by the earlier schema need them added via ALTER TABLE.

 Columns added:
 - accounts.age_assurance TEXT
 - accounts.age_verified_at TEXT
 - accounts.webauthn_enabled INTEGER DEFAULT 0
 - records.indexed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
 - jwt_signing_keys.keychain_tag TEXT
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSServiceMigration002 : NSObject
@end

NS_ASSUME_NONNULL_END
