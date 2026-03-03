/*!
 @file PDSRepoRepository.h
 @abstract Protocol for repository metadata access.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseRepo;

/*!
 @protocol PDSRepoRepository
 @abstract Protocol for repository metadata access operations.
 */
@protocol PDSRepoRepository <NSObject>

/*! Creates a new repository record. */
- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;

/*! Updates a repository's root CID. */
- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error;

/*! Retrieves repository metadata by owner DID. */
- (nullable PDSDatabaseRepo *)repoForDid:(NSString *)did error:(NSError **)error;

/*! Retrieves all repository records. */
- (nullable NSArray<PDSDatabaseRepo *> *)allReposWithError:(NSError **)error;

/*! Deletes a repository record. */
- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
