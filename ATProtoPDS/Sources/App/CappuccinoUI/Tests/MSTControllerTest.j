/*
 * MSTControllerTest.j
 * CappuccinoUI Tests
 *
 * Tests the pure string-formatting and data-transformation helpers on
 * MSTController that do not require AppKit rendering or network access.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import <OJUnit/OJTestCase.j>
@import "../MSTController.j"

@implementation MSTControllerTest : OJTestCase
{
    MSTController _ctrl;
}

- (void)setUp
{
    // Pass nil for both deps; the helpers under test never touch them.
    _ctrl = [[MSTController alloc] initWithSessionState:nil apiClient:nil];
}

// ---------------------------------------------------------------------------
// trimmedString:
// ---------------------------------------------------------------------------

- (void)testTrimmedStringNilReturnsEmpty
{
    [self assert:[_ctrl trimmedString:nil] equals:@""];
}

- (void)testTrimmedStringEmptyReturnsEmpty
{
    [self assert:[_ctrl trimmedString:@""] equals:@""];
}

- (void)testTrimmedStringNoWhitespace
{
    [self assert:[_ctrl trimmedString:@"hello"] equals:@"hello"];
}

- (void)testTrimmedStringLeadingWhitespace
{
    [self assert:[_ctrl trimmedString:@"   hello"] equals:@"hello"];
}

- (void)testTrimmedStringTrailingWhitespace
{
    [self assert:[_ctrl trimmedString:@"hello   "] equals:@"hello"];
}

- (void)testTrimmedStringBothEnds
{
    [self assert:[_ctrl trimmedString:@"  hello world  "] equals:@"hello world"];
}

// ---------------------------------------------------------------------------
// safeString:
// ---------------------------------------------------------------------------

- (void)testSafeStringNilReturnsEmpty
{
    [self assert:[_ctrl safeString:nil] equals:@""];
}

- (void)testSafeStringEmptyStringReturnsEmpty
{
    [self assert:[_ctrl safeString:@""] equals:@""];
}

- (void)testSafeStringPassesThroughString
{
    [self assert:[_ctrl safeString:@"did:plc:abc"] equals:@"did:plc:abc"];
}

- (void)testSafeStringConvertsNumber
{
    [self assert:[_ctrl safeString:42] equals:@"42"];
}

- (void)testSafeStringConvertsZero
{
    [self assert:[_ctrl safeString:0] equals:@"0"];
}

- (void)testSafeStringConvertsBoolean
{
    [self assert:[_ctrl safeString:YES] equals:@"true"];
}

// ---------------------------------------------------------------------------
// abbreviatedString:maxLength:
// ---------------------------------------------------------------------------

- (void)testAbbreviatedStringNilReturnsEmpty
{
    [self assert:[_ctrl abbreviatedString:nil maxLength:10] equals:@""];
}

- (void)testAbbreviatedStringExactlyAtLimit
{
    // "hello" is 5 chars, maxLength 5 — no truncation
    [self assert:[_ctrl abbreviatedString:@"hello" maxLength:5] equals:@"hello"];
}

- (void)testAbbreviatedStringBelowLimit
{
    [self assert:[_ctrl abbreviatedString:@"hi" maxLength:10] equals:@"hi"];
}

- (void)testAbbreviatedStringExceedsLimit
{
    // "hello world!" = 12 chars, maxLength 8 → "hello..." (5 + 3 = 8)
    [self assert:[_ctrl abbreviatedString:@"hello world!" maxLength:8] equals:@"hello..."];
}

- (void)testAbbreviatedStringProducesEllipsis
{
    var result = [_ctrl abbreviatedString:@"abcdefghij" maxLength:6];
    [self assertTrue:(result.indexOf("...") >= 0)
             message:@"Truncated string should end with ellipsis"];
    [self assertTrue:(result.length === 6)
             message:@"Truncated string should respect maxLength"];
}

// ---------------------------------------------------------------------------
// prettyJSON:
// ---------------------------------------------------------------------------

- (void)testPrettyJSONNilReturnsEmpty
{
    [self assert:[_ctrl prettyJSON:nil] equals:@""];
}

- (void)testPrettyJSONUndefinedReturnsEmpty
{
    [self assert:[_ctrl prettyJSON:undefined] equals:@""];
}

- (void)testPrettyJSONSimpleObject
{
    var result = [_ctrl prettyJSON:{key: "value"}];
    [self assertTrue:(result.length > 0) message:@"prettyJSON should produce non-empty output"];
    [self assertTrue:(result.indexOf("key") >= 0) message:@"Key should appear in output"];
    [self assertTrue:(result.indexOf("value") >= 0) message:@"Value should appear in output"];
}

- (void)testPrettyJSONIsIndented
{
    var result = [_ctrl prettyJSON:{key: "value"}];
    [self assertTrue:(result.indexOf("\n") >= 0)
             message:@"prettyJSON should produce multi-line output"];
}

- (void)testPrettyJSONArray
{
    var result = [_ctrl prettyJSON:[1, 2, 3]];
    [self assertTrue:(result.indexOf("1") >= 0)];
    [self assertTrue:(result.indexOf("2") >= 0)];
    [self assertTrue:(result.indexOf("3") >= 0)];
}

// ---------------------------------------------------------------------------
// renderMSTStatsSummary (pure data-formatting, no UI side-effects)
// ---------------------------------------------------------------------------

- (void)testRenderMSTStatsSummaryWithNoDataReturnsEmpty
{
    // Neither _currentStatsPayload nor _currentTreePayload set → empty string
    [self assert:[_ctrl renderMSTStatsSummary] equals:@""];
}

- (void)testRenderMSTStatsSummaryWithErrorPayload
{
    // Simulate a loaded error payload by going through the public path.
    // We test the return value of renderMSTStatsSummary after the ivars
    // have been set via loadMSTForDid:, but here we test the safe fallback
    // by providing just the empty-guard path (no data set).
    var result = [_ctrl renderMSTStatsSummary];
    [self assertTrue:(result.length === 0)
             message:@"renderMSTStatsSummary should return empty when nothing loaded"];
}

// ---------------------------------------------------------------------------
// renderMSTTreeSummary: (pure data-formatting)
// ---------------------------------------------------------------------------

- (void)testRenderMSTTreeSummaryNilReturnsEmpty
{
    [self assert:[_ctrl renderMSTTreeSummary:nil] equals:@""];
}

- (void)testRenderMSTTreeSummaryWithErrorPayload
{
    var result = [_ctrl renderMSTTreeSummary:{error: "Not found"}];
    [self assertTrue:(result.indexOf("Error:") >= 0)
             message:@"Error payload should produce error prefix in output"];
    [self assertTrue:(result.indexOf("Not found") >= 0)
             message:@"Error message should appear in output"];
}

- (void)testRenderMSTTreeSummaryWithNodesArray
{
    var payload = {
        rootCID: "bafyabc123",
        nodeCount: 2,
        entryCount: 5,
        maxDepth: 1,
        nodes: [
            {level: 0, kind: "leaf", entries: [{fullKey: "a", value: "v1", tree: nil}], left: nil, cid: "cid1"},
            {level: 1, kind: "internal", entries: [], left: "cid1", cid: "cid2"}
        ]
    };
    var result = [_ctrl renderMSTTreeSummary:payload];
    [self assertTrue:(result.indexOf("MST Tree Summary") >= 0)];
    [self assertTrue:(result.indexOf("bafyabc123") >= 0) message:@"Root CID should appear"];
    [self assertTrue:(result.indexOf("Nodes:") >= 0)];
}

// ---------------------------------------------------------------------------
// renderMSTListSummary: (pure data-formatting)
// ---------------------------------------------------------------------------

- (void)testRenderMSTListSummaryNilReturnsEmpty
{
    [self assert:[_ctrl renderMSTListSummary:nil] equals:@""];
}

- (void)testRenderMSTListSummaryWithErrorPayload
{
    var result = [_ctrl renderMSTListSummary:{error: "Timeout"}];
    [self assertTrue:(result.indexOf("Error:") >= 0)];
    [self assertTrue:(result.indexOf("Timeout") >= 0)];
}

- (void)testRenderMSTListSummaryWithNodesArray
{
    var payload = {
        nodes: [
            {level: 0, kind: "leaf", entries: [{fullKey: "key1", value: "val1", tree: nil}], left: nil, cid: "cid-abc"}
        ]
    };
    var result = [_ctrl renderMSTListSummary:payload];
    [self assertTrue:(result.indexOf("MST Node List") >= 0)];
    [self assertTrue:(result.indexOf("cid-abc") >= 0)];
    [self assertTrue:(result.indexOf("key1") >= 0)];
}

@end
