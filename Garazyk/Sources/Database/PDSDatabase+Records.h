// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Records)

 @abstract Record CRUD methods for PDSDatabase.

 @discussion These methods provide operations for managing individual records
 within repositories. Records are identified by AT-URIs and contain typed content.
 */
@interface PDSDatabase (Records)

/*!
 @method saveRecord:error:

 @abstract Saves or updates a record in the database.

 @param record The record object to save.
 @param error On return, contains an error if the operation failed.
 @return YES if the record was saved successfully, NO otherwise.
 */
- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error;

/*!
 @method getRecord:error:

 @abstract Retrieves a record by its URI.

 @param uri The AT-URI of the record.
 @param error On return, contains an error if the operation failed.
 @return The record object, or nil if not found.
 */
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error;

/*!
 @method getRecordsForDid:collection:error:

 @abstract Retrieves records from a repository.

 @param did The DID of the repository owner.
 @param collection Optional collection filter (e.g., app.bsky.actor.profile).
 @param error On return, contains an error if the operation failed.
 @return An array of matching record objects.
 */
- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
