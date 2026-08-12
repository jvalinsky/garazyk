// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import <Foundation/Foundation.h>
#import "Network/PDSRepoImportValidationResult.h"
#import "Repository/CAR.h"
#import "Repository/RepoCommit.h"
#import "Database/Pool/DatabasePool.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepoImportValidator : NSObject

/*!
 @abstract Validates a caller-supplied repo CAR before import.
 @discussion The reader must be an ATProtoCARStreamReader constructed in strict
 mode; this method streams the full body once, verifying every block (the
 strict reader already enforces DASL conformance and per-block CID hashes),
 enforcing the block-count bound, checking the commit CID against the CAR
 root and the commit signature against the DID document, and extracting
 records via an MST walk over the reader's block index. No database writes
 happen here — failures surface as clean validation errors.
 @param carData The raw CAR bytes (used for the size bound).
 @param reader Strict-mode streaming reader over carData.
 @param commit The repo commit parsed from the CAR root.
 @param did The authenticated account DID; the commit must match it.
 @param databasePool Pool used to resolve the DID document for signature checks.
 @param allowLocalKeyFallback Permit verification against the actor store's
   local signing key when the PLC endpoint is mock/skip.
 @param maxImportSize Maximum accepted body size in bytes (configuration).
 @param error On return, contains an error if validation failed.
 @return A validation result (records) on success, nil on failure.
 */
+ (nullable PDSRepoImportValidationResult *)validateCARData:(NSData *)carData
                                                     reader:(ATProtoCARStreamReader *)reader
                                                     commit:(ATProtoRepoCommit *)commit
                                                        did:(NSString *)did
                                              databasePool:(PDSDatabasePool *)databasePool
                                     allowLocalKeyFallback:(BOOL)allowLocalKeyFallback
                                             maxImportSize:(NSUInteger)maxImportSize
                                                      error:(NSError **)error;

/*! @abstract The per-import CAR block-count bound (DoS guard). */
+ (NSUInteger)maxImportCARBlocks;

/*! @abstract Batch size used when writing imported blocks inside the transaction. */
+ (NSUInteger)importBlockBatchSize;

@end

NS_ASSUME_NONNULL_END
