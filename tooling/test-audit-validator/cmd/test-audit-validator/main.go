package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/september-pds/test-audit-validator/internal/cache"
	"github.com/september-pds/test-audit-validator/internal/config"
	"github.com/september-pds/test-audit-validator/internal/models"
	"github.com/september-pds/test-audit-validator/internal/report"
	"github.com/september-pds/test-audit-validator/internal/runner"
	"github.com/september-pds/test-audit-validator/internal/validation"
	"github.com/spf13/cobra"
)

// Exit codes:
//   0 = success (no findings at or above fail-on level)
//   1 = critical findings found
//   2 = high findings found
//   3 = medium findings found
//   4 = low findings found

var (
	cachePath          string
	format             string
	output             string
	quiet              bool
	incremental        bool
	failOn             string
	domains            []string
	severities         []string
	testTypes          []string
	classes            []string
	workers            int
	parserMode         string
	compileCommandsDir string
	clangArgs          []string
	configFile         string
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "test-audit-validator",
		Short: "Validate that tests actually test what they claim to test",
		Long:  "Analyzes test code to identify false positive tests, assertion gaps, and naming mismatches",
	}

	analyzeCmd := &cobra.Command{
		Use:   "analyze [directory]",
		Short: "Run test audit analysis",
		Args:  cobra.MaximumNArgs(1),
		RunE:  runAnalyze,
	}

	analyzeCmd.Flags().StringVar(&configFile, "config", "", "Path to config file")
	analyzeCmd.Flags().StringVar(&cachePath, "cache", ".test_audit_cache.db", "Path to cache database")
	analyzeCmd.Flags().StringVarP(&format, "format", "f", "markdown", "Output format: markdown, json, html")
	analyzeCmd.Flags().StringVarP(&output, "output", "o", "", "Output file (default: stdout)")
	analyzeCmd.Flags().BoolVarP(&quiet, "quiet", "q", false, "Suppress progress output")
	analyzeCmd.Flags().BoolVar(&incremental, "incremental", false, "Only analyze changed files")
	analyzeCmd.Flags().StringVar(&failOn, "fail-on", "", "Exit with error if findings at this severity or above (critical, high, medium, low)")
	analyzeCmd.Flags().StringSliceVar(&domains, "domain", nil, "Filter by domain (Auth, Core, Network, etc.)")
	analyzeCmd.Flags().StringSliceVar(&severities, "severity", nil, "Filter by severity (critical, high, medium, low)")
	analyzeCmd.Flags().StringSliceVar(&testTypes, "test-type", nil, "Filter by test type")
	analyzeCmd.Flags().StringSliceVar(&classes, "class", nil, "Filter by test class name")
	analyzeCmd.Flags().IntVar(&workers, "workers", 0, "Number of parallel workers (default: NumCPU)")
	analyzeCmd.Flags().StringVar(&parserMode, "parser", "auto", "Parser mode: auto, clang, simple")
	analyzeCmd.Flags().StringVar(&compileCommandsDir, "compile-commands-dir", "", "Directory containing compile_commands.json")
	analyzeCmd.Flags().StringSliceVar(&clangArgs, "clang-arg", nil, "Additional clang argument (repeatable)")

	rootCmd.AddCommand(analyzeCmd)

	versionCmd := &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println("test-audit-validator v0.1.0")
		},
	}
	rootCmd.AddCommand(versionCmd)

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func runAnalyze(cmd *cobra.Command, args []string) error {
	start := time.Now()
	flags := cmd.Flags()

	cfg, err := config.LoadConfig(configFile)
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	// Positional directory argument has highest precedence for root directory.
	if len(args) > 0 {
		cfg.RootDirectory = args[0]
	}

	// Overlay explicit CLI flag values on top of config/env/defaults.
	if flags.Changed("cache") {
		cfg.CachePath = cachePath
	}
	if flags.Changed("format") {
		cfg.OutputFormat = format
	}
	if flags.Changed("output") {
		cfg.OutputFile = output
	}
	if flags.Changed("quiet") {
		cfg.Quiet = quiet
	}
	if flags.Changed("incremental") {
		cfg.Incremental = incremental
	}
	if flags.Changed("fail-on") {
		cfg.FailOn = failOn
	}
	if flags.Changed("domain") {
		cfg.Domains = domains
	}
	if flags.Changed("severity") {
		cfg.Severities = severities
	}
	if flags.Changed("test-type") {
		cfg.TestTypes = testTypes
	}
	if flags.Changed("class") {
		cfg.TestClasses = classes
	}
	if flags.Changed("workers") {
		cfg.Workers = workers
	}
	if flags.Changed("parser") {
		cfg.Parser = parserMode
	}
	if flags.Changed("compile-commands-dir") {
		cfg.CompileCommandsDir = compileCommandsDir
	}
	if flags.Changed("clang-arg") {
		cfg.ClangArgs = clangArgs
	}

	// Apply defaults for unset values
	if cfg.Workers <= 0 {
		cfg.Workers = config.DefaultConfig().Workers
	}
	if cfg.MaxFileSize <= 0 {
		cfg.MaxFileSize = config.DefaultConfig().MaxFileSize
	}
	if cfg.FileTimeout <= 0 {
		cfg.FileTimeout = config.DefaultConfig().FileTimeout
	}

	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("configuration error: %w", err)
	}

	if !cfg.Quiet {
		fmt.Fprintf(os.Stderr, "Analyzing tests in: %s\n", cfg.RootDirectory)
	}

	// Discover test files
	testFiles, err := discoverTestFiles(cfg.RootDirectory)
	if err != nil {
		return fmt.Errorf("discovering test files: %w", err)
	}

	if len(testFiles) == 0 {
		if !cfg.Quiet {
			fmt.Fprintln(os.Stderr, "No test files found.")
		}
		return nil
	}

	if !cfg.Quiet {
		fmt.Fprintf(os.Stderr, "Found %d test files\n", len(testFiles))
	}

	// Set up validation engine with all rules
	rules := validation.DefaultRules()
	engine := validation.NewEngine(rules)

	// Always available regex parser
	analyzer := func(filePath string) (*models.TestFile, error) {
		return parseTestFileSimple(filePath)
	}

	// Libclang-backed parser (used in auto/clang modes).
	var clangAnalyzer fileAnalyzerFn
	if cfg.Parser != parserModeSimple {
		clangParser := newClangFileParser(cfg)
		clangAnalyzer = clangParser.analyze
	}

	selector, err := newParserSelector(cfg.Parser, analyzer, clangAnalyzer, os.Stderr)
	if err != nil {
		return fmt.Errorf("configuring parser selector: %w", err)
	}
	analyzer = selector.analyze

	// Set up runner
	r := runner.NewRunner(engine, analyzer, cfg)

	// Set up incremental analysis if enabled
	if cfg.Incremental {
		cm, err := cache.NewCacheManager(cfg.CachePath)
		if err != nil {
			if !cfg.Quiet {
				fmt.Fprintf(os.Stderr, "Warning: could not set up cache: %v\n", err)
			}
		} else {
			defer cm.Close()
			ia := cache.NewIncrementalAnalyzer(cm)
			r.SetIncrementalAnalyzer(ia)
		}
	}

	// Set up progress reporting
	if !cfg.Quiet {
		pr := runner.NewProgressReporter(os.Stderr, len(testFiles), false)
		r.SetProgressReporter(pr)
	}

	// Run analysis
	results := r.Run(context.Background(), testFiles)
	parserStats := selector.stats()

	// Aggregate findings and stats
	var allFindings []validation.Finding
	var analysisErrors []runner.Result
	var totalTests, totalClasses, totalAssertions int
	for _, res := range results {
		if res.Error != nil {
			analysisErrors = append(analysisErrors, res)
			if !cfg.Quiet {
				fmt.Fprintf(os.Stderr, "Error analyzing %s: %v\n", res.FilePath, res.Error)
			}
			continue
		}
		allFindings = append(allFindings, res.Findings...)
	}

	reportErrors := make([]report.AnalysisError, 0, len(analysisErrors))
	for _, e := range analysisErrors {
		reportErrors = append(reportErrors, report.AnalysisError{
			FilePath: e.FilePath,
			Message:  e.Error.Error(),
		})
	}

	// In strict clang mode, any file-level analysis error fails the run.
	// For JSON output, still emit a machine-readable report before returning error.
	var strictClangErr error
	if cfg.Parser == parserModeClang && len(analysisErrors) > 0 {
		first := analysisErrors[0]
		strictClangErr = fmt.Errorf(
			"strict clang mode failed on %d/%d file(s); first failure: %s: %w",
			len(analysisErrors),
			len(testFiles),
			first.FilePath,
			first.Error,
		)
		if cfg.OutputFormat != "json" {
			return strictClangErr
		}
	}

	// Count tests, classes, assertions from a second pass through files
	for _, fp := range testFiles {
		tf, err := parseTestFileSimple(fp)
		if err != nil {
			continue
		}
		totalClasses += len(tf.Classes)
		for _, c := range tf.Classes {
			totalTests += len(c.Methods)
			for _, m := range c.Methods {
				totalAssertions += len(m.Assertions)
			}
		}
	}

	// Apply filters
	filtered := config.FilterFindings(allFindings, cfg)
	filtered = validation.DedupeFindings(filtered)

	// Calculate statistics
	stats := report.CalculateStatistics(filtered, totalTests, totalClasses, len(testFiles), totalAssertions)

	// Build report
	duration := time.Since(start)
	configSnapshot := map[string]string{
		"parser":  cfg.Parser,
		"workers": fmt.Sprintf("%d", cfg.Workers),
	}
	if cfg.CompileCommandsDir != "" {
		configSnapshot["compile_commands_dir"] = cfg.CompileCommandsDir
	}
	if len(cfg.ClangArgs) > 0 {
		configSnapshot["clang_args"] = strings.Join(cfg.ClangArgs, " ")
	}
	if cfg.FailOn != "" {
		configSnapshot["fail_on"] = cfg.FailOn
	}

	rpt := &report.Report{
		Findings:   filtered,
		Statistics: stats,
		Metadata: report.Metadata{
			AnalysisTimestamp: time.Now().Format(time.RFC3339),
			Version:           "0.1.0",
			RootDirectory:     cfg.RootDirectory,
			Duration:          duration.String(),
			Configuration:     configSnapshot,
			ParserMode:        parserStats.Mode,
			ClangAttempted:    parserStats.ClangAttempted,
			ClangSucceeded:    parserStats.ClangSucceeded,
			ClangFallbacks:    parserStats.ClangFallbacks,
		},
		Errors: reportErrors,
	}

	// Generate report
	var reportOutput string
	switch cfg.OutputFormat {
	case "json":
		gen := report.NewJSONReportGenerator(true)
		reportOutput, err = gen.Generate(rpt)
	case "html":
		gen := report.NewHTMLReportGenerator()
		reportOutput, err = gen.Generate(rpt)
	default:
		gen := report.NewMarkdownReportGenerator()
		reportOutput, err = gen.Generate(rpt)
	}
	if err != nil {
		return fmt.Errorf("generating report: %w", err)
	}

	// Output report
	if cfg.OutputFile != "" {
		if err := os.WriteFile(cfg.OutputFile, []byte(reportOutput), 0644); err != nil {
			return fmt.Errorf("writing report to %s: %w", cfg.OutputFile, err)
		}
		if !cfg.Quiet {
			fmt.Fprintf(os.Stderr, "Report written to %s\n", cfg.OutputFile)
		}
	} else {
		fmt.Print(reportOutput)
	}

	// Print summary
	if !cfg.Quiet {
		fmt.Fprintf(os.Stderr, "\nAnalysis complete in %s\n", duration.Round(time.Millisecond))
		fmt.Fprintf(os.Stderr, "  Files: %d | Classes: %d | Tests: %d\n", len(testFiles), totalClasses, totalTests)
		fmt.Fprintf(os.Stderr, "  Findings: %d (pass rate: %.1f%%)\n", stats.IssuesFound, stats.PassRate)
	}

	if strictClangErr != nil {
		return strictClangErr
	}

	// Check fail-on severity
	if cfg.FailOn != "" {
		exitCode := checkFailOn(filtered, cfg.FailOn)
		if exitCode > 0 {
			os.Exit(exitCode)
		}
	}

	return nil
}

