package models

// Assertion represents an XCTest assertion call in test code
type Assertion struct {
	Type          string   // Assertion type (e.g., "XCTAssertEqual", "XCTAssertTrue", "XCTAssertNil")
	Arguments     []string // Raw argument expressions passed to the assertion
	LineNumber    int      // Line number where the assertion appears
	IsConditional bool     // True if assertion is inside an if/else block
	IsReachable   bool     // False if assertion is in unreachable code path
}
