/*!
 @file AppViewIndexHook.h

 @abstract Protocol for index hooks — callbacks fired after record indexing.

 @discussion Index hooks allow operators to attach custom logic when records
 are created, updated, or deleted. Hooks fire asynchronously on a background
 queue after successful indexing, so they don't block the critical ingest path.

 Hook failures are logged and recorded in the dead_letter_hooks table.
 Hooks can be filtered by collection (only fire for specific collections).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol AppViewIndexHook

 @abstract A callback that fires after record indexing events.
 */
@protocol AppViewIndexHook <NSObject>

/*!
 @method hookIdentifier

 @abstract Unique identifier for this hook (for logging and dead-letter tracking).
 */
- (NSString *)hookIdentifier;

/*!
 @method collections

 @abstract Collections this hook should fire for.

 @return Array of collection NSIDs, or nil to fire for all collections.
 */
- (nullable NSArray<NSString *> *)collections;

/*!
 @method didIndexRecord:uri:did:collection:

 @abstract Called after a record is successfully indexed (created or updated).

 @param record     The indexed record dictionary.
 @param uri        The AT URI of the record.
 @param did        The DID of the repo.
 @param collection The collection NSID.
 */
- (void)didIndexRecord:(NSDictionary *)record
                   uri:(NSString *)uri
                    did:(NSString *)did
            collection:(NSString *)collection;

/*!
 @method didDeleteRecordWithURI:did:collection:

 @abstract Called after a record is successfully deleted.

 @param uri        The AT URI of the deleted record.
 @param did        The DID of the repo.
 @param collection The collection NSID.
 */
- (void)didDeleteRecordWithURI:(NSString *)uri
                           did:(NSString *)did
                    collection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
