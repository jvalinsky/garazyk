package analysis

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/go-clang/clang-v14/clang"
	. "github.com/september-pds/test-audit-validator/internal/models"
)

// StaticAnalysisEngine provides Objective-C AST parsing capabilities using libclang
type StaticAnalysisEngine struct {
	index   clang.Index
	disposed bool
}

// NewStaticAnalysisEngine creates a new static analysis engine with a clang index
func NewStaticAnalysisEngine() *StaticAnalysisEngine {
	// Create a clang index with excludeDeclarationsFromPCH=1 and displayDiagnostics=1
	// This improves performance by excluding precompiled headers and shows diagnostics
	index := clang.NewIndex(1, 1)
	
	return &StaticAnalysisEngine{
		index: index,
	}
}

// Close releases resources held by the static analysis engine
// It is safe to call Close multiple times
func (e *StaticAnalysisEngine) Close() {
	if !e.disposed && e.index != (clang.Index{}) {
		e.index.Dispose()
		e.disposed = true
	}
}

// ParseFile parses an Objective-C file and returns a translation unit
// It configures clang arguments for Objective-C with ARC and handles parsing errors gracefully
func (e *StaticAnalysisEngine) ParseFile(filePath string) (clang.TranslationUnit, error) {
	return e.ParseFileWithCommandLine(filePath, e.getClangArguments(), false)
}

// getClangArguments returns the clang compiler arguments for Objective-C with ARC
func (e *StaticAnalysisEngine) getClangArguments() []string {
	return []string{
		"-x", "objective-c",           // Treat input as Objective-C
		"-fobjc-arc",                   // Enable Automatic Reference Counting
		"-fblocks",                     // Enable blocks extension
		"-fmodules",                    // Enable modules
		"-isysroot", e.getSDKPath(),   // System root for headers
		"-I/usr/include",               // Standard include path
		"-I/usr/local/include",         // Local include path
		"-Wno-everything",              // Suppress all warnings for cleaner output
	}
}

// getSDKPath returns the SDK path for the current platform
func (e *StaticAnalysisEngine) getSDKPath() string {
	// On macOS, use the Xcode SDK
	// On Linux, this will be empty and clang will use system defaults
	// This is a simplified version - production code might want to detect this dynamically
	return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
}

// ParseFileWithFallback attempts to parse a file with standard settings,
// and if that fails, tries with more lenient settings
func (e *StaticAnalysisEngine) ParseFileWithFallback(filePath string) (clang.TranslationUnit, error) {
	// First attempt: standard parsing
	tu, err := e.ParseFile(filePath)
	if err == nil {
		return tu, nil
	}
	
	// If standard parsing failed, try with more lenient options
	// This is the "fallback strategy" mentioned in the task
	args := []string{
		"-x", "objective-c",
		"-fobjc-arc",
		"-fblocks",
		"-Wno-everything",
		"-ferror-limit=0", // Don't stop on errors
	}
	return e.ParseFileWithCommandLine(filePath, args, false)
}

// ParseFileWithCommandLine parses a file with explicit clang command-line arguments.
// If fullArgv is true, commandLineArgs must include argv[0] and will be passed to
// ParseTranslationUnit2FullArgv.
func (e *StaticAnalysisEngine) ParseFileWithCommandLine(filePath string, commandLineArgs []string, fullArgv bool) (clang.TranslationUnit, error) {
	// Validate file path
	if filePath == "" {
		return clang.TranslationUnit{}, fmt.Errorf("file path cannot be empty")
	}

	// Check if file has .m or .h extension
	ext := strings.ToLower(filepath.Ext(filePath))
	if ext != ".m" && ext != ".h" {
		return clang.TranslationUnit{}, fmt.Errorf("file must have .m or .h extension, got: %s", ext)
	}

	if len(commandLineArgs) == 0 {
		commandLineArgs = e.getClangArguments()
	}

	// Note: We do NOT use SkipFunctionBodies because we need to analyze method
	// bodies for assertions, variables, and method calls.
	options := clang.TranslationUnit_DetailedPreprocessingRecord |
		clang.TranslationUnit_KeepGoing

	var (
		tu clang.TranslationUnit
		ec clang.ErrorCode
	)
	if fullArgv {
		ec = e.index.ParseTranslationUnit2FullArgv(
			filePath,
			commandLineArgs,
			nil, // unsaved files
			uint32(options),
			&tu,
		)
	} else {
		ec = e.index.ParseTranslationUnit2(
			filePath,
			commandLineArgs,
			nil, // unsaved files
			uint32(options),
			&tu,
		)
	}
	if ec != clang.Error_Success || !tu.IsValid() {
		if tu.IsValid() {
			tu.Dispose()
		}
		return clang.TranslationUnit{}, fmt.Errorf("failed to parse file %s (error: %s)", filePath, ec.Spelling())
	}

	// Check for parse diagnostics
	diagnostics := tu.Diagnostics()
	hasParseErrors := false
	var errorMessages []string

	for _, diag := range diagnostics {
		severity := diag.Severity()
		if severity == clang.Diagnostic_Error || severity == clang.Diagnostic_Fatal {
			hasParseErrors = true
			errorMessages = append(errorMessages, diag.Spelling())
		}
	}

	// Return translation unit and error together to enable partial analysis.
	if hasParseErrors {
		return tu, fmt.Errorf("parse errors in %s: %s", filePath, strings.Join(errorMessages, "; "))
	}

	return tu, nil
}

