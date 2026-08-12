// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZHTMLTests.m

 @abstract Unit tests for GZHTML.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AdminUIServer/GZHTML.h"

@interface GZHTMLTests : XCTestCase
@end

@implementation GZHTMLTests

#pragma mark - Escaping

- (void)testEscapedStringHandlesNil {
    XCTAssertEqualObjects([GZHTML escapedString:nil], @"");
}

- (void)testEscapedStringHandlesEmptyString {
    XCTAssertEqualObjects([GZHTML escapedString:@""], @"");
}

- (void)testEscapedStringReplacesAmpersand {
    XCTAssertEqualObjects([GZHTML escapedString:@"a&b"], @"a&amp;b");
}

- (void)testEscapedStringReplacesLessThan {
    XCTAssertEqualObjects([GZHTML escapedString:@"a<b"], @"a&lt;b");
}

- (void)testEscapedStringReplacesGreaterThan {
    XCTAssertEqualObjects([GZHTML escapedString:@"a>b"], @"a&gt;b");
}

- (void)testEscapedStringReplacesDoubleQuote {
    XCTAssertEqualObjects([GZHTML escapedString:@"\"hi\""], @"&quot;hi&quot;");
}

- (void)testEscapedStringReplacesSingleQuote {
    XCTAssertEqualObjects([GZHTML escapedString:@"it's"], @"it&#39;s");
}

- (void)testEscapedStringDoesNotDoubleEscape {
    XCTAssertEqualObjects([GZHTML escapedString:@"&amp;"], @"&amp;amp;");
}

- (void)testEscapedStringHandlesAllFiveTogether {
    XCTAssertEqualObjects([GZHTML escapedString:@"<a href=\"x\" data-y='z'>&"],
                         @"&lt;a href=&quot;x&quot; data-y=&#39;z&#39;&gt;&amp;");
}

- (void)testTextEscapesContent {
    XCTAssertEqualObjects([GZHTML text:@"<script>alert(1)</script>"],
                         @"&lt;script&gt;alert(1)&lt;/script&gt;");
}

- (void)testRawReturnsInputUnchanged {
    XCTAssertEqualObjects([GZHTML raw:@"<b>bold</b>"], @"<b>bold</b>");
}

- (void)testRawHandlesNil {
    NSString *result = [GZHTML raw:nil];
    XCTAssertEqualObjects(result, @"");
}

#pragma mark - Element Construction

- (void)testElementWithNoAttributesOrChildren {
    XCTAssertEqualObjects([GZHTML element:@"div" attributes:nil children:nil], @"<div></div>");
}

- (void)testElementWithAttributes {
    NSDictionary *attrs = @{@"class": @"alert"};
    XCTAssertEqualObjects([GZHTML element:@"div" attributes:attrs children:nil],
                         @"<div class=\"alert\"></div>");
}

- (void)testElementWithChildren {
    NSArray *children = @[@"hello"];
    XCTAssertEqualObjects([GZHTML element:@"p" attributes:nil children:children],
                         @"<p>hello</p>");
}

- (void)testElementWithMultipleChildren {
    NSArray *children = @[@"a", @"b"];
    XCTAssertEqualObjects([GZHTML element:@"div" attributes:nil children:children],
                         @"<div>ab</div>");
}

- (void)testElementEscapesAttributeValues {
    NSDictionary *attrs = @{@"title": @"x\"y"};
    NSString *result = [GZHTML element:@"div" attributes:attrs children:nil];
    XCTAssertEqualObjects(result, @"<div title=\"x&quot;y\"></div>");
}

- (void)testElementDoesNotEscapeChildren {
    // Children are treated as already-rendered HTML — not escaped.
    NSArray *children = @[@"<b>raw</b>"];
    XCTAssertEqualObjects([GZHTML element:@"div" attributes:nil children:children],
                         @"<div><b>raw</b></div>");
}

- (void)testElementWithBooleanAttribute {
    NSDictionary *attrs = @{@"disabled": @""};
    NSString *result = [GZHTML element:@"input" attributes:attrs children:nil];
    XCTAssertEqualObjects(result, @"<input disabled></input>");
}

- (void)testElementAttributesAreSorted {
    NSDictionary *attrs = @{@"z": @"1", @"a": @"2", @"m": @"3"};
    NSString *result = [GZHTML element:@"div" attributes:attrs children:nil];
    XCTAssertEqualObjects(result, @"<div a=\"2\" m=\"3\" z=\"1\"></div>");
}

