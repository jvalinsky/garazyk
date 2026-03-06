package runner

import (
	"fmt"
	"io"
	"path/filepath"
	"sync"
	"time"
)

// ProgressReporter reports analysis progress.
type ProgressReporter struct {
	mu        sync.Mutex
	writer    io.Writer
	total     int
	completed int
	cached    int
	errors    int
	startTime time.Time
	quiet     bool
}

// NewProgressReporter creates a new ProgressReporter.
func NewProgressReporter(writer io.Writer, total int, quiet bool) *ProgressReporter {
	return &ProgressReporter{
		writer:    writer,
		total:     total,
		quiet:     quiet,
		startTime: time.Now(),
	}
}

// ReportFile reports progress for a single file.
func (pr *ProgressReporter) ReportFile(filePath string, fromCache bool, dur time.Duration, err error) {
	pr.mu.Lock()
	defer pr.mu.Unlock()

	pr.completed++
	if fromCache {
		pr.cached++
	}
	if err != nil {
		pr.errors++
	}

	if pr.quiet {
		return
	}

	short := filepath.Base(filePath)
	if dir := filepath.Dir(filePath); dir != "." {
		short = filepath.Join(filepath.Base(dir), short)
	}

	if err != nil {
		fmt.Fprintf(pr.writer, "[%d/%d] Error: %s (%v)\n", pr.completed, pr.total, short, err)
	} else if fromCache {
		fmt.Fprintf(pr.writer, "[%d/%d] Cached: %s\n", pr.completed, pr.total, short)
	} else {
		fmt.Fprintf(pr.writer, "[%d/%d] Analyzing: %s (%.1fs)\n", pr.completed, pr.total, short, dur.Seconds())
	}
}

// ReportSummary prints the final summary.
func (pr *ProgressReporter) ReportSummary() {
	pr.mu.Lock()
	defer pr.mu.Unlock()

	elapsed := time.Since(pr.startTime)
	analyzed := pr.completed - pr.cached - pr.errors
	rate := float64(pr.completed) / elapsed.Seconds()

	fmt.Fprintf(pr.writer, "\nAnalysis complete: %d files (%d analyzed, %d cached, %d errors) in %.1fs (%.1f files/sec)\n",
		pr.completed, analyzed, pr.cached, pr.errors, elapsed.Seconds(), rate)
}

// Progress returns current progress as a percentage.
func (pr *ProgressReporter) Progress() float64 {
	pr.mu.Lock()
	defer pr.mu.Unlock()

	if pr.total == 0 {
		return 0
	}
	return float64(pr.completed) / float64(pr.total) * 100
}

// Rate returns files processed per second.
func (pr *ProgressReporter) Rate() float64 {
	pr.mu.Lock()
	defer pr.mu.Unlock()

	elapsed := time.Since(pr.startTime).Seconds()
	if elapsed == 0 {
		return 0
	}
	return float64(pr.completed) / elapsed
}

// ETA returns estimated time remaining.
func (pr *ProgressReporter) ETA() time.Duration {
	pr.mu.Lock()
	defer pr.mu.Unlock()

	if pr.completed == 0 {
		return 0
	}
	elapsed := time.Since(pr.startTime)
	remaining := pr.total - pr.completed
	perFile := elapsed / time.Duration(pr.completed)
	return perFile * time.Duration(remaining)
}
