// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Lightweight server-side HTML generation utility for the admin UI.
 * @discussion GZHTML provides stateless class methods that produce HTML strings with automatic
 * escaping of text content and attribute values. It replaces the duplicated escaping functions
 * scattered across the admin UI server and offers compound element builders for the repeated
 * patterns in the codebase (alerts, tables, detail grids, metric rows, badges, pagination,
 * sections, buttons, inputs).
 *
 * Design principles:
 * - Auto-escaping is the default. Use +text: for text content; use +raw: only for pre-rendered
 *   HTML (e.g. template engine output or nested GZHTML calls).
 * - Children passed to +element:attributes:children: are treated as already-rendered HTML.
 *   Wrap text in +text: to get escaping. This matches the template engine convention where
 *   triple-brace output is raw and double-brace is escaped.
 * - All compound element builders escape their string parameters internally.
 * - The class is stateless; methods are safe to call from any thread.
 */
@interface GZHTML : NSObject

/// @name Escaping

/**
 * @abstract Escapes a string for safe insertion into HTML text content or attribute values.
 * @discussion Replaces & < > " ' with their HTML entity references. Returns an empty string
 * for nil input. This is the canonical escaping function for the admin UI — it supersedes
 * both GZAdminUIEscaped() and the static EscapeHTML() in UITemplateEngine.
 * @param string The string to escape, or nil.
 * @return The escaped string, or @"" if string is nil.
 */
+ (NSString *)escapedString:(nullable NSString *)string;

/**
 * @abstract Returns an HTML-escaped text node.
 * @discussion Use this for text content that should be treated as plain text, not HTML markup.
 * The returned string is safe to pass as a child to +element:attributes:children:.
 * @param text The text to escape.
 * @return The escaped text string.
 */
+ (NSString *)text:(NSString *)text;

/**
 * @abstract Returns raw HTML without escaping.
 * @discussion This is an explicit opt-out from escaping. Use it for pre-rendered HTML such as
 * template engine output or nested GZHTML element calls. The returned string is safe to pass
 * as a child to +element:attributes:children:.
 * @param html The raw HTML string.
 * @return The input string unchanged.
 */
+ (NSString *)raw:(nullable NSString *)html;

/// @name Element Construction

/**
 * @abstract Builds an HTML element with attributes and children.
 * @discussion Children are treated as already-rendered HTML — they are not escaped. Wrap text
 * content in +text: for escaping. Void elements (br, img, input, hr, etc.) should use
 * +voidElement:attributes: instead; passing nil children to a void element produces a self-closing
 * tag, but the void method is preferred for clarity.
 *
 * Boolean attributes (disabled, hidden, checked, etc.) should be passed with an empty string value:
 * @{@"hidden": @""}. The builder omits the ="" and renders just the attribute name.
 *
 * @param tag The element tag name (e.g. @"div", @"span", @"table").
 * @param attributes A dictionary of attribute name → value pairs. Values are HTML-escaped.
 *                   Pass nil for no attributes. Boolean attributes use @"" as the value.
 * @param children An array of already-rendered HTML strings. Pass nil for no children.
 * @return The rendered HTML element string.
 */
+ (NSString *)element:(NSString *)tag
            attributes:(nullable NSDictionary<NSString *, NSString *> *)attributes
              children:(nullable NSArray<NSString *> *)children;

/**
 * @abstract Builds a void (self-closing) HTML element.
 * @discussion Use this for elements that cannot have children: input, br, img, hr, meta, link.
 * @param tag The element tag name.
 * @param attributes A dictionary of attribute name → value pairs. Values are HTML-escaped.
 *                   Pass nil for no attributes.
 * @return The rendered void element string (e.g. @"<input type=\"text\"/>").
 */
+ (NSString *)voidElement:(NSString *)tag
                attributes:(nullable NSDictionary<NSString *, NSString *> *)attributes;

/// @name Compound Elements

