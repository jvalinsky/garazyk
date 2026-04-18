#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @class AdminUITemplateRenderer
 * @brief Simple template renderer for AdminUI HTML responses.
 *
 * Provides basic template rendering with variable substitution ({{key}})
 * and simple conditionals ({{#if key}}...{{/if}}) and loops ({{#each items}}...{{/each}}).
 */
@interface AdminUITemplateRenderer : NSObject

/**
 * @brief Renders a template string with the given context data.
 *
 * @param template The template string with {{key}} placeholders.
 * @param context Dictionary of key-value pairs for substitution.
 * @return The rendered template with all placeholders replaced.
 */
+ (NSString *)renderTemplate:(NSString *)template withContext:(NSDictionary *)context;

/**
 * @brief Renders a template string with conditional and loop support.
 *
 * @param template The template with {{#if}}, {{#each}}, and {{key}} markers.
 * @param context Dictionary with keys, arrays, and boolean values.
 * @return The rendered template.
 *
 * Example:
 *   {{#if active}}<span class="badge badge-success">Active</span>{{/if}}
 *   {{#each items}}<li>{{name}}</li>{{/each}}
 */
+ (NSString *)renderAdvancedTemplate:(NSString *)template withContext:(NSDictionary *)context;

/**
 * @brief Safely substitutes a value into a template, escaping HTML entities.
 *
 * @param value The value to substitute.
 * @return The HTML-escaped value.
 */
+ (NSString *)escapeHTML:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
