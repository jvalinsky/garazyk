// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMSTPersistence.h

 @abstract Persistence layer for Merkle Search Tree storage.

 @discussion Provides save/load operations for ATProtoMST structures and nodes.
 Stores ATProtoMST trees and nodes in per-DID databases, enabling efficient
 repository state management and synchronization.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoMST;
@class ATProtoMSTNode;
@class ATProtoCID;
@class PDSDatabase;

/*!
 @class ATProtoMSTPersistence

 @abstract Persistence manager for Merkle Search Trees.

 @discussion Handles storage and retrieval of ATProtoMST structures and nodes.
 MSTs are stored per-DID in actor databases. Nodes are content-addressed
 by ATProtoCID for deduplication and efficient sync.
 */
@interface ATProtoMSTPersistence : NSObject

/*! Get singleton persistence instance. */
+ (instancetype)shared;

/*! Save complete ATProtoMST structure for DID. */
- (BOOL)saveMST:(ATProtoMST *)mst forDid:(NSString *)did error:(NSError **)error;

/*! Load complete ATProtoMST structure for DID. */
- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

/*! Save individual ATProtoMST node with ATProtoCID. */
- (BOOL)saveMSTNode:(ATProtoMSTNode *)node withCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Load individual ATProtoMST node by ATProtoCID. */
- (nullable ATProtoMSTNode *)loadMSTNodeWithCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Delete all ATProtoMST data for DID. */
- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error;

@property (nonatomic, strong, nullable) PDSDatabase *database;

@end

NS_ASSUME_NONNULL_END
