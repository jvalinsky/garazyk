// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Reads repository-root and signed-head metadata used by repository synchronization.
 * @discussion These methods access actor-scoped storage through the database pool and do not
 * mutate state, except getLatestCommitForDid:error:, which can repair incomplete export state.
 */
@interface PDSRepositoryService (Commit)

/**
 * @abstract Returns the stored block data addressed by the repository root ATProtoCID.
 * @param did The actor DID whose root block is requested.
 * @param error Receives actor-store, repository-metadata, or block-lookup failures.
 * @return The root block bytes, or nil when the actor, root metadata, or referenced block is absent.
 */
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;
/**
 * @abstract Returns persisted signed-head metadata without rebuilding the repository.
 * @discussion The result contains string keys cid and rev. It is returned only when repo_root
 * addresses a signed commit; the revision comes from stored repository metadata when available,
 * otherwise from that commit. Missing or unsigned head data returns nil without self-healing.
 * @param did The actor DID whose head is requested.
 * @param error Receives actor-store lookup failures.
 * @return A cid/rev dictionary for the signed head, or nil when no signed head is stored.
 */
- (nullable NSDictionary *)headInfoForDid:(NSString *)did error:(NSError **)error;
/**
 * @abstract Returns the current signed commit ATProtoCID and repository revision.
 * @discussion Uses persisted signed-head metadata when it matches the repository. Otherwise it
 * rebuilds export state and may materialize missing record blocks, backfill record revisions, and
 * create and persist a signed head commit. Those repair writes are committed transactionally per
 * actor store; failures return nil and report an error.
 * @param did The actor DID whose current commit is requested.
 * @param error Receives actor-store, block-materialization, signing, or persistence failures.
 * @return A dictionary containing string keys cid and rev, or nil when no current commit can be prepared.
 */
- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
