package validation

import (
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// TestDocumentationRule validates test documentation quality
type TestDocumentationRule struct{}

// NewTestDocumentationRule creates a new instance of the rule
func NewTestDocumentationRule() *TestDocumentationRule {
	return &TestDocumentationRule{}
}

// Name returns the unique name of this rule
func (r *TestDocumentationRule) Name() string {
	return "TestDocumentationRule"
}

// Severity returns the severity level for findings from this rule
func (r *TestDocumentationRule) Severity() Severity {
	return LOW
}

// Description returns a human-readable description of what this rule validates
func (r *TestDocumentationRule) Description() string {
	return "Validates that complex test methods have adequate documentation explaining their purpose and approach"
}

// Validate applies the rule to the given context and returns findings
func (r *TestDocumentationRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	method := ctx.TestMethod
	isComplex := r.isComplex(method)
	hasComments := len(method.Comments) > 0

	// Check for complex setup without documentation
	if r.hasComplexSetup(method) && !hasComments {
		findings = append(findings, r.makeFinding(ctx,
			"Test has complex setup code without explanatory comments.",
			"Add comments explaining what the setup code prepares and why it is needed.",
		))
	}

	// Check for missing documentation on complex tests
	if isComplex && !hasComments {
		score := r.documentationScore(method)
		if score < 0.3 {
			findings = append(findings, Finding{
				RuleName:       r.Name(),
				Severity:       r.Severity(),
				TestMethod:     method.Name,
				TestClass:      r.className(ctx),
				FilePath:       r.filePath(ctx),
				LineNumber:     method.LineNumber,
				Message:        "Complex test method has no documentation. Consider adding comments explaining the test's purpose and approach.",
				Recommendation: "Add a comment block before or at the start of the test method describing what is being tested and the expected behavior.",
				Confidence:     score,
			})
		}
	}

	return findings
}

// isComplex determines whether a test method is complex enough to warrant documentation
func (r *TestDocumentationRule) isComplex(method *models.TestMethod) bool {
	lineCount := strings.Count(method.SourceCode, "\n") + 1
	if lineCount > 30 {
		return true
	}

	if len(method.Assertions) > 8 {
		return true
	}

	if r.countObjectCreations(method.SourceCode) > 3 {
		return true
	}

	return false
}

// hasComplexSetup checks if a test has complex setup without documentation
func (r *TestDocumentationRule) hasComplexSetup(method *models.TestMethod) bool {
	creationCount := r.countObjectCreations(method.SourceCode)
	return creationCount > 3
}

// countObjectCreations counts alloc] init and [ClassName new] patterns in source code
func (r *TestDocumentationRule) countObjectCreations(source string) int {
	count := 0
	count += strings.Count(source, "alloc] init")
	count += strings.Count(source, " new]")
	return count
}

// documentationScore calculates a documentation completeness score
func (r *TestDocumentationRule) documentationScore(method *models.TestMethod) float64 {
	commentCount := float64(len(method.Comments))

	lineCount := float64(strings.Count(method.SourceCode, "\n") + 1)
	assertionCount := float64(len(method.Assertions))
	complexityIndicator := lineCount/10.0 + assertionCount/3.0

	if complexityIndicator < 1.0 {
		complexityIndicator = 1.0
	}

	score := commentCount / complexityIndicator
	if score > 1.0 {
		score = 1.0
	}
	return score
}

func (r *TestDocumentationRule) makeFinding(ctx ValidationContext, message, recommendation string) Finding {
	return Finding{
		RuleName:       r.Name(),
		Severity:       r.Severity(),
		TestMethod:     ctx.TestMethod.Name,
		TestClass:      r.className(ctx),
		FilePath:       r.filePath(ctx),
		LineNumber:     ctx.TestMethod.LineNumber,
		Message:        message,
		Recommendation: recommendation,
		Confidence:     r.documentationScore(ctx.TestMethod),
	}
}

func (r *TestDocumentationRule) className(ctx ValidationContext) string {
	if ctx.TestClass != nil {
		return ctx.TestClass.Name
	}
	return ctx.TestMethod.ClassName
}

func (r *TestDocumentationRule) filePath(ctx ValidationContext) string {
	if ctx.TestFile != nil {
		return ctx.TestFile.Path
	}
	if ctx.TestClass != nil {
		return ctx.TestClass.FilePath
	}
	return ""
}
