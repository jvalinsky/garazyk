// Package models defines the core data structures for representing parsed Objective-C test code.
//
// These models form the foundation for all subsequent analysis and validation in the
// Test Audit Validation System. They represent the structure of test files, classes,
// methods, assertions, and other code elements extracted during static analysis.
//
// The primary data structures are:
//
//   - TestFile: Represents a test file containing test classes
//   - TestClass: Represents a test class (typically inheriting from XCTestCase)
//   - TestMethod: Represents a single test method within a test class
//   - Assertion: Represents an XCTest assertion call in test code
//   - Variable: Represents a variable declaration in test code
//   - MethodCall: Represents a method invocation in test code
//
// These models are populated by the Static Analysis Engine during AST parsing
// and consumed by the Validation Engine to detect test quality issues.
package models
