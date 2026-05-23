// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Moderation database operations for reports and labels.
 */
@interface PDSDatabase (Moderation)

- (BOOL)takeDownAccount:(NSString *)did reason:(nullable NSString *)reason takedownRef:(nullable NSString *)ref error:(NSError **)error;
- (BOOL)deactivateAccount:(NSString *)did error:(NSError **)error;
- (BOOL)activateAccount:(NSString *)did error:(NSError **)error;
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;
- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error;
- (BOOL)isRecordTakedownActive:(NSString *)uri error:(NSError **)error;
- (nullable NSString *)accountStatusForDid:(NSString *)did error:(NSError **)error;
/**
 * @abstract Create label.
 * @param label Moderation label to apply.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)createLabel:(NSDictionary *)label error:(NSError **)error;
- (NSArray<NSDictionary *> *)getLabelsWithPatterns:(nullable NSArray<NSString *> *)uriPatterns sources:(nullable NSArray<NSString *> *)sources limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
