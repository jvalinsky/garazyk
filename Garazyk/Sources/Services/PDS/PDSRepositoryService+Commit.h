// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService (Commit)

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;
- (nullable NSDictionary *)headInfoForDid:(NSString *)did error:(NSError **)error;
- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
