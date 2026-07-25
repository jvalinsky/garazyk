// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UITemplateEngine : NSObject

/// Loads an HTML template from Assets/html and replaces {{key}} with values from the context dictionary.
+ (NSString *)renderTemplate:(NSString *)templateName context:(NSDictionary<NSString *, id> *)context;

@end

NS_ASSUME_NONNULL_END
