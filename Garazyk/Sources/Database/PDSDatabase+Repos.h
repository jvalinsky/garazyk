// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Repos)

 @abstract Repository management methods for PDSDatabase.

 @discussion These methods provide CRUD operations for user repositories.
 Repositories contain collections of records organized in a Merkle Search Tree.
 */
@interface PDSDatabase (Repos)

/*!
 @method createRepo:error:

 @abstract Creates a new repository.

 @param repo The repository object containing owner and initial state.
 @param error On return, contains an error if the operation failed.
 @return YES if the repository was created successfully, NO otherwise.
 */
- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;

/*!
 @method updateRepoRoot:rootCid:error:

 @abstract Updates the root CID of a repository.

 @discussion This method updates the repository's Merkle Search Tree root
 after a commit operation.

 @param ownerDid The DID of the repository owner.
 @param rootCid The new root CID.
 @param error On return, contains an error if the operation failed.
 @return YES if the root was updated successfully, NO otherwise.
 */
/**
 * @abstract Update repo root.
 * @param ownerDid Actor DID for the request.
 * @param rootCid Repository root CID.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error;

/*!
 @method getRepoForDid:error:

 @abstract Retrieves a repository by owner DID.

 @param did The DID of the repository owner.
 @param error On return, contains an error if the operation failed.
 @return The repository object, or nil if not found.
 */
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;

/*!
 @method getAllReposWithError:

 @abstract Retrieves all repositories.

 @param error On return, contains an error if the operation failed.
 @return An array of all repository objects.
 */
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;

/*!
 @method deleteRepo:error:

 @abstract Deletes a repository and all its records and blocks.

 @param ownerDid The DID of the repository owner.
 @param error On return, contains an error if the operation failed.
 @return YES if the repository was deleted successfully, NO otherwise.
 */
- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
