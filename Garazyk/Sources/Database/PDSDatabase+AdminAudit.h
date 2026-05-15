// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (AdminAudit)

- (BOOL)insertAuditLogEntry:(NSDictionary *)entry error:(NSError **)error;
- (NSArray<NSDictionary *> *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (BOOL)deleteAuditLogsOlderThanDays:(NSInteger)days error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
