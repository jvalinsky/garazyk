package models

import "testing"

// TestTestFileCreation verifies TestFile struct can be instantiated
func TestTestFileCreation(t *testing.T) {
	testFile := TestFile{
		Path:    "ATProtoPDS/Tests/Auth/OAuthTests.m",
		Classes: []TestClass{},
		Imports: []string{"<XCTest/XCTest.h>", "\"OAuth.h\""},
	}

	if testFile.Path != "ATProtoPDS/Tests/Auth/OAuthTests.m" {
		t.Errorf("Expected path to be set correctly")
	}
	if len(testFile.Imports) != 2 {
		t.Errorf("Expected 2 imports, got %d", len(testFile.Imports))
	}
}

// TestTestClassCreation verifies TestClass struct can be instantiated
func TestTestClassCreation(t *testing.T) {
	baseClass := "XCTestCase"
	testClass := TestClass{
		Name:      "OAuthTests",
		FilePath:  "ATProtoPDS/Tests/Auth/OAuthTests.m",
		Methods:   []TestMethod{},
		BaseClass: &baseClass,
		IsHelper:  false,
	}

	if testClass.Name != "OAuthTests" {
		t.Errorf("Expected name to be set correctly")
	}
	if testClass.BaseClass == nil || *testClass.BaseClass != "XCTestCase" {
		t.Errorf("Expected base class to be XCTestCase")
	}
	if testClass.IsHelper {
		t.Errorf("Expected IsHelper to be false")
	}
}

// TestTestMethodCreation verifies TestMethod struct can be instantiated
func TestTestMethodCreation(t *testing.T) {
	testMethod := TestMethod{
		Name:       "testOAuthTokenValidation",
		ClassName:  "OAuthTests",
		LineNumber: 42,
		SourceCode: "- (void)testOAuthTokenValidation { ... }",
		Assertions: []Assertion{},
		Comments:   []string{"// Test OAuth token validation"},
	}

	if testMethod.Name != "testOAuthTokenValidation" {
		t.Errorf("Expected method name to be set correctly")
	}
	if testMethod.LineNumber != 42 {
		t.Errorf("Expected line number to be 42, got %d", testMethod.LineNumber)
	}
}

// TestAssertionCreation verifies Assertion struct can be instantiated
func TestAssertionCreation(t *testing.T) {
	assertion := Assertion{
		Type:          "XCTAssertEqual",
		Arguments:     []string{"token.type", "@\"Bearer\""},
		LineNumber:    45,
		IsConditional: false,
		IsReachable:   true,
	}

	if assertion.Type != "XCTAssertEqual" {
		t.Errorf("Expected assertion type to be XCTAssertEqual")
	}
	if len(assertion.Arguments) != 2 {
		t.Errorf("Expected 2 arguments, got %d", len(assertion.Arguments))
	}
	if !assertion.IsReachable {
		t.Errorf("Expected assertion to be reachable")
	}
}

// TestVariableCreation verifies Variable struct can be instantiated
func TestVariableCreation(t *testing.T) {
	initialValue := "@\"test\""
	variable := Variable{
		Name:         "token",
		Type:         "NSString*",
		InitialValue: &initialValue,
		LineNumber:   10,
	}

	if variable.Name != "token" {
		t.Errorf("Expected variable name to be token")
	}
	if variable.Type != "NSString*" {
		t.Errorf("Expected variable type to be NSString*")
	}
	if variable.InitialValue == nil || *variable.InitialValue != "@\"test\"" {
		t.Errorf("Expected initial value to be @\"test\"")
	}
}

// TestMethodCallCreation verifies MethodCall struct can be instantiated
func TestMethodCallCreation(t *testing.T) {
	methodCall := MethodCall{
		Receiver:   "parser",
		Selector:   "parse:",
		Arguments:  []string{"input"},
		LineNumber: 20,
	}

	if methodCall.Receiver != "parser" {
		t.Errorf("Expected receiver to be parser")
	}
	if methodCall.Selector != "parse:" {
		t.Errorf("Expected selector to be parse:")
	}
	if len(methodCall.Arguments) != 1 {
		t.Errorf("Expected 1 argument, got %d", len(methodCall.Arguments))
	}
}

// TestNilBaseClass verifies TestClass works with nil base class
func TestNilBaseClass(t *testing.T) {
	testClass := TestClass{
		Name:      "TestHelper",
		FilePath:  "ATProtoPDS/Tests/Helpers/TestHelper.m",
		Methods:   []TestMethod{},
		BaseClass: nil,
		IsHelper:  true,
	}

	if testClass.BaseClass != nil {
		t.Errorf("Expected base class to be nil")
	}
	if !testClass.IsHelper {
		t.Errorf("Expected IsHelper to be true")
	}
}

// TestNilInitialValue verifies Variable works with nil initial value
func TestNilInitialValue(t *testing.T) {
	variable := Variable{
		Name:         "result",
		Type:         "id",
		InitialValue: nil,
		LineNumber:   15,
	}

	if variable.InitialValue != nil {
		t.Errorf("Expected initial value to be nil")
	}
}
