// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSDatabaseRepo
 * 
 * @abstract Represents a repository in the database.
 * 
 * @discussion A repository contains a user's collection of records and blocks.
 * Each repository is identified by its owner's DID and has a current root CID
 * representing the state of the Merkle Search Tree.
 * 
 * @see PDSDatabase (Repos)
 */
@interface PDSDatabaseRepo : NSObject <PDSDatabaseModel>

/** The DID of the repository owner. */
@property (nonatomic, copy) NSString *ownerDid;

/** The current root CID of the repository's Merkle Search Tree. */
@property (nonatomic, copy) NSData *rootCid;

/** Optional serialized collection index data. */
@property (nonatomic, copy, nullable) NSData *collectionData;

/** Date when the repository was created. */
@property (nonatomic, strong) NSDate *createdAt;

/** Date when the repository was last updated. */
@property (nonatomic, strong) NSDate *updatedAt;

@end

NS_ASSUME_NONNULL_END
