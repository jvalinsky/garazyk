/*!
 @file AppViewIndexHookRegistry.h

 @abstract Registry and dispatcher for index hooks.

 @discussion Manages hook registration and dispatches hook callbacks
 asynchronously on a background queue. Hook failures are logged
 and recorded in the dead_letter_hooks table.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class AppViewDatabase;

NS_ASSUME_NONNULL_BEGIN

@protocol AppViewIndexHook;

/*!
 @class AppViewIndexHookRegistry

 @abstract Manages and dispatches index hooks.
 */
@interface AppViewIndexHookRegistry : NSObject

/*!
 @method initWithDatabase:

 @abstract Initialize with the database for dead-letter recording.

 @param database The AppView database.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database;

/*!
 @method registerHook:

 @abstract Register an index hook.

 @param hook The hook to register.
 */
- (void)registerHook:(id<AppViewIndexHook>)hook;

/*!
 @method unregisterHook:

 @abstract Remove an index hook by its identifier.

 @param hookIdentifier The identifier of the hook to remove.
 */
- (void)unregisterHook:(NSString *)hookIdentifier;

/*!
 @method fireDidIndexRecord:uri:did:collection:

 @abstract Fire all matching hooks for a record index event.

 @discussion Hooks fire asynchronously on a background queue.
 Only hooks whose collections filter matches (or is nil) will fire.

 @param record     The indexed record dictionary.
 @param uri        The AT URI of the record.
 @param did        The DID of the repo.
 @param collection The collection NSID.
 */
- (void)fireDidIndexRecord:(NSDictionary *)record
                       uri:(NSString *)uri
                        did:(NSString *)did
                collection:(NSString *)collection;

/*!
 @method fireDidDeleteRecordWithURI:did:collection:

 @abstract Fire all matching hooks for a record delete event.

 @param uri        The AT URI of the deleted record.
 @param did        The DID of the repo.
 @param collection The collection NSID.
 */
- (void)fireDidDeleteRecordWithURI:(NSString *)uri
                               did:(NSString *)did
                        collection:(NSString *)collection;

/*!
 @method registeredHookCount

 @abstract Return the number of registered hooks.
 */
- (NSUInteger)registeredHookCount;

@end

NS_ASSUME_NONNULL_END