// discoverTestFiles recursively finds .m test files in a directory.
func discoverTestFiles(root string) ([]string, error) {
	var files []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip inaccessible files
		}
		if info.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".m") {
			return nil
		}
		// Only include files that look like test files
		base := filepath.Base(path)
		if strings.HasSuffix(base, "Tests.m") || strings.HasSuffix(base, "Test.m") ||
			strings.Contains(base, "Test") {
			files = append(files, path)
		}
		return nil
	})
	return files, err
}

// parseTestFileSimple does a simple regex-based parse of an Objective-C test file.
// This doesn't require libclang and handles the common patterns.
func parseTestFileSimple(filePath string) (*models.TestFile, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	source := string(data)
	lines := strings.Split(source, "\n")

	tf := &models.TestFile{
		Path: filePath,
	}

	var currentClass *models.TestClass
	var currentMethod *models.TestMethod
	var methodBody strings.Builder
	braceDepth := 0
	inMethod := false

	for lineNum, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Detect @interface or @implementation for test classes
		if strings.HasPrefix(trimmed, "@implementation ") || strings.HasPrefix(trimmed, "@interface ") {
			parts := strings.Fields(trimmed)
			if len(parts) >= 2 {
				className := strings.TrimSuffix(parts[1], ":")
				className = strings.TrimSpace(className)
				if strings.Contains(className, "Test") || strings.HasSuffix(className, "Tests") {
					tc := models.TestClass{
						Name:     className,
						FilePath: filePath,
					}
					// Extract base class from interface
					if len(parts) > 2 && parts[0] == "@interface" {
						for _, p := range parts[2:] {
							clean := strings.Trim(p, ":(){}")
							if clean != "" && clean != "NSObject" {
								bc := clean
								tc.BaseClass = &bc
								break
							}
						}
					}
					tf.Classes = append(tf.Classes, tc)
					currentClass = &tf.Classes[len(tf.Classes)-1]
				}
			}
		}

		// Detect test methods
		if strings.HasPrefix(trimmed, "- (void)test") || strings.HasPrefix(trimmed, "-(void)test") {
			// XCTest methods must be parameterless selectors (no ':').
			if strings.Contains(trimmed, ":") {
				continue
			}
			// Extract method name
			name := extractMethodName(trimmed)
			if name != "" && currentClass != nil {
				if inMethod && currentMethod != nil {
					// Finish previous method
					currentMethod.SourceCode = methodBody.String()
					extractAssertionsFromSource(currentMethod)
					extractCommentsFromSource(currentMethod, lines, currentMethod.LineNumber)
				}
				currentClass.Methods = append(currentClass.Methods, models.TestMethod{
					Name:       name,
					ClassName:  currentClass.Name,
					LineNumber: lineNum + 1,
				})
				currentMethod = &currentClass.Methods[len(currentClass.Methods)-1]
				methodBody.Reset()
				inMethod = true
				braceDepth = 0
			}
		}

		if inMethod {
			methodBody.WriteString(line)
			methodBody.WriteString("\n")
			braceDepth += strings.Count(line, "{") - strings.Count(line, "}")
			if braceDepth <= 0 && strings.Contains(line, "}") && currentMethod != nil {
				currentMethod.SourceCode = methodBody.String()
				extractAssertionsFromSource(currentMethod)
				extractCommentsFromSource(currentMethod, lines, currentMethod.LineNumber)
				inMethod = false
				currentMethod = nil
			}
		}
	}

	// Handle case where last method wasn't closed
	if inMethod && currentMethod != nil {
		currentMethod.SourceCode = methodBody.String()
		extractAssertionsFromSource(currentMethod)
	}

	return tf, nil
}