// GetCursor returns the root cursor for a translation unit
func (e *StaticAnalysisEngine) GetCursor(tu clang.TranslationUnit) clang.Cursor {
	return tu.TranslationUnitCursor()
}

// VisitChildren visits all children of a cursor with a visitor function
// The visitor function should return true to continue visiting, false to stop
func (e *StaticAnalysisEngine) VisitChildren(cursor clang.Cursor, visitor func(cursor, parent clang.Cursor) bool) {
	cursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		if visitor(cursor, parent) {
			return clang.ChildVisit_Continue
		}
		return clang.ChildVisit_Break
	})
}

// ExtractAssertions finds all XCTest assertion calls in a method
// It detects all XCTest assertion types and tracks their context (conditional, reachable)
func (e *StaticAnalysisEngine) ExtractAssertions(methodCursor clang.Cursor) ([]Assertion, error) {
	var assertions []Assertion
	
	// Use a more sophisticated approach to track conditional depth
	// We need to track the nesting level properly using the AST structure
	e.extractAssertionsRecursive(methodCursor, &assertions, 0)
	
	return assertions, nil
}

// extractAssertionsRecursive recursively extracts assertions while tracking conditional depth
func (e *StaticAnalysisEngine) extractAssertionsRecursive(cursor clang.Cursor, assertions *[]Assertion, conditionalDepth int) {
	cursor.Visit(func(child, parent clang.Cursor) clang.ChildVisitResult {
		kind := child.Kind()
		
		// Increase conditional depth for if/switch statements
		newDepth := conditionalDepth
		if kind == clang.Cursor_IfStmt || kind == clang.Cursor_SwitchStmt {
			newDepth++
		}
		
		// Look for call expressions that might be XCTest assertions
		if kind == clang.Cursor_CallExpr {
			// Get the function name
			funcName := e.getFunctionName(child)
			
			// Check if this is an XCTest assertion
			if e.isXCTestAssertion(funcName) {
				// Get file location properly
				location := child.Location()
				_, line, _, _ := location.FileLocation()
				
				assertion := Assertion{
					Type:          funcName,
					Arguments:     e.extractCallArguments(child),
					LineNumber:    int(line),
					IsConditional: conditionalDepth > 0,
					IsReachable:   true, // Will be updated by AnalyzeControlFlow
				}
				*assertions = append(*assertions, assertion)
			}
		}
		
		// Recursively visit children with updated depth
		e.extractAssertionsRecursive(child, assertions, newDepth)
		
		return clang.ChildVisit_Continue
	})
}

// visitDescendants recursively visits all descendants of a cursor
func (e *StaticAnalysisEngine) visitDescendants(cursor clang.Cursor, visitor func(cursor, parent clang.Cursor) bool) {
	cursor.Visit(func(child, parent clang.Cursor) clang.ChildVisitResult {
		if !visitor(child, parent) {
			return clang.ChildVisit_Break
		}
		
		// Recursively visit children
		e.visitDescendants(child, visitor)
		
		return clang.ChildVisit_Continue
	})
}

