// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZHTML.h"

@interface GZHTML ()
+ (void)appendAttributes:(nullable NSDictionary<NSString *, NSString *> *)attributes
                toString:(NSMutableString *)html;
@end

@implementation GZHTML

#pragma mark - Escaping

+ (NSString *)escapedString:(NSString *)string {
    if (!string || string.length == 0) {
        return @"";
    }
    NSMutableString *s = [NSMutableString stringWithString:string];
    // Order matters: & must be first to avoid double-escaping entities produced
    // by subsequent replacements.
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

+ (NSString *)text:(NSString *)text {
    return [self escapedString:text];
}

+ (NSString *)raw:(NSString *)html {
    return html ?: @"";
}

#pragma mark - Element Construction

+ (NSString *)element:(NSString *)tag
            attributes:(nullable NSDictionary<NSString *, NSString *> *)attributes
              children:(nullable NSArray<NSString *> *)children {
    NSMutableString *html = [NSMutableString stringWithFormat:@"<%@", tag];
    [self appendAttributes:attributes toString:html];
    if (children.count == 0) {
        [html appendFormat:@"></%@>", tag];
        return html;
    }
    [html appendString:@">"];
    for (NSString *child in children) {
        if (child) {
            [html appendString:child];
        }
    }
    [html appendFormat:@"</%@>", tag];
    return html;
}

+ (NSString *)voidElement:(NSString *)tag
                attributes:(nullable NSDictionary<NSString *, NSString *> *)attributes {
    NSMutableString *html = [NSMutableString stringWithFormat:@"<%@", tag];
    [self appendAttributes:attributes toString:html];
    [html appendString:@"/>"];
    return html;
}

#pragma mark - Compound Elements

+ (NSString *)alertWithType:(NSString *)type message:(NSString *)message {
    return [NSString stringWithFormat:@"<div class=\"alert alert-%@\">%@</div>",
            [self escapedString:type],
            [self escapedString:message]];
}

+ (NSString *)tableWithHeaders:(NSArray<NSString *> *)headers
                          rows:(nullable NSArray<NSArray<NSString *> *> *)rows
                  emptyMessage:(NSString *)emptyMessage {
    NSUInteger colCount = headers.count;
    NSMutableArray<NSString *> *htmlRows = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray<NSString *> *row in rows) {
        [htmlRows addObject:[self tableRowWithCells:row]];
    }
    return [self tableWithHeaders:headers htmlRows:htmlRows emptyMessage:emptyMessage];
}

+ (NSString *)tableWithHeaders:(NSArray<NSString *> *)headers
                       htmlRows:(nullable NSArray<NSString *> *)htmlRows
                  emptyMessage:(NSString *)emptyMessage {
    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<table class=\"table\"><thead><tr>"];
    for (NSString *header in headers) {
        [html appendFormat:@"<th>%@</th>", [self escapedString:header]];
    }
    [html appendString:@"</tr></thead><tbody>"];
    if (htmlRows.count > 0) {
        for (NSString *row in htmlRows) {
            [html appendString:row];
        }
    } else {
        [html appendString:[self emptyStateRowWithColspan:headers.count message:emptyMessage]];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)tableRowWithCells:(NSArray<NSString *> *)cells {
    NSMutableString *html = [NSMutableString stringWithString:@"<tr>"];
    for (NSString *cell in cells) {
        [html appendFormat:@"<td>%@</td>", [self escapedString:cell]];
    }
    [html appendString:@"</tr>"];
    return html;
}

+ (NSString *)tableRowWithHtmlCells:(NSArray<NSString *> *)htmlCells {
    NSMutableString *html = [NSMutableString stringWithString:@"<tr>"];
    for (NSString *cell in htmlCells) {
        [html appendFormat:@"<td>%@</td>", cell ?: @""];
    }
    [html appendString:@"</tr>"];
    return html;
}

+ (NSString *)emptyStateRowWithColspan:(NSUInteger)colspan
                                message:(NSString *)message {
    return [NSString stringWithFormat:
            @"<tr><td colspan=\"%lu\" class=\"text-center text-secondary p-lg\">%@</td></tr>",
            (unsigned long)colspan, [self escapedString:message]];
}