- (void)testVoidElement {
    XCTAssertEqualObjects([GZHTML voidElement:@"br" attributes:nil], @"<br/>");
}

- (void)testVoidElementWithAttributes {
    NSDictionary *attrs = @{@"type": @"text", @"name": @"q"};
    XCTAssertEqualObjects([GZHTML voidElement:@"input" attributes:attrs],
                         @"<input name=\"q\" type=\"text\"/>");
}

- (void)testVoidElementEscapesAttributeValues {
    NSDictionary *attrs = @{@"alt": @"x\"y"};
    XCTAssertEqualObjects([GZHTML voidElement:@"img" attributes:attrs],
                         @"<img alt=\"x&quot;y\"/>");
}

#pragma mark - Compound: Alert

- (void)testAlertDestructive {
    XCTAssertEqualObjects([GZHTML alertWithType:@"destructive" message:@"Error occurred"],
                         @"<div class=\"alert alert-destructive\">Error occurred</div>");
}

- (void)testAlertSuccess {
    XCTAssertEqualObjects([GZHTML alertWithType:@"success" message:@"Saved"],
                         @"<div class=\"alert alert-success\">Saved</div>");
}

- (void)testAlertEscapesMessage {
    XCTAssertEqualObjects([GZHTML alertWithType:@"destructive" message:@"<script>"],
                         @"<div class=\"alert alert-destructive\">&lt;script&gt;</div>");
}

- (void)testAlertEscapesType {
    XCTAssertEqualObjects([GZHTML alertWithType:@"x\">y" message:@"ok"],
                         @"<div class=\"alert alert-x&quot;&gt;y\">ok</div>");
}

#pragma mark - Compound: Table

- (void)testTableWithHeadersAndRows {
    NSArray *headers = @[@"Name", @"Handle"];
    NSArray *rows = @[@[@"Alice", @"@alice"], @[@"Bob", @"@bob"]];
    NSString *result = [GZHTML tableWithHeaders:headers rows:rows emptyMessage:@"No data"];
    XCTAssertEqualObjects(result,
                         @"<table class=\"table\"><thead><tr><th>Name</th><th>Handle</th></tr></thead>"
                         @"<tbody><tr><td>Alice</td><td>@alice</td></tr>"
                         @"<tr><td>Bob</td><td>@bob</td></tr>"
                         @"</tbody></table>");
}

- (void)testTableWithEmptyRowsShowsEmptyMessage {
    NSArray *headers = @[@"A", @"B"];
    NSString *result = [GZHTML tableWithHeaders:headers rows:nil emptyMessage:@"Nothing here"];
    XCTAssertEqualObjects(result,
                         @"<table class=\"table\"><thead><tr><th>A</th><th>B</th></tr></thead>"
                         @"<tbody><tr><td colspan=\"2\" class=\"text-center text-secondary p-lg\">"
                         @"Nothing here</td></tr></tbody></table>");
}

- (void)testTableEscapesHeadersAndCells {
    NSArray *headers = @[@"<th>"];
    NSArray *rows = @[@[@"<td>"]];
    NSString *result = [GZHTML tableWithHeaders:headers rows:rows emptyMessage:@"unused"];
    XCTAssertTrue([result containsString:@"&lt;th&gt;"]);
    XCTAssertTrue([result containsString:@"&lt;td&gt;"]);
    XCTAssertFalse([result containsString:@"unused"]);

    NSString *empty = [GZHTML tableWithHeaders:headers rows:nil emptyMessage:@"<x>"];
    XCTAssertTrue([empty containsString:@"&lt;x&gt;"]);
}

- (void)testTableWithHtmlRows {
    NSArray *headers = @[@"DID"];
    NSArray *htmlRows = @[@"<tr><td>did:plc:abc</td></tr>"];
    NSString *result = [GZHTML tableWithHeaders:headers htmlRows:htmlRows emptyMessage:@"No entries"];
    XCTAssertEqualObjects(result,
                         @"<table class=\"table\"><thead><tr><th>DID</th></tr></thead>"
                         @"<tbody><tr><td>did:plc:abc</td></tr>"
                         @"</tbody></table>");
}

