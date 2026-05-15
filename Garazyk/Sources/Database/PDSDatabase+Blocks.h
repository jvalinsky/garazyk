// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (Blocks)

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;
- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;
- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;
- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error;
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
