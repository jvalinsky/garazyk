/*!
 @file DraftService.h

 @abstract Draft storage service for app.bsky.draft.* endpoints.

 @discussion Provides CRUD operations for user drafts stored in the
 service database. Drafts are scoped per-actor via the did column.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class DraftService

 @abstract Service for draft storage operations.

 @discussion Manages draft records in the service database. Each draft
 belongs to an actor (identified by DID) and stores arbitrary JSON content.
 */
@interface DraftService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;

#pragma mark - CRUD

/*! Create a new draft for the given actor. Returns the draft dictionary. */
- (nullable NSDictionary *)createDraftForDID:(NSString *)actorDID
                                     content:(NSDictionary *)content
                                       error:(NSError **)error;

/*! Update an existing draft. */
- (BOOL)updateDraftForDID:(NSString *)actorDID
                  draftID:(NSString *)draftID
                  content:(NSDictionary *)content
                    error:(NSError **)error;

/*! Get all drafts for an actor. */
- (nullable NSArray<NSDictionary *> *)getDraftsForDID:(NSString *)actorDID
                                                error:(NSError **)error;

/*! Delete a draft. */
- (BOOL)deleteDraftForDID:(NSString *)actorDID
                  draftID:(NSString *)draftID
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