// extractMethodName extracts the method name from a line like "- (void)testSomething {"
func extractMethodName(line string) string {
	// Find "test" in the line
	idx := strings.Index(line, "test")
	if idx < 0 {
		return ""
	}
	name := line[idx:]
	// Remove everything after space, bracket, or brace
	for i, ch := range name {
		if ch == ' ' || ch == '{' || ch == '(' || ch == ':' || ch == ';' {
			return name[:i]
		}
	}
	return name
}

// extractAssertionsFromSource populates assertions from the method's source code.
func extractAssertionsFromSource(method *models.TestMethod) {
	assertionTypes := []string{
		"XCTAssertEqual", "XCTAssertNotEqual",
		"XCTAssertTrue", "XCTAssertFalse",
		"XCTAssertNil", "XCTAssertNotNil",
		"XCTAssertThrows", "XCTAssertThrowsSpecific",
		"XCTAssertNoThrow", "XCTAssertNoThrowSpecific",
		"XCTAssertEqualObjects", "XCTAssertNotEqualObjects",
		"XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan", "XCTAssertLessThanOrEqual",
		"XCTAssertEqualWithAccuracy", "XCTAssertNotEqualWithAccuracy",
		"XCTFail",
	}

	lines := strings.Split(method.SourceCode, "\n")
	for lineIdx, line := range lines {
		trimmed := strings.TrimSpace(line)
		for _, assertType := range assertionTypes {
			if strings.Contains(trimmed, assertType+"(") || strings.Contains(trimmed, assertType+" (") {
				assertion := models.Assertion{
					Type:        assertType,
					LineNumber:  method.LineNumber + lineIdx,
					IsReachable: true,
				}
				// Extract arguments (simplified: get text between first ( and last ))
				start := strings.Index(trimmed, "(")
				end := strings.LastIndex(trimmed, ")")
				if start >= 0 && end > start {
					assertion.Arguments = []string{trimmed[start+1 : end]}
				}
				method.Assertions = append(method.Assertions, assertion)
				break // One assertion per line
			}
		}
	}

	// Apply basic reachability analysis
	analyzeReachability(method)
}