- (void)testTableWithHtmlRowsEmptyShowsEmptyMessage {
    NSArray *headers = @[@"A"];
    NSString *result = [GZHTML tableWithHeaders:headers htmlRows:nil emptyMessage:@"Empty"];
    XCTAssertTrue([result containsString:@"colspan=\"1\""]);
    XCTAssertTrue([result containsString:@"Empty"]);
}

#pragma mark - Compound: Table Row

- (void)testTableRowWithCells {
    NSArray *cells = @[@"a", @"b"];
    XCTAssertEqualObjects([GZHTML tableRowWithCells:cells],
                         @"<tr><td>a</td><td>b</td></tr>");
}

- (void)testTableRowWithCellsEscapes {
    NSArray *cells = @[@"<b>"];
    XCTAssertEqualObjects([GZHTML tableRowWithCells:cells],
                         @"<tr><td>&lt;b&gt;</td></tr>");
}

- (void)testTableRowWithHtmlCells {
    NSArray *cells = @[@"<b>x</b>"];
    XCTAssertEqualObjects([GZHTML tableRowWithHtmlCells:cells],
                         @"<tr><td><b>x</b></td></tr>");
}

#pragma mark - Compound: Empty State Row

- (void)testEmptyStateRow {
    XCTAssertEqualObjects([GZHTML emptyStateRowWithColspan:4 message:@"No data"],
                         @"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No data</td></tr>");
}

- (void)testEmptyStateRowEscapesMessage {
    XCTAssertEqualObjects([GZHTML emptyStateRowWithColspan:1 message:@"<b>"],
                         @"<tr><td colspan=\"1\" class=\"text-center text-secondary p-lg\">&lt;b&gt;</td></tr>");
}

#pragma mark - Compound: Detail Grid

- (void)testDetailGridWithFields {
    NSArray *fields = @[
        @{@"label": @"DID", @"value": @"did:plc:abc"},
        @{@"label": @"Handle", @"value": @"@alice"},
    ];
    NSString *result = [GZHTML detailGridWithFields:fields];
    XCTAssertEqualObjects(result,
                         @"<div class=\"detail-grid\">"
                         @"<div class=\"detail-field\"><span class=\"detail-label\">DID</span>"
                         @"<span class=\"detail-value\">did:plc:abc</span></div>"
                         @"<div class=\"detail-field\"><span class=\"detail-label\">Handle</span>"
                         @"<span class=\"detail-value\">@alice</span></div>"
                         @"</div>");
}

- (void)testDetailGridWithFullWidthField {
    NSArray *fields = @[
        @{@"label": @"JSON", @"value": @"{}", @"fullWidth": @"true"},
    ];
    NSString *result = [GZHTML detailGridWithFields:fields];
    XCTAssertTrue([result containsString:@"detail-field full-width"]);
}

- (void)testDetailGridEscapesValues {
    NSArray *fields = @[
        @{@"label": @"<x>", @"value": @"\"y\""},
    ];
    NSString *result = [GZHTML detailGridWithFields:fields];
    XCTAssertTrue([result containsString:@"&lt;x&gt;"]);
    XCTAssertTrue([result containsString:@"&quot;y&quot;"]);
}

#pragma mark - Compound: Metric Row

- (void)testMetricRow {
    NSArray *metrics = @[
        @{@"label": @"Repos", @"value": @"42"},
        @{@"label": @"Records", @"value": @"100"},
    ];
    NSString *result = [GZHTML metricRowWithMetrics:metrics];
    XCTAssertEqualObjects(result,
                         @"<div class=\"metric-row\">"
                         @"<div class=\"metric\"><span class=\"metric-label\">Repos</span>"
                         @"<span class=\"metric-value\">42</span></div>"
                         @"<div class=\"metric\"><span class=\"metric-label\">Records</span>"
                         @"<span class=\"metric-value\">100</span></div>"
                         @"</div>");
}

- (void)testMetricRowEscapesValues {
    NSArray *metrics = @[
        @{@"label": @"<x>", @"value": @"\"y\""},
    ];
    NSString *result = [GZHTML metricRowWithMetrics:metrics];
    XCTAssertTrue([result containsString:@"&lt;x&gt;"]);
    XCTAssertTrue([result containsString:@"&quot;y&quot;"]);
}

#pragma mark - Compound: Badge