/**
 * @abstract Builds an alert box.
 * @discussion Produces: <div class="alert alert-{type}">{escaped message}</div>
 * Common types: @"destructive", @"success", @"warning", @"info".
 * @param type The alert type, inserted into the class name after "alert-".
 * @param message The alert message. HTML-escaped.
 * @return The rendered alert HTML.
 */
+ (NSString *)alertWithType:(NSString *)type message:(NSString *)message;

/**
 * @abstract Builds a data table with headers, text rows, and an empty-state message.
 * @discussion Produces a <table class="table"> with <thead> and <tbody>. Each row is an array
 * of cell values (strings). All values are HTML-escaped. When rows is empty or nil, an
 * empty-state row spanning all columns is rendered.
 *
 * For tables that need non-text cells (checkboxes, buttons, selects), use
 * +tableWithHeaders:htmlRows:emptyMessage: instead.
 *
 * @param headers Column header strings. HTML-escaped.
 * @param rows An array of rows, each row being an array of cell value strings. HTML-escaped.
 *             Pass nil for no rows (renders empty state).
 * @param emptyMessage Message shown when rows is empty. HTML-escaped.
 * @return The rendered table HTML.
 */
+ (NSString *)tableWithHeaders:(NSArray<NSString *> *)headers
                          rows:(nullable NSArray<NSArray<NSString *> *> *)rows
                  emptyMessage:(NSString *)emptyMessage;

/**
 * @abstract Builds a data table with pre-rendered HTML rows.
 * @discussion Produces a <table class="table"> with <thead> and <tbody>. Headers are HTML-escaped.
 * Row content is inserted raw — the caller is responsible for escaping cell content. Use this
 * variant when rows contain form controls, links, or other HTML elements.
 * @param headers Column header strings. HTML-escaped.
 * @param htmlRows An array of pre-rendered <tr>...</tr> strings. Inserted raw.
 *                  Pass nil for no rows (renders empty state).
 * @param emptyMessage Message shown when htmlRows is empty. HTML-escaped.
 * @return The rendered table HTML.
 */
+ (NSString *)tableWithHeaders:(NSArray<NSString *> *)headers
                       htmlRows:(nullable NSArray<NSString *> *)htmlRows
                  emptyMessage:(NSString *)emptyMessage;

/**
 * @abstract Builds a table row (<tr>) with text cells.
 * @discussion Each cell value is HTML-escaped and wrapped in <td>. For cells that need custom
 * HTML (attributes, nested elements), use +tableRowWithHtmlCells: instead.
 * @param cells An array of cell value strings. HTML-escaped.
 * @return The rendered <tr> HTML.
 */
+ (NSString *)tableRowWithCells:(NSArray<NSString *> *)cells;

/**
 * @abstract Builds a table row (<tr>) with pre-rendered HTML cells.
 * @discussion Each string in the array is inserted as raw HTML inside a <td>. The caller is
 * responsible for escaping cell content.
 * @param htmlCells An array of pre-rendered HTML cell strings.
 * @return The rendered <tr> HTML.
 */
+ (NSString *)tableRowWithHtmlCells:(NSArray<NSString *> *)htmlCells;

/**
 * @abstract Builds an empty-state table row.
 * @discussion Produces: <tr><td colspan="{colspan}" class="text-center text-secondary p-lg">{message}</td></tr>
 * @param colspan Number of columns the empty row should span.
 * @param message The empty state message. HTML-escaped.
 * @return The rendered empty-state row HTML.
 */
+ (NSString *)emptyStateRowWithColspan:(NSUInteger)colspan
                                message:(NSString *)message;

/**
 * @abstract Builds a detail grid with label/value field pairs.
 * @discussion Produces a <div class="detail-grid"> containing detail-field divs. Each field
 * dictionary should contain @"label" and @"value" keys. Both are HTML-escaped. An optional
 * @"fullWidth" key with value @"true" adds the "full-width" class to the field.
 * @param fields An array of field dictionaries with @"label" and @"value" keys.
 * @return The rendered detail grid HTML.
 */
+ (NSString *)detailGridWithFields:(NSArray<NSDictionary<NSString *, NSString *> *> *)fields;