// extractCommentsFromSource extracts comments from the method and preceding lines.
func extractCommentsFromSource(method *models.TestMethod, allLines []string, startLine int) {
	// Look at the few lines before the method for doc comments
	commentStart := startLine - 4
	if commentStart < 0 {
		commentStart = 0
	}
	for i := commentStart; i < startLine-1 && i < len(allLines); i++ {
		trimmed := strings.TrimSpace(allLines[i])
		if strings.HasPrefix(trimmed, "//") || strings.HasPrefix(trimmed, "/*") || strings.HasPrefix(trimmed, "*") {
			method.Comments = append(method.Comments, trimmed)
		}
	}

	// Also extract inline comments from the method body
	bodyLines := strings.Split(method.SourceCode, "\n")
	for _, line := range bodyLines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			method.Comments = append(method.Comments, trimmed)
		}
	}
}

// checkFailOn returns an exit code based on the highest severity finding.
func checkFailOn(findings []validation.Finding, failOn string) int {
	severityOrder := map[string]int{
		"critical": 1,
		"high":     2,
		"medium":   3,
		"low":      4,
	}

	threshold, ok := severityOrder[strings.ToLower(failOn)]
	if !ok {
		return 0
	}

	highestSeverity := 0
	for _, f := range findings {
		sev := strings.ToLower(f.Severity.String())
		code, ok := severityOrder[sev]
		if ok && (highestSeverity == 0 || code < highestSeverity) {
			highestSeverity = code
		}
	}

	if highestSeverity > 0 && highestSeverity <= threshold {
		return highestSeverity
	}

	return 0
}

