// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (AdminConfig)

- (nullable NSString *)getAdminConfigValue:(NSString *)key error:(NSError **)error;
- (BOOL)setAdminConfigValue:(NSString *)value forKey:(NSString *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
