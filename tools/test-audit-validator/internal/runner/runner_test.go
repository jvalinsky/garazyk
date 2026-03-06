package runner

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/september-pds/test-audit-validator/internal/config"
	"github.com/september-pds/test-audit-validator/internal/models"
	"github.com/september-pds/test-audit-validator/internal/validation"
)

func mockAnalyzer(filePath string) (*models.TestFile, error) {
	return &models.TestFile{
		Path: filePath,
		Classes: []models.TestClass{
			{
				Name: "TestClass",
				Methods: []models.TestMethod{
					{Name: "testExample", SourceCode: "XCTAssertTrue(YES);"},
				},
			},
		},
	}, nil
}

func testConfig() *config.Config {
	cfg := config.DefaultConfig()
	cfg.Workers = 2
	return cfg
}

func TestRunner_BasicAnalysis(t *testing.T) {
	engine := validation.NewEngine(nil)
	cfg := testConfig()

	tmpFile, err := os.CreateTemp("", "test-*.m")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmpFile.Name())
	tmpFile.WriteString("// test file content")
	tmpFile.Close()

	r := NewRunner(engine, mockAnalyzer, cfg)
	results := r.Run(context.Background(), []string{tmpFile.Name()})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Error != nil {
		t.Fatalf("unexpected error: %v", results[0].Error)
	}
	if results[0].FilePath != tmpFile.Name() {
		t.Errorf("expected file path %s, got %s", tmpFile.Name(), results[0].FilePath)
	}
	if results[0].FromCache {
		t.Error("expected FromCache=false")
	}
}

func TestRunner_ParallelExecution(t *testing.T) {
	engine := validation.NewEngine(nil)
	cfg := testConfig()
	cfg.Workers = 4

	var tmpFiles []string
	for i := 0; i < 10; i++ {
		f, err := os.CreateTemp("", fmt.Sprintf("test-%d-*.m", i))
		if err != nil {
			t.Fatal(err)
		}
		f.WriteString("// test content")
		f.Close()
		tmpFiles = append(tmpFiles, f.Name())
		defer os.Remove(f.Name())
	}

	r := NewRunner(engine, mockAnalyzer, cfg)
	results := r.Run(context.Background(), tmpFiles)

	if len(results) != 10 {
		t.Fatalf("expected 10 results, got %d", len(results))
	}

	seen := make(map[string]bool)
	for _, res := range results {
		if res.Error != nil {
			t.Errorf("unexpected error for %s: %v", res.FilePath, res.Error)
		}
		seen[res.FilePath] = true
	}
	for _, fp := range tmpFiles {
		if !seen[fp] {
			t.Errorf("missing result for %s", fp)
		}
	}
}

func TestRunner_FileSizeLimit(t *testing.T) {
	engine := validation.NewEngine(nil)
	cfg := testConfig()
	cfg.MaxFileSize = 10

	f, err := os.CreateTemp("", "test-big-*.m")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(f.Name())
	f.WriteString(strings.Repeat("x", 100))
	f.Close()

	r := NewRunner(engine, mockAnalyzer, cfg)
	results := r.Run(context.Background(), []string{f.Name()})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Error == nil {
		t.Fatal("expected error for oversized file")
	}
	if !strings.Contains(results[0].Error.Error(), "exceeds size limit") {
		t.Errorf("expected size limit error, got: %v", results[0].Error)
	}
}

func TestRunner_FileTimeout(t *testing.T) {
	engine := validation.NewEngine(nil)
	cfg := testConfig()
	cfg.FileTimeout = 1

	slowAnalyzer := func(filePath string) (*models.TestFile, error) {
		time.Sleep(5 * time.Second)
		return mockAnalyzer(filePath)
	}

	f, err := os.CreateTemp("", "test-slow-*.m")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(f.Name())
	f.WriteString("// content")
	f.Close()

	r := NewRunner(engine, slowAnalyzer, cfg)
	start := time.Now()
	results := r.Run(context.Background(), []string{f.Name()})
	elapsed := time.Since(start)

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Error == nil {
		t.Fatal("expected timeout error")
	}
	if elapsed > 3*time.Second {
		t.Errorf("timeout took too long: %v", elapsed)
	}
}