// analyzeReachability marks assertions as unreachable if they follow a return
// statement at the same brace depth (depth 0 = method body top level).
// Assertions inside Objective-C blocks (^{}) and nested scopes are considered
// reachable because blocks are closures that execute in their own context.
func analyzeReachability(method *models.TestMethod) {
	if len(method.Assertions) == 0 {
		return
	}

	lines := strings.Split(method.SourceCode, "\n")

	// Track lines where a return statement occurs at depth 0 (method body level)
	returnAtDepthZero := -1
	depth := 0

	for lineIdx, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Skip the method signature line
		if lineIdx == 0 && (strings.HasPrefix(trimmed, "- (void)") || strings.HasPrefix(trimmed, "-(void)")) {
			depth += strings.Count(line, "{") - strings.Count(line, "}")
			continue
		}

		// Track brace depth relative to method body
		depth += strings.Count(line, "{") - strings.Count(line, "}")

		// Only consider return statements at depth 0 (method body level)
		// Depth <= 1 because we start inside the method body's outer braces
		if depth <= 1 && (trimmed == "return;" || strings.HasPrefix(trimmed, "return ")) {
			absLine := method.LineNumber + lineIdx
			if returnAtDepthZero < 0 || absLine < returnAtDepthZero {
				returnAtDepthZero = absLine
			}
		}
	}

	// Mark assertions as unreachable only if they come after a return at depth 0
	if returnAtDepthZero > 0 {
		for i := range method.Assertions {
			if method.Assertions[i].LineNumber > returnAtDepthZero {
				method.Assertions[i].IsReachable = false
			}
		}
	}
}
