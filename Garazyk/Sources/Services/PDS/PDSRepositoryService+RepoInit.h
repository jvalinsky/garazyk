// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService (RepoInit)

- (BOOL)initializeRepoForDid:(NSString *)did error:(NSError **)error;
- (BOOL)forceReinitializeRepoForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