func TestRunner_IncrementalAnalysis(t *testing.T) {
	// Since IncrementalAnalyzer requires a real CacheManager with SQLite,
	// we verify the non-incremental path works correctly and that the
	// runner handles nil incremental analyzer.
	engine := validation.NewEngine(nil)
	cfg := testConfig()
	cfg.Incremental = true

	f, err := os.CreateTemp("", "test-inc-*.m")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(f.Name())
	f.WriteString("// content")
	f.Close()

	var callCount int32
	countingAnalyzer := func(filePath string) (*models.TestFile, error) {
		atomic.AddInt32(&callCount, 1)
		return mockAnalyzer(filePath)
	}

	r := NewRunner(engine, countingAnalyzer, cfg)
	// No incremental analyzer set — should still work
	results := r.Run(context.Background(), []string{f.Name()})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Error != nil {
		t.Fatalf("unexpected error: %v", results[0].Error)
	}
	if results[0].FromCache {
		t.Error("expected FromCache=false without incremental analyzer")
	}
	if atomic.LoadInt32(&callCount) != 1 {
		t.Errorf("expected analyzer called once, got %d", callCount)
	}
}

func TestProgressReporter_Tracking(t *testing.T) {
	var buf bytes.Buffer
	pr := NewProgressReporter(&buf, 10, false)

	for i := 0; i < 5; i++ {
		pr.ReportFile(fmt.Sprintf("Tests/file%d.m", i), false, 100*time.Millisecond, nil)
	}
	pr.ReportFile("Tests/cached.m", true, 0, nil)

	progress := pr.Progress()
	if progress != 60 {
		t.Errorf("expected 60%% progress, got %.1f%%", progress)
	}

	rate := pr.Rate()
	if rate <= 0 {
		t.Errorf("expected positive rate, got %f", rate)
	}

	eta := pr.ETA()
	if eta <= 0 {
		t.Errorf("expected positive ETA, got %v", eta)
	}

	output := buf.String()
	if !strings.Contains(output, "Analyzing:") {
		t.Error("expected 'Analyzing:' in output")
	}
	if !strings.Contains(output, "Cached:") {
		t.Error("expected 'Cached:' in output")
	}
}

func TestProgressReporter_Quiet(t *testing.T) {
	var buf bytes.Buffer
	pr := NewProgressReporter(&buf, 3, true)

	pr.ReportFile("Tests/file1.m", false, 100*time.Millisecond, nil)
	pr.ReportFile("Tests/file2.m", true, 0, nil)
	pr.ReportFile("Tests/file3.m", false, 0, fmt.Errorf("parse error"))

	if buf.Len() != 0 {
		t.Errorf("expected no output in quiet mode, got: %s", buf.String())
	}

	progress := pr.Progress()
	if progress != 100 {
		t.Errorf("expected 100%% progress, got %.1f%%", progress)
	}

	pr.ReportSummary()
	output := buf.String()
	if !strings.Contains(output, "Analysis complete:") {
		t.Error("expected summary output even in quiet mode")
	}
	if !strings.Contains(output, "1 cached") {
		t.Error("expected cached count in summary")
	}
	if !strings.Contains(output, "1 errors") {
		t.Error("expected error count in summary")
	}
}

func TestCheckFileSize(t *testing.T) {
	small, err := os.CreateTemp("", "test-small-*.m")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(small.Name())
	small.WriteString("small")
	small.Close()

	if err := CheckFileSize(small.Name(), 1024); err != nil {
		t.Errorf("expected no error for small file, got: %v", err)
	}

	if err := CheckFileSize(small.Name(), 1); err == nil {
		t.Error("expected error for file exceeding limit")
	}

	if err := CheckFileSize("/nonexistent/file.m", 1024); err == nil {
		t.Error("expected error for nonexistent file")
	}
}
