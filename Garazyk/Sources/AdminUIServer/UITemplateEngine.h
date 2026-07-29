// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Renders packaged admin HTML templates with a small Mustache-like substitution language.
 * @discussion Double-brace string and number values are HTML-escaped; triple-brace values are
 * inserted verbatim. Array sections repeat for dictionary elements, while truthy and inverted
 * sections select content by context value. Callers must restrict template names to trusted assets
 * and use triple-brace placeholders only for already-sanitized markup.
 */
@interface UITemplateEngine : NSObject

/**
 * @abstract Loads an admin template and applies the supplied substitution context.
 * @param templateName Trusted template basename, resolved beneath the packaged HTML asset directory.
 * @param context Values used for escaped placeholders, raw placeholders, and conditional sections.
 * @return Rendered HTML, or a visible error fragment when the template cannot be loaded.
 */
+ (NSString *)renderTemplate:(NSString *)templateName context:(NSDictionary<NSString *, id> *)context;

@end

NS_ASSUME_NONNULL_END
