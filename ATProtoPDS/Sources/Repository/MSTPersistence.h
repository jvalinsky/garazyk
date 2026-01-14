/*!
 @file MSTPersistence.h

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
@class CID;
@class PDSDatabase;

/*!
 @class MSTPersistence

 @abstract Persistence manager for Merkle Search Trees.

 @discussion Handles storage and retrieval of MST structures and nodes.
 MSTs are stored per-DID in actor databases. Nodes are content-addressed
 by CID for deduplication and efficient sync.
 */
@interface MSTPersistence : NSObject

/*! Get singleton persistence instance. */
+ (instancetype)shared;

/*! Save complete MST structure for DID. */
- (BOOL)saveMST:(MST *)mst forDid:(NSString *)did error:(NSError **)error;

/*! Load complete MST structure for DID. */
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

/*! Save individual MST node with CID. */
- (BOOL)saveMSTNode:(MSTNode *)node withCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Load individual MST node by CID. */
- (nullable MSTNode *)loadMSTNodeWithCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Delete all MST data for DID. */
- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