/**
 * @abstract Builds a metric row with label/value metric cards.
 * @discussion Produces a <div class="metric-row"> containing metric divs. Each metric
 * dictionary should contain @"label" and @"value" keys. Both are HTML-escaped.
 * @param metrics An array of metric dictionaries with @"label" and @"value" keys.
 * @return The rendered metric row HTML.
 */
+ (NSString *)metricRowWithMetrics:(NSArray<NSDictionary<NSString *, NSString *> *> *)metrics;

/**
 * @abstract Builds a badge span.
 * @discussion Produces: <span class="{className}">{escaped text}</span>
 * @param className The CSS class(es) for the badge (e.g. @"badge badge-success").
 * @param text The badge text. HTML-escaped.
 * @return The rendered badge HTML.
 */
+ (NSString *)badgeWithClass:(NSString *)className text:(NSString *)text;

/**
 * @abstract Builds an HTMX-powered pagination "Load more" button.
 * @discussion Produces a button that fetches the next page via HTMX. The href is URL-encoded
 * for the hx-get attribute; the label is HTML-escaped.
 * @param href The HTMX fetch URL (e.g. @"/admin/partials/audit-log?cursor=abc").
 * @param target The HTMX target selector (e.g. @"#audit-log-content").
 * @param label The button label text (e.g. @"Load more"). HTML-escaped.
 * @return The rendered pagination button HTML.
 */
+ (NSString *)paginationButtonWithHref:(NSString *)href
                                target:(NSString *)target
                                 label:(NSString *)label;

/**
 * @abstract Builds a section with a title heading and content.
 * @discussion Produces: <section class="{className or "mt-lg"}"><h3 class="section-title">{title}</h3>{content}</section>
 * @param title The section title. HTML-escaped.
 * @param content The section body HTML. Inserted raw — use GZHTML builders or +text: for content.
 * @param className Additional CSS class for the section element, or nil for default @"mt-lg".
 * @return The rendered section HTML.
 */
+ (NSString *)sectionWithTitle:(NSString *)title
                       content:(NSString *)content
                    className:(nullable NSString *)className;

/**
 * @abstract Builds a button with data attributes.
 * @discussion Produces: <button class="{className}" data-ui-action="{action}" [data-*="{value}"]>{text}</button>
 * Data attribute keys in the data dictionary are prefixed with "data-". Both attribute values
 * and the button text are HTML-escaped.
 * @param className The CSS class(es) for the button (e.g. @"btn btn-primary btn-sm").
 * @param text The button label. HTML-escaped.
 * @param action The data-ui-action value. HTML-escaped.
 * @param data Additional data attributes. Keys are used as-is (without "data-" prefix).
 *             Values are HTML-escaped. Pass nil for no additional data attributes.
 * @return The rendered button HTML.
 */
+ (NSString *)buttonWithClass:(NSString *)className
                         text:(NSString *)text
                       action:(NSString *)action
                         data:(nullable NSDictionary<NSString *, NSString *> *)data;

/**
 * @abstract Builds a form input element.
 * @discussion Produces: <input type="{type}" name="{name}" placeholder="{placeholder}" value="{value}" class="{className}"/>
 * All attribute values are HTML-escaped. The value attribute is omitted when nil or empty.
 * @param type The input type (e.g. @"text", @"checkbox", @"hidden").
 * @param name The input name attribute. HTML-escaped.
 * @param placeholder The placeholder text. HTML-escaped. Pass nil to omit.
 * @param value The input value. HTML-escaped. Pass nil to omit.
 * @param className The CSS class(es). Pass nil to omit.
 * @return The rendered input element HTML.
 */
+ (NSString *)inputWithType:(NSString *)type
                        name:(NSString *)name
                 placeholder:(nullable NSString *)placeholder
                       value:(nullable NSString *)value
                    className:(nullable NSString *)className;