- (void)testBadge {
    XCTAssertEqualObjects([GZHTML badgeWithClass:@"badge badge-success" text:@"active"],
                         @"<span class=\"badge badge-success\">active</span>");
}

- (void)testBadgeEscapes {
    XCTAssertEqualObjects([GZHTML badgeWithClass:@"badge\"x" text:@"<b>"],
                         @"<span class=\"badge&quot;x\">&lt;b&gt;</span>");
}

#pragma mark - Compound: Pagination Button

- (void)testPaginationButton {
    NSString *result = [GZHTML paginationButtonWithHref:@"/admin/partials/audit-log?cursor=abc"
                                                target:@"#audit-log-content"
                                                 label:@"Load more"];
    XCTAssertEqualObjects(result,
                         @"<div class=\"d-flex justify-between mt-sm\">"
                         @"<button class=\"btn btn-secondary btn-sm\" "
                         @"hx-get=\"/admin/partials/audit-log?cursor=abc\" "
                         @"hx-target=\"#audit-log-content\">Load more</button>"
                         @"</div>");
}

- (void)testPaginationButtonEscapes {
    NSString *result = [GZHTML paginationButtonWithHref:@"?x=\"&"
                                                target:@"#x"
                                                 label:@"<b>"];
    XCTAssertTrue([result containsString:@"&quot;"]);
    XCTAssertTrue([result containsString:@"&amp;"]);
    XCTAssertTrue([result containsString:@"&lt;b&gt;"]);
}

#pragma mark - Compound: Section

- (void)testSectionWithDefaultClass {
    NSString *result = [GZHTML sectionWithTitle:@"Reports" content:@"<div>content</div>" className:nil];
    XCTAssertEqualObjects(result,
                         @"<section class=\"mt-lg\"><h3 class=\"section-title\">Reports</h3>"
                         @"<div>content</div></section>");
}

- (void)testSectionWithCustomClass {
    NSString *result = [GZHTML sectionWithTitle:@"Data" content:@"body" className:@"custom-class"];
    XCTAssertTrue([result containsString:@"class=\"custom-class\""]);
}

- (void)testSectionEscapesTitle {
    NSString *result = [GZHTML sectionWithTitle:@"<x>" content:@"" className:nil];
    XCTAssertTrue([result containsString:@"&lt;x&gt;"]);
}

#pragma mark - Compound: Button

- (void)testButtonWithAction {
    XCTAssertEqualObjects([GZHTML buttonWithClass:@"btn btn-primary" text:@"Save" action:@"save" data:nil],
                         @"<button class=\"btn btn-primary\" data-ui-action=\"save\">Save</button>");
}

- (void)testButtonWithDataAttributes {
    NSDictionary *data = @{@"did": @"did:plc:abc"};
    NSString *result = [GZHTML buttonWithClass:@"btn btn-destructive" text:@"Delete"
                                         action:@"delete-account" data:data];
    XCTAssertEqualObjects(result,
                         @"<button class=\"btn btn-destructive\" data-ui-action=\"delete-account\" "
                         @"data-did=\"did:plc:abc\">Delete</button>");
}

- (void)testButtonEscapesAllValues {
    NSDictionary *data = @{@"k": @"v\"z"};
    NSString *result = [GZHTML buttonWithClass:@"cls\"x" text:@"<b>" action:@"act\"y" data:data];
    XCTAssertTrue([result containsString:@"cls&quot;x"]);
    XCTAssertTrue([result containsString:@"&lt;b&gt;"]);
    XCTAssertTrue([result containsString:@"act&quot;y"]);
    XCTAssertTrue([result containsString:@"v&quot;z"]);
}

#pragma mark - Compound: Input

- (void)testInputWithAllAttributes {
    NSString *result = [GZHTML inputWithType:@"text" name:@"q" placeholder:@"Search..." value:@"hello" className:@"form-input"];
    XCTAssertEqualObjects(result,
                         @"<input class=\"form-input\" name=\"q\" placeholder=\"Search...\" type=\"text\" value=\"hello\"/>");
}

- (void)testInputWithoutOptionalAttributes {
    NSString *result = [GZHTML inputWithType:@"checkbox" name:@"agree" placeholder:nil value:nil className:nil];
    XCTAssertEqualObjects(result, @"<input name=\"agree\" type=\"checkbox\"/>");
}