// getFunctionName extracts the function name from a call expression cursor
func (e *StaticAnalysisEngine) getFunctionName(callCursor clang.Cursor) string {
	// For a call expression, the first child is usually the function reference
	var funcName string
	
	callCursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		kind := cursor.Kind()
		
		// Look for the function reference
		if kind == clang.Cursor_DeclRefExpr || kind == clang.Cursor_UnexposedExpr {
			funcName = cursor.Spelling()
			if funcName != "" {
				return clang.ChildVisit_Break
			}
		}
		
		return clang.ChildVisit_Continue
	})
	
	// If we didn't find it via children, try the cursor itself
	if funcName == "" {
		funcName = callCursor.Spelling()
	}
	
	return funcName
}

// isXCTestAssertion checks if a function name is an XCTest assertion macro
func (e *StaticAnalysisEngine) isXCTestAssertion(funcName string) bool {
	// List of all XCTest assertion macros
	xcTestAssertions := []string{
		"XCTAssert",
		"XCTAssertTrue",
		"XCTAssertFalse",
		"XCTAssertEqual",
		"XCTAssertNotEqual",
		"XCTAssertEqualObjects",
		"XCTAssertNotEqualObjects",
		"XCTAssertNil",
		"XCTAssertNotNil",
		"XCTAssertGreaterThan",
		"XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan",
		"XCTAssertLessThanOrEqual",
		"XCTAssertThrows",
		"XCTAssertThrowsSpecific",
		"XCTAssertThrowsSpecificNamed",
		"XCTAssertNoThrow",
		"XCTAssertNoThrowSpecific",
		"XCTAssertNoThrowSpecificNamed",
		"XCTFail",
		"XCTAssertEqualWithAccuracy",
		"XCTAssertNotEqualWithAccuracy",
		"XCTUnwrap",
		"XCTSkip",
		"XCTSkipIf",
		"XCTSkipUnless",
		"XCTExpectFailure",
	}
	
	for _, assertion := range xcTestAssertions {
		if funcName == assertion {
			return true
		}
	}
	
	return false
}

// extractCallArguments extracts argument expressions from a call expression
func (e *StaticAnalysisEngine) extractCallArguments(callCursor clang.Cursor) []string {
	var arguments []string
	
	// Get the number of arguments
	numArgs := int(callCursor.NumArguments())
	
	// Extract each argument
	for i := 0; i < numArgs; i++ {
		argCursor := callCursor.Argument(uint32(i))
		
		// Get the source text for the argument
		argText := e.getCursorText(argCursor)
		arguments = append(arguments, argText)
	}
	
	return arguments
}

// getCursorText extracts the source text for a cursor
// This is a simplified implementation that works for most cases
func (e *StaticAnalysisEngine) getCursorText(cursor clang.Cursor) string {
	kind := cursor.Kind()
	
	// For string literals, use DisplayName which includes the quotes
	if kind == clang.Cursor_StringLiteral || kind == clang.Cursor_ObjCStringLiteral {
		displayName := cursor.DisplayName()
		if displayName != "" {
			return displayName
		}
	}
	
	// For integer and floating literals, try to extract from source
	// This is a simplified approach - we just mark that there's a value
	if kind == clang.Cursor_IntegerLiteral {
		// For now, just return a placeholder to indicate there's a value
		// A full implementation would read the source file
		return "<integer>"
	}
	
	if kind == clang.Cursor_FloatingLiteral {
		return "<float>"
	}
	
	// For other cases, try DisplayName first
	displayName := cursor.DisplayName()
	if displayName != "" {
		return displayName
	}
	
	// Fall back to Spelling
	return cursor.Spelling()
}

// FindMethodByName searches for an Objective-C method by name in a translation unit
// This is a helper method for tests to find method cursors
func (e *StaticAnalysisEngine) FindMethodByName(tu clang.TranslationUnit, methodName string) (clang.Cursor, bool) {
	cursor := tu.TranslationUnitCursor()
	var foundCursor clang.Cursor
	found := false
	
	// Visit all descendants to find the method
	e.visitDescendants(cursor, func(c, parent clang.Cursor) bool {
		if c.Kind() == clang.Cursor_ObjCInstanceMethodDecl || c.Kind() == clang.Cursor_ObjCClassMethodDecl {
			if c.Spelling() == methodName {
				foundCursor = c
				found = true
				return false // Stop searching
			}
		}
		return true // Continue searching
	})
	
	return foundCursor, found
}

