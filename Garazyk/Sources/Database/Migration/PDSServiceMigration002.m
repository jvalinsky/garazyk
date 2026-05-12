// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabaseMigration.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

/*!
 @class PDSServiceMigration002
 @brief Add columns introduced after initial server deployment.

 @discussion Databases created before the age_assurance, webauthn, and
 indexed_at features need these columns added. Fresh databases already
 include them in CREATE TABLE statements, so all ALTERs guard against
 "duplicate column name" errors.
 */
@interface PDSServiceMigration002 : NSObject <PDSDatabaseMigration>
@end

@implementation PDSServiceMigration002

- (NSInteger)version {
    return 2;
}

- (NSString *)description {
    return @"Add age_assurance, age_verified_at, webauthn_enabled to accounts; indexed_at to records; keychain_tag to jwt_signing_keys";
}

- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error {
    // Each ALTER is idempotent: if the column already exists (fresh DB),
    // the "duplicate column name" error is caught and ignored.

    // Note: SQLite ALTER TABLE ADD COLUMN does not support non-constant
    // defaults (e.g., strftime()). Use a constant sentinel default and
    // backfill existing rows with created_at as a fallback.

    NSArray<NSString *> *alterStatements = @[
        // accounts: age_assurance, age_verified_at, webauthn_enabled
        @"ALTER TABLE accounts ADD COLUMN age_assurance TEXT",
        @"ALTER TABLE accounts ADD COLUMN age_verified_at TEXT",
        @"ALTER TABLE accounts ADD COLUMN webauthn_enabled INTEGER DEFAULT 0",

        // records: indexed_at — constant default, backfilled below
        @"ALTER TABLE records ADD COLUMN indexed_at TEXT NOT NULL DEFAULT ''",

        // jwt_signing_keys: keychain_tag
        @"ALTER TABLE jwt_signing_keys ADD COLUMN keychain_tag TEXT",
    ];

    for (NSString *sql in alterStatements) {
        NSError *execError = nil;
        BOOL success = [database executeParameterizedUpdate:sql params:@[] error:&execError];

        if (!success) {
            NSString *errMsg = execError.localizedDescription;
            // "duplicate column name" means the column already exists — not an error
            if ([errMsg containsString:@"duplicate column name"]) {
                GZ_LOG_DB_DEBUG(@"Migration 002: column already exists, skipping: %@", sql);
                continue;
            }
            // Real error
            if (error) *error = execError;
            GZ_LOG_DB_ERROR(@"Migration 002 failed on %@: %@", sql, errMsg);
            return NO;
        }
    }

    // Backfill indexed_at for existing records: use created_at as fallback.
    // New records will get indexed_at set by the application layer.
    NSError *backfillError = nil;
    BOOL backfillSuccess = [database executeParameterizedUpdate:
        @"UPDATE records SET indexed_at = created_at WHERE indexed_at = ''"
        params:@[] error:&backfillError];
    if (!backfillSuccess) {
        GZ_LOG_DB_WARN(@"Migration 002: backfill of indexed_at failed (non-fatal): %@",
                        backfillError.localizedDescription);
        // Non-fatal: existing records will have empty indexed_at until
        // the application layer sets it on next write.
    }

    GZ_LOG_DB_INFO(@"Migration 002: all column additions applied successfully");
    return YES;
}

@end