+ (NSString *)detailGridWithFields:(NSArray<NSDictionary<NSString *, NSString *> *> *)fields {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    for (NSDictionary<NSString *, NSString *> *field in fields) {
        NSString *label = [self escapedString:field[@"label"]];
        NSString *value = [self escapedString:field[@"value"]];
        NSString *fullWidth = field[@"fullWidth"];
        NSString *fieldClass = [fullWidth isEqualToString:@"true"] ? @"detail-field full-width" : @"detail-field";
        [html appendFormat:@"<div class=\"%@\"><span class=\"detail-label\">%@</span>"
                         "<span class=\"detail-value\">%@</span></div>",
                         fieldClass, label, value];
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)metricRowWithMetrics:(NSArray<NSDictionary<NSString *, NSString *> *> *)metrics {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];
    for (NSDictionary<NSString *, NSString *> *metric in metrics) {
        NSString *label = [self escapedString:metric[@"label"]];
        NSString *value = [self escapedString:metric[@"value"]];
        [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">%@</span>"
                         "<span class=\"metric-value\">%@</span></div>",
                         label, value];
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)badgeWithClass:(NSString *)className text:(NSString *)text {
    return [NSString stringWithFormat:@"<span class=\"%@\">%@</span>",
            [self escapedString:className], [self escapedString:text]];
}

+ (NSString *)paginationButtonWithHref:(NSString *)href
                                target:(NSString *)target
                                 label:(NSString *)label {
    return [NSString stringWithFormat:
            @"<div class=\"d-flex justify-between mt-sm\">"
             "<button class=\"btn btn-secondary btn-sm\" hx-get=\"%@\" hx-target=\"%@\">%@</button>"
             "</div>",
            [self escapedString:href], [self escapedString:target], [self escapedString:label]];
}

+ (NSString *)sectionWithTitle:(NSString *)title
                       content:(NSString *)content
                    className:(nullable NSString *)className {
    NSString *sectionClass = className.length > 0 ? className : @"mt-lg";
    return [NSString stringWithFormat:
            @"<section class=\"%@\"><h3 class=\"section-title\">%@</h3>%@</section>",
            [self escapedString:sectionClass], [self escapedString:title], content ?: @""];
}

+ (NSString *)buttonWithClass:(NSString *)className
                         text:(NSString *)text
                       action:(NSString *)action
                         data:(nullable NSDictionary<NSString *, NSString *> *)data {
    NSMutableString *html = [NSMutableString stringWithFormat:@"<button class=\"%@\" data-ui-action=\"%@\"",
                            [self escapedString:className], [self escapedString:action]];
    for (NSString *key in data) {
        NSString *attrName = [NSString stringWithFormat:@"data-%@", key];
        [html appendFormat:@" %@=\"%@\"", attrName, [self escapedString:data[key]]];
    }
    [html appendFormat:@">%@</button>", [self escapedString:text]];
    return html;
}

+ (NSString *)inputWithType:(NSString *)type
                        name:(NSString *)name
                 placeholder:(nullable NSString *)placeholder
                       value:(nullable NSString *)value
                    className:(nullable NSString *)className {
    NSMutableDictionary<NSString *, NSString *> *attrs = [NSMutableDictionary dictionary];
    attrs[@"type"] = type;
    attrs[@"name"] = name;
    if (placeholder.length > 0) attrs[@"placeholder"] = placeholder;
    if (value.length > 0) attrs[@"value"] = value;
    if (className.length > 0) attrs[@"class"] = className;
    return [self voidElement:@"input" attributes:attrs];
}

+ (NSString *)linkWithHref:(NSString *)href
                      text:(NSString *)text
                  className:(nullable NSString *)className {
    NSMutableDictionary<NSString *, NSString *> *attrs = [NSMutableDictionary dictionary];
    attrs[@"href"] = href;
    if (className.length > 0) attrs[@"class"] = className;
    return [self element:@"a" attributes:attrs children:@[[self escapedString:text]]];
}

#pragma mark - Product dashboard primitives

+ (NSString *)detailCardWithFields:(NSArray<NSDictionary<NSString *, NSString *> *> *)fields {
    NSMutableString *html = [NSMutableString stringWithString:[self detailCardOpening]];
    for (NSDictionary<NSString *, NSString *> *field in fields) {
        NSString *label = field[@"label"] ?: @"";
        NSString *valueHTML = field[@"html"];
        if (valueHTML.length == 0) {
            valueHTML = [self text:field[@"value"] ?: @"—"];
        }
        [html appendString:[self detailRowWithLabel:label valueHTML:valueHTML]];
    }
    [html appendString:[self detailCardClosing]];
    return html;
}

+ (NSString *)detailCardOpening { return @"<div class=\"detail-card\">"; }
+ (NSString *)detailCardClosing { return @"</div>"; }

+ (NSString *)detailRowWithLabel:(NSString *)label valueHTML:(nullable NSString *)valueHTML {
    return [NSString stringWithFormat:
            @"<div class=\"detail-row\">"
            @"<span class=\"detail-label\">%@</span>"
            @"<span class=\"detail-value\">%@</span>"
            @"</div>",
            [self escapedString:label],
            valueHTML.length > 0 ? valueHTML : @"—"];
}

+ (NSString *)healthBadge:(nullable NSString *)health {
    NSString *normalized = health.lowercaseString ?: @"unknown";
    if ([normalized isEqualToString:@"ok"] || [normalized isEqualToString:@"healthy"]) {
        return [self badgeWithClass:@"badge badge-success" text:@"Healthy"];
    }
    if ([normalized isEqualToString:@"degraded"]) {
        return [self badgeWithClass:@"badge badge-warning" text:@"Degraded"];
    }
    return [self badgeWithClass:@"badge badge-destructive" text:@"Error"];
}

+ (NSString *)connectionBadge:(nullable NSString *)status {
    NSString *display = status.length > 0 ? status : @"unknown";
    NSString *normalized = display.lowercaseString;
    NSString *className = @"badge badge-secondary";
    if ([normalized isEqualToString:@"connected"] || [normalized isEqualToString:@"running"] || [normalized isEqualToString:@"online"]) {
        className = @"badge badge-success";
    } else if ([normalized isEqualToString:@"error"] || [normalized isEqualToString:@"failed"]) {
        className = @"badge badge-destructive";
    }
    return [self badgeWithClass:className text:display];
}

+ (NSString *)monoValue:(nullable id)value {
    NSString *text = @"—";
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        text = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        text = [value description];
    } else if (value && value != [NSNull null]) {
        text = [value description];
    }
    return [self element:@"span" attributes:@{@"class": @"text-mono"} children:@[[self escapedString:text]]];
}

