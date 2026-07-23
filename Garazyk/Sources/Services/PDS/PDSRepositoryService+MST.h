// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService (MST)

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;
- (nullable MST *)loadMSTForDid:(NSString *)did store:(PDSActorStore *)store error:(NSError **)error;
- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error;
- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error;
- (MST *)mstFromRecords:(NSArray<PDSDatabaseRecord *> *)records;

@end

NS_ASSUME_NONNULL_END