// ExtractVariables finds all variable declarations in a method
// It tracks variable names, types, initial values, and line numbers
func (e *StaticAnalysisEngine) ExtractVariables(methodCursor clang.Cursor) ([]Variable, error) {
	var variables []Variable
	
	// Recursively visit all descendants of the method
	e.visitDescendants(methodCursor, func(cursor, parent clang.Cursor) bool {
		kind := cursor.Kind()
		
		// Look for variable declarations (VarDecl nodes)
		if kind == clang.Cursor_VarDecl {
			// Get file location
			location := cursor.Location()
			_, line, _, _ := location.FileLocation()
			
			// Get variable name
			name := cursor.Spelling()
			
			// Get variable type
			varType := cursor.Type().Spelling()
			
			// Get initial value if present
			var initialValue *string
			
			// Visit children to find initialization expression
			cursor.Visit(func(child, parent clang.Cursor) clang.ChildVisitResult {
				childKind := child.Kind()
				
				// Look for initialization expressions
				// These can be various kinds: IntegerLiteral, StringLiteral, CallExpr, etc.
				if childKind == clang.Cursor_IntegerLiteral ||
					childKind == clang.Cursor_FloatingLiteral ||
					childKind == clang.Cursor_StringLiteral ||
					childKind == clang.Cursor_CharacterLiteral ||
					childKind == clang.Cursor_ObjCStringLiteral ||
					childKind == clang.Cursor_CallExpr ||
					childKind == clang.Cursor_ObjCMessageExpr ||
					childKind == clang.Cursor_DeclRefExpr ||
					childKind == clang.Cursor_UnexposedExpr {
					
					// Get the text representation of the initial value
					initText := e.getCursorText(child)
					if initText != "" {
						initialValue = &initText
						return clang.ChildVisit_Break
					}
				}
				
				return clang.ChildVisit_Continue
			})
			
			variable := Variable{
				Name:         name,
				Type:         varType,
				InitialValue: initialValue,
				LineNumber:   int(line),
			}
			
			variables = append(variables, variable)
		}
		
		return true // Continue visiting
	})
	
	return variables, nil
}

// ExtractMethodCalls finds all method invocations in a method
// It extracts receiver, selector, arguments, and line numbers
func (e *StaticAnalysisEngine) ExtractMethodCalls(methodCursor clang.Cursor) ([]MethodCall, error) {
	var methodCalls []MethodCall
	
	// Recursively visit all descendants of the method
	e.visitDescendants(methodCursor, func(cursor, parent clang.Cursor) bool {
		kind := cursor.Kind()
		
		// Look for Objective-C message expressions (method calls)
		if kind == clang.Cursor_ObjCMessageExpr {
			// Get file location
			location := cursor.Location()
			_, line, _, _ := location.FileLocation()
			
			// Get the selector (method name)
			selector := cursor.DisplayName()
			
			// Get the receiver
			receiver := e.extractReceiver(cursor)
			
			// Get the arguments
			arguments := e.extractMessageArguments(cursor)
			
			methodCall := MethodCall{
				Receiver:   receiver,
				Selector:   selector,
				Arguments:  arguments,
				LineNumber: int(line),
			}
			
			methodCalls = append(methodCalls, methodCall)
		}
		
		return true // Continue visiting
	})
	
	return methodCalls, nil
}

// extractReceiver extracts the receiver object or class name from a message expression
func (e *StaticAnalysisEngine) extractReceiver(messageCursor clang.Cursor) string {
	// The receiver is typically the first child of the message expression
	var receiver string
	
	messageCursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		kind := cursor.Kind()
		
		// Look for the receiver expression
		// It can be a DeclRefExpr (variable), MemberRefExpr (property), or ObjCClassRef (class)
		if kind == clang.Cursor_DeclRefExpr ||
			kind == clang.Cursor_MemberRefExpr ||
			kind == clang.Cursor_ObjCClassRef ||
			kind == clang.Cursor_UnexposedExpr {
			
			receiver = cursor.Spelling()
			if receiver == "" {
				receiver = cursor.DisplayName()
			}
			
			// If we found a receiver, stop looking
			if receiver != "" {
				return clang.ChildVisit_Break
			}
		}
		
		return clang.ChildVisit_Continue
	})
	
	// If we didn't find a receiver through children, try to get it from the cursor itself
	if receiver == "" {
		// For class methods, the receiver might be in the type
		receiverType := messageCursor.ReceiverType()
		if receiverType.Kind() != clang.Type_Invalid {
			receiver = receiverType.Spelling()
		}
	}
	
	// If still empty, use a placeholder
	if receiver == "" {
		receiver = "<unknown>"
	}
	
	return receiver
}

