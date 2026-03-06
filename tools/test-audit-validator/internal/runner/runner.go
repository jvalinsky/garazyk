package runner

import (
	"context"
	"runtime"
	"sync"
	"time"

	"github.com/september-pds/test-audit-validator/internal/cache"
	"github.com/september-pds/test-audit-validator/internal/config"
	"github.com/september-pds/test-audit-validator/internal/models"
	"github.com/september-pds/test-audit-validator/internal/validation"
)

// FileAnalyzer is a function that parses and analyzes a single test file.
// This abstraction allows the runner to be independent of the parser implementation.
type FileAnalyzer func(filePath string) (*models.TestFile, error)

// Result holds the analysis result for a single file.
type Result struct {
	FilePath  string
	Findings  []validation.Finding
	FromCache bool
	Duration  time.Duration
	Error     error
}

// Runner orchestrates parallel analysis of test files.
type Runner struct {
	engine      *validation.Engine
	analyzer    FileAnalyzer
	incremental *cache.IncrementalAnalyzer
	config      *config.Config
	progress    *ProgressReporter
}

// NewRunner creates a new analysis runner.
func NewRunner(engine *validation.Engine, analyzer FileAnalyzer, cfg *config.Config) *Runner {
	return &Runner{
		engine:   engine,
		analyzer: analyzer,
		config:   cfg,
	}
}

// SetIncrementalAnalyzer enables incremental analysis.
func (r *Runner) SetIncrementalAnalyzer(ia *cache.IncrementalAnalyzer) {
	r.incremental = ia
}

// SetProgressReporter enables progress reporting.
func (r *Runner) SetProgressReporter(pr *ProgressReporter) {
	r.progress = pr
}

// Run executes analysis on all provided file paths and returns aggregated results.
func (r *Runner) Run(ctx context.Context, filePaths []string) []Result {
	workers := r.config.Workers
	if workers <= 0 {
		workers = runtime.NumCPU()
	}
	if workers > len(filePaths) {
		workers = len(filePaths)
	}

	maxFileSize := r.config.MaxFileSize
	if maxFileSize <= 0 {
		maxFileSize = DefaultMaxFileSize
	}

	fileTimeout := r.config.FileTimeout
	if fileTimeout <= 0 {
		fileTimeout = DefaultFileTimeout
	}

	work := make(chan string, len(filePaths))
	results := make(chan Result, len(filePaths))

	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for filePath := range work {
				res := r.processFile(ctx, filePath, maxFileSize, fileTimeout)
				results <- res
			}
		}()
	}

	for _, fp := range filePaths {
		work <- fp
	}
	close(work)

	go func() {
		wg.Wait()
		close(results)
	}()

	var collected []Result
	for res := range results {
		collected = append(collected, res)
	}
	return collected
}

func (r *Runner) processFile(ctx context.Context, filePath string, maxFileSize int64, fileTimeout int) Result {
	start := time.Now()

	if err := CheckFileSize(filePath, maxFileSize); err != nil {
		res := Result{FilePath: filePath, Error: err, Duration: time.Since(start)}
		r.reportProgress(filePath, false, res.Duration, err)
		return res
	}

	if r.incremental != nil {
		findings, fromCache, err := r.incremental.GetCachedOrAnalyze(filePath)
		if err == nil && fromCache {
			dur := time.Since(start)
			r.reportProgress(filePath, true, dur, nil)
			return Result{FilePath: filePath, Findings: findings, FromCache: true, Duration: dur}
		}
	}

	fileCtx, cancel := context.WithTimeout(ctx, time.Duration(fileTimeout)*time.Second)
	defer cancel()

	type analyzeResult struct {
		file *models.TestFile
		err  error
	}
	ch := make(chan analyzeResult, 1)
	go func() {
		tf, err := r.analyzer(filePath)
		ch <- analyzeResult{file: tf, err: err}
	}()

	select {
	case <-fileCtx.Done():
		dur := time.Since(start)
		err := fileCtx.Err()
		r.reportProgress(filePath, false, dur, err)
		return Result{FilePath: filePath, Error: err, Duration: dur}
	case ar := <-ch:
		if ar.err != nil {
			dur := time.Since(start)
			r.reportProgress(filePath, false, dur, ar.err)
			return Result{FilePath: filePath, Error: ar.err, Duration: dur}
		}

		findings := r.engine.ValidateTestFile(ar.file)

		if r.incremental != nil {
			_ = r.incremental.CacheResults(filePath, findings)
		}

		dur := time.Since(start)
		r.reportProgress(filePath, false, dur, nil)
		return Result{FilePath: filePath, Findings: findings, Duration: dur}
	}
}

func (r *Runner) reportProgress(filePath string, fromCache bool, dur time.Duration, err error) {
	if r.progress != nil {
		r.progress.ReportFile(filePath, fromCache, dur, err)
	}
}