+ (NSString *)sectionTitle:(NSString *)title {
    return [NSString stringWithFormat:@"<h3 class=\"section-title\">%@</h3>", [self escapedString:title]];
}

+ (NSString *)tableCellWithText:(NSString *)text className:(nullable NSString *)className {
    return [self tableCellWithHTML:[self escapedString:text] className:className];
}

+ (NSString *)tableCellWithHTML:(NSString *)html className:(nullable NSString *)className {
    if (className.length > 0) {
        return [NSString stringWithFormat:@"<td class=\"%@\">%@</td>",
                [self escapedString:className], html ?: @""];
    }
    return [NSString stringWithFormat:@"<td>%@</td>", html ?: @""];
}

+ (NSString *)buttonRowWithButtons:(NSArray<NSString *> *)buttons {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"button-row\">"];
    for (NSString *button in buttons) {
        if (button.length > 0) {
            [html appendString:button];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)formatUptime:(int64_t)seconds {
    if (seconds < 0) seconds = 0;
    int64_t hours = seconds / 3600;
    int64_t mins = (seconds % 3600) / 60;
    return [NSString stringWithFormat:@"%lldh %lldm", (long long)hours, (long long)mins];
}

+ (NSString *)formatMegabytes:(int64_t)bytes {
    return [NSString stringWithFormat:@"%lld MB", (long long)(bytes / (1024 * 1024))];
}

#pragma mark - Private

+ (void)appendAttributes:(nullable NSDictionary<NSString *, NSString *> *)attributes
                toString:(NSMutableString *)html {
    // Sort keys for deterministic output. This is not strictly required by HTML
    // but makes test assertions and diff output stable.
    NSArray<NSString *> *sortedKeys = [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        NSString *value = attributes[key];
        if (value.length == 0) {
            // Boolean attribute: render name only, no ="".
            [html appendFormat:@" %@", key];
        } else {
            [html appendFormat:@" %@=\"%@\"", key, [self escapedString:value]];
        }
    }
}

@end