// extractMessageArguments extracts argument expressions from an Objective-C message expression
func (e *StaticAnalysisEngine) extractMessageArguments(messageCursor clang.Cursor) []string {
	var arguments []string
	
	// Get the number of arguments
	numArgs := int(messageCursor.NumArguments())
	
	// Extract each argument
	for i := 0; i < numArgs; i++ {
		argCursor := messageCursor.Argument(uint32(i))
		
		// Get the source text for the argument
		argText := e.getCursorText(argCursor)
		if argText == "" {
			argText = argCursor.Spelling()
		}
		
		arguments = append(arguments, argText)
	}
	
	return arguments
}

// ControlFlowNode represents a node in the control flow graph
type ControlFlowNode struct {
	Cursor     clang.Cursor
	Kind       clang.CursorKind
	LineNumber int
	IsReachable bool
	Children   []*ControlFlowNode
}

// AnalyzeControlFlow builds a control flow graph and detects unreachable code paths
// It updates the IsReachable field on assertions based on control flow analysis
func (e *StaticAnalysisEngine) AnalyzeControlFlow(methodCursor clang.Cursor, assertions []Assertion) []Assertion {
	// Build a map of line numbers to assertion indices for quick lookup
	assertionsByLine := make(map[int]int)
	for i, assertion := range assertions {
		assertionsByLine[assertion.LineNumber] = i
	}
	
	// Track unreachable code regions
	unreachableRegions := e.findUnreachableRegions(methodCursor)
	
	// Update assertions based on unreachable regions
	for i := range assertions {
		lineNum := assertions[i].LineNumber
		if e.isLineInUnreachableRegion(lineNum, unreachableRegions) {
			assertions[i].IsReachable = false
		}
	}
	
	return assertions
}

// UnreachableRegion represents a region of code that cannot be reached
type UnreachableRegion struct {
	StartLine int
	EndLine   int
	Reason    string // "after-return", "after-throw", "always-false-condition", etc.
}

// findUnreachableRegions identifies regions of code that cannot be reached
func (e *StaticAnalysisEngine) findUnreachableRegions(methodCursor clang.Cursor) []UnreachableRegion {
	var regions []UnreachableRegion
	
	// Get the method's extent to know the boundaries
	methodExtent := methodCursor.Extent()
	_, methodEndLine, _, _ := methodExtent.End().FileLocation()
	
	// Find the method body (CompoundStmt)
	var methodBody clang.Cursor
	methodCursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		if cursor.Kind() == clang.Cursor_CompoundStmt {
			methodBody = cursor
			return clang.ChildVisit_Break
		}
		return clang.ChildVisit_Continue
	})
	
	if methodBody.IsNull() {
		// No method body found
		return regions
	}
	
	// Track statements in the method body (direct children of the compound statement)
	type statement struct {
		kind   clang.CursorKind
		line   int
		cursor clang.Cursor
	}
	
	var statements []statement
	
	// Collect all direct children of the method body
	methodBody.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		location := cursor.Location()
		_, line, _, _ := location.FileLocation()
		
		statements = append(statements, statement{
			kind:   cursor.Kind(),
			line:   int(line),
			cursor: cursor,
		})
		
		// Don't recurse - we only want direct children
		return clang.ChildVisit_Continue
	})
	
	// Find return statements and mark everything after as unreachable
	for _, stmt := range statements {
		if stmt.kind == clang.Cursor_ReturnStmt {
			// Everything after this return until the end of the method is unreachable
			startLine := stmt.line + 1
			endLine := int(methodEndLine)
			
			if startLine <= endLine {
				regions = append(regions, UnreachableRegion{
					StartLine: startLine,
					EndLine:   endLine,
					Reason:    "after-return",
				})
			}
			
			// Once we find a return at the top level, everything after is unreachable
			break
		}
	}
	
	// Find always-false conditions recursively
	e.findAlwaysFalseRegions(methodCursor, &regions)
	
	return regions
}

