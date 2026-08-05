// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMSTPersistence.h

 @abstract Persistence layer for Merkle Search Tree storage.

 @discussion Provides save/load operations for MST structures and nodes.
 Stores MST trees and nodes in per-DID databases, enabling efficient
 repository state management and synchronization.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MST;
@class MSTNode;
@class ATProtoCID;
@class PDSDatabase;

/*!
 @class ATProtoMSTPersistence

 @abstract Persistence manager for Merkle Search Trees.

 @discussion Handles storage and retrieval of MST structures and nodes.
 MSTs are stored per-DID in actor databases. Nodes are content-addressed
 by ATProtoCID for deduplication and efficient sync.
 */
@interface ATProtoMSTPersistence : NSObject

/*! Get singleton persistence instance. */
+ (instancetype)shared;

/*! Save complete MST structure for DID. */
- (BOOL)saveMST:(MST *)mst forDid:(NSString *)did error:(NSError **)error;

/*! Load complete MST structure for DID. */
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

/*! Save individual MST node with ATProtoCID. */
- (BOOL)saveMSTNode:(MSTNode *)node withCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Load individual MST node by ATProtoCID. */
- (nullable MSTNode *)loadMSTNodeWithCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Delete all MST data for DID. */
- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error;

@property (nonatomic, strong, nullable) PDSDatabase *database;

@end

NS_ASSUME_NONNULL_END
