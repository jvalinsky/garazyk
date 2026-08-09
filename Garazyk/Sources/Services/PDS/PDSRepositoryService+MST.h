// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Loads, rebuilds, and updates an actor repository's Merkle Search Tree.
 * @discussion The category uses the shared ATProtoMST cache when possible, then reconstructs a tree
 * from persisted repository blocks or record rows. The cache and ATProtoMST root publication are
 * thread-safe, but this category does not couple an ATProtoMST mutation and root persistence in one
 * transaction. A persistence failure does not restore the in-memory tree.
 */
@interface PDSRepositoryService (ATProtoMST)

/**
 * @abstract Returns the cached or reconstructed ATProtoMST for an actor.
 * @discussion Obtains the actor store, tries repository-block reconstruction, and falls back to
 * rebuilding from persisted records. A successfully loaded tree is placed in the shared cache.
 * @param did The actor DID whose repository is loaded.
 * @param error Receives actor-store or record-loading failures.
 * @return The actor's ATProtoMST, or nil when the actor store cannot be opened or record fallback fails.
 */
- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did error:(NSError **)error;
/**
 * @abstract Returns the cached or reconstructed ATProtoMST using an existing actor store.
 * @discussion The supplied store must address did. Repository-block loading is attempted without
 * propagating its error; record reconstruction supplies the reported error when it also fails.
 * @param did The actor DID whose repository is loaded.
 * @param store The actor store to query for repository blocks or records.
 * @param error Receives record-loading failures from the fallback path.
 * @return The actor's ATProtoMST, or nil when record fallback fails.
 */
- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did store:(PDSActorStore *)store error:(NSError **)error;
/**
 * @abstract Reconstructs an ATProtoMST from persisted repository blocks.
 * @param did The actor DID that scopes the repository blocks.
 * @param store The actor store containing the blocks.
 * @param error Receives block decoding or lookup failures.
 * @return The reconstructed ATProtoMST, or nil when the stored block graph cannot be loaded.
 */
- (nullable ATProtoMST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;
/**
 * @abstract Inserts, replaces, or removes one collection/rkey entry and stores the resulting root ATProtoCID.
 * @discussion A nonnull cid is stored at key; a nil cid removes key. The cached ATProtoMST is mutated before the root is persisted, and a failed write neither creates a signed commit nor rolls back the cache.
 * @param did The actor DID whose repository is updated.
 * @param key The ATProtoMST collection/rkey key to insert, replace, or remove.
 * @param cid The record ATProtoCID to store, or nil to remove key.
 * @param error Receives ATProtoMST-root computation, actor-store, or repository-root persistence failures.
 * @return YES when the computed root ATProtoCID was persisted; otherwise NO.
 */
- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable ATProtoCID *)cid error:(NSError **)error;
/**
 * @abstract Builds an ATProtoMST from valid persisted record entries.
 * @discussion Each record with a nonempty collection, rkey, and parseable ATProtoCID contributes a
 * collection/rkey-to-ATProtoCID entry. Malformed or incomplete records are omitted.
 * @param records The records from which to build the tree.
 * @return A new ATProtoMST containing the valid record entries.
 */
- (ATProtoMST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;

@end

NS_ASSUME_NONNULL_END