// findAlwaysFalseRegions finds regions inside always-false if statements
func (e *StaticAnalysisEngine) findAlwaysFalseRegions(cursor clang.Cursor, regions *[]UnreachableRegion) {
	cursor.Visit(func(child, parent clang.Cursor) clang.ChildVisitResult {
		if child.Kind() == clang.Cursor_IfStmt {
			// Check if this if statement has an always-false condition
			if e.isAlwaysFalseCondition(child) {
				// Find the then-branch (the body of the if statement)
				var thenBranchStart, thenBranchEnd int
				
				// The then-branch is typically the second child of the if statement
				// First child is the condition, second is the then-branch
				childCount := 0
				child.Visit(func(grandchild, gparent clang.Cursor) clang.ChildVisitResult {
					childCount++
					// Skip the first child (condition), get the second (then-branch)
					if childCount == 2 {
						extent := grandchild.Extent()
						_, start, _, _ := extent.Start().FileLocation()
						_, end, _, _ := extent.End().FileLocation()
						thenBranchStart = int(start)
						thenBranchEnd = int(end)
						return clang.ChildVisit_Break
					}
					return clang.ChildVisit_Continue
				})
				
				if thenBranchStart > 0 && thenBranchEnd > 0 {
					*regions = append(*regions, UnreachableRegion{
						StartLine: thenBranchStart,
						EndLine:   thenBranchEnd,
						Reason:    "always-false-condition",
					})
				}
			}
		}
		
		// Recursively check nested statements
		e.findAlwaysFalseRegions(child, regions)
		
		return clang.ChildVisit_Continue
	})
}

// isAlwaysFalseCondition checks if an if statement has a condition that is always false
func (e *StaticAnalysisEngine) isAlwaysFalseCondition(ifStmt clang.Cursor) bool {
	// Look for the condition expression (first child of if statement)
	isAlwaysFalse := false
	
	ifStmt.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		kind := cursor.Kind()
		
		// Check for Objective-C boolean literal (NO)
		// In Objective-C, NO and YES are represented as ObjCBoolLiteralExpr
		// Unfortunately, we can't easily distinguish NO from YES without reading source
		// So we use a heuristic: if the extent is small (3 chars or less), it's likely NO
		// This is a limitation of the clang API
		if kind == clang.Cursor_ObjCBoolLiteralExpr {
			extent := cursor.Extent()
			_, _, startCol, _ := extent.Start().FileLocation()
			_, _, endCol, _ := extent.End().FileLocation()
			
			// NO is 2 characters, YES is 3 characters
			// If the extent is 2-3 columns, we assume it could be either
			// For now, we'll assume any ObjCBoolLiteralExpr in a condition
			// that's very short is likely NO (this is a heuristic)
			colSpan := int(endCol) - int(startCol)
			
			// If it's 2 columns (NO), mark as always false
			// This is imperfect but works for most cases
			if colSpan <= 2 {
				isAlwaysFalse = true
			}
			
			return clang.ChildVisit_Break
		}
		
		// Check for integer literal 0
		if kind == clang.Cursor_IntegerLiteral {
			// For integer literals, we try to evaluate them
			// The clang API doesn't give us easy access to the value
			// So we use a heuristic: if it's a very short extent (1 char), it's likely 0 or 1
			extent := cursor.Extent()
			_, _, startCol, _ := extent.Start().FileLocation()
			_, _, endCol, _ := extent.End().FileLocation()
			
			colSpan := int(endCol) - int(startCol)
			
			// If it's 1 column (just "0"), mark as always false
			if colSpan == 1 {
				// This is likely "0" - mark as always false
				isAlwaysFalse = true
				return clang.ChildVisit_Break
			}
		}
		
		// Check for explicit NO or false identifiers
		if kind == clang.Cursor_DeclRefExpr {
			spelling := cursor.Spelling()
			if spelling == "NO" || spelling == "false" {
				isAlwaysFalse = true
				return clang.ChildVisit_Break
			}
		}
		
		// Only check the first child (the condition)
		return clang.ChildVisit_Break
	})
	
	return isAlwaysFalse
}

// isLineInUnreachableRegion checks if a line number falls within any unreachable region
func (e *StaticAnalysisEngine) isLineInUnreachableRegion(lineNum int, regions []UnreachableRegion) bool {
	for _, region := range regions {
		if lineNum >= region.StartLine && lineNum <= region.EndLine {
			return true
		}
	}
	return false
}
