// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for moderation reports.
 */
@interface PDSDatabase (Reports)

- (NSString *)createReport:(NSDictionary *)report error:(NSError **)error;
- (NSArray<NSDictionary *> *)queryReports:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (nullable NSDictionary *)getReportById:(NSString *)reportId error:(NSError **)error;
- (BOOL)updateReportStatus:(NSString *)reportId status:(NSString *)status resolvedBy:(nullable NSString *)adminDid notes:(nullable NSString *)notes error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