/**
 * @abstract Builds a hyperlink element.
 * @discussion Produces: <a href="{href}" class="{className}">{text}</a>
 * The href and text are HTML-escaped.
 * @param href The link URL. HTML-escaped.
 * @param text The link text. HTML-escaped.
 * @param className The CSS class(es). Pass nil to omit.
 * @return The rendered anchor HTML.
 */
+ (NSString *)linkWithHref:(NSString *)href
                      text:(NSString *)text
                  className:(nullable NSString *)className;

/// @name Product dashboard primitives
/// Preferred over metric-row for operator dashboards after the 2026 redesign.

/**
 * @abstract Builds a stacked detail card of label/value rows.
 * @discussion Produces <div class="detail-card">…</div>. Each field dictionary may include:
 * - @"label" (required, escaped)
 * - @"value" (escaped plain text), or
 * - @"html" (trusted pre-rendered value markup, e.g. a badge)
 * Prefer @"html" when the value is a badge or mono span from another GZHTML helper.
 * @param fields Field dictionaries.
 * @return The rendered detail-card HTML.
 */
+ (NSString *)detailCardWithFields:(NSArray<NSDictionary<NSString *, NSString *> *> *)fields;

/**
 * @abstract Opening tag for an incrementally built detail card.
 * @discussion Prefer +detailCardWithFields: when all rows are known up front.
 */
+ (NSString *)detailCardOpening;

/** @abstract Closing tag for an incrementally built detail card. */
+ (NSString *)detailCardClosing;

/**
 * @abstract Builds one detail-card row with a trusted HTML value.
 * @param label Escaped label text.
 * @param valueHTML Trusted markup for the value cell (use +monoValue: / +healthBadge: / +text:).
 * @return The rendered detail-row HTML.
 */
+ (NSString *)detailRowWithLabel:(NSString *)label valueHTML:(nullable NSString *)valueHTML;

/**
 * @abstract Builds a semantic health badge for ok/healthy/degraded/error states.
 * @param health Raw health string from a snapshot. Case-insensitive.
 * @return Badge HTML with success/warning/destructive classes.
 */
+ (NSString *)healthBadge:(nullable NSString *)health;

/**
 * @abstract Builds a semantic connection/status badge.
 * @param status Raw status (connected, running, disconnected, error, …).
 * @return Badge HTML; text is the original status string (escaped).
 */
+ (NSString *)connectionBadge:(nullable NSString *)status;

/**
 * @abstract Builds a monospace span for IDs, counts, URLs, and other exact values.
 * @param value String, number, or description-able object. Nil becomes "—".
 * @return Escaped mono span HTML.
 */
+ (NSString *)monoValue:(nullable id)value;

/**
 * @abstract Builds a standalone section title (h3.section-title).
 * @param title Escaped title text.
 * @return The heading HTML without a wrapping section.
 */
+ (NSString *)sectionTitle:(NSString *)title;

/**
 * @abstract Builds a table cell with optional CSS class.
 * @param text Escaped cell text.
 * @param className Optional class (e.g. @"text-right text-mono"). Nil omits class.
 * @return The <td> HTML.
 */
+ (NSString *)tableCellWithText:(NSString *)text className:(nullable NSString *)className;

/**
 * @abstract Builds a table cell containing trusted HTML with an optional class.
 * @param html Trusted cell markup.
 * @param className Optional class. Nil omits class.
 * @return The <td> HTML.
 */
+ (NSString *)tableCellWithHTML:(NSString *)html className:(nullable NSString *)className;

/**
 * @abstract Builds a horizontal button/action row.
 * @param buttons Pre-rendered button HTML strings (from +buttonWithClass:…).
 * @return A div.button-row wrapping the buttons.
 */
+ (NSString *)buttonRowWithButtons:(NSArray<NSString *> *)buttons;

/**
 * @abstract Formats uptime seconds as `Nh Nm` for operator displays.
 */
+ (NSString *)formatUptime:(int64_t)seconds;

/**
 * @abstract Formats a byte count as `N MB` for storage pressure displays.
 */
+ (NSString *)formatMegabytes:(int64_t)bytes;

@end

NS_ASSUME_NONNULL_END