- (void)testInputEscapesValues {
    NSString *result = [GZHTML inputWithType:@"text" name:@"x\"y" placeholder:nil value:nil className:nil];
    XCTAssertTrue([result containsString:@"x&quot;y"]);
}

#pragma mark - Compound: Link

- (void)testLinkWithClass {
    // Attributes are emitted in sorted key order (class before href).
    XCTAssertEqualObjects([GZHTML linkWithHref:@"/admin/login" text:@"Sign in" className:@"nav-link"],
                         @"<a class=\"nav-link\" href=\"/admin/login\">Sign in</a>");
}

- (void)testLinkWithoutClass {
    XCTAssertEqualObjects([GZHTML linkWithHref:@"/admin" text:@"Home" className:nil],
                         @"<a href=\"/admin\">Home</a>");
}

- (void)testLinkEscapes {
    NSString *result = [GZHTML linkWithHref:@"?x=\"&" text:@"<b>" className:nil];
    XCTAssertTrue([result containsString:@"&quot;"]);
    XCTAssertTrue([result containsString:@"&amp;"]);
    XCTAssertTrue([result containsString:@"&lt;b&gt;"]);
}

#pragma mark - Product dashboard primitives

- (void)testDetailCardWithFields {
    NSString *result = [GZHTML detailCardWithFields:@[
        @{@"label": @"Status", @"html": [GZHTML healthBadge:@"ok"]},
        @{@"label": @"Uptime", @"value": @"1h 2m"},
    ]];
    XCTAssertTrue([result hasPrefix:@"<div class=\"detail-card\">"]);
    XCTAssertTrue([result containsString:@"detail-label"]);
    XCTAssertTrue([result containsString:@"badge badge-success"]);
    XCTAssertTrue([result containsString:@"1h 2m"]);
    XCTAssertTrue([result hasSuffix:@"</div>"]);
}

- (void)testHealthBadgeVariants {
    XCTAssertEqualObjects([GZHTML healthBadge:@"healthy"],
                         @"<span class=\"badge badge-success\">Healthy</span>");
    XCTAssertEqualObjects([GZHTML healthBadge:@"degraded"],
                         @"<span class=\"badge badge-warning\">Degraded</span>");
    XCTAssertEqualObjects([GZHTML healthBadge:@"boom"],
                         @"<span class=\"badge badge-destructive\">Error</span>");
}

- (void)testConnectionBadgeVariants {
    XCTAssertTrue([[GZHTML connectionBadge:@"connected"] containsString:@"badge-success"]);
    XCTAssertTrue([[GZHTML connectionBadge:@"disconnected"] containsString:@"badge-secondary"]);
    XCTAssertTrue([[GZHTML connectionBadge:@"error"] containsString:@"badge-destructive"]);
}

- (void)testMonoValueFormatsNumbersAndNil {
    XCTAssertEqualObjects([GZHTML monoValue:@42], @"<span class=\"text-mono\">42</span>");
    XCTAssertEqualObjects([GZHTML monoValue:nil], @"<span class=\"text-mono\">—</span>");
}

- (void)testSectionTitleEscapes {
    XCTAssertEqualObjects([GZHTML sectionTitle:@"<x>"],
                         @"<h3 class=\"section-title\">&lt;x&gt;</h3>");
}

- (void)testTableCellHelpers {
    XCTAssertEqualObjects([GZHTML tableCellWithText:@"9" className:@"text-right text-mono"],
                         @"<td class=\"text-right text-mono\">9</td>");
    XCTAssertEqualObjects([GZHTML tableCellWithHTML:@"<b>1</b>" className:nil],
                         @"<td><b>1</b></td>");
}

- (void)testButtonRow {
    NSString *result = [GZHTML buttonRowWithButtons:@[
        [GZHTML buttonWithClass:@"btn" text:@"A" action:@"a" data:nil],
    ]];
    XCTAssertTrue([result hasPrefix:@"<div class=\"button-row\">"]);
    XCTAssertTrue([result containsString:@"data-ui-action=\"a\""]);
}

- (void)testFormatHelpers {
    XCTAssertEqualObjects([GZHTML formatUptime:3661], @"1h 1m");
    XCTAssertEqualObjects([GZHTML formatMegabytes:2 * 1024 * 1024], @"2 MB");
}

@end
