package cache

import (
	"fmt"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

// IncrementalAnalyzer coordinates incremental analysis using the cache
type IncrementalAnalyzer struct {
	cache *CacheManager
}

// NewIncrementalAnalyzer creates a new IncrementalAnalyzer
func NewIncrementalAnalyzer(cache *CacheManager) *IncrementalAnalyzer {
	return &IncrementalAnalyzer{cache: cache}
}

// ShouldAnalyze checks if a file needs re-analysis.
// Returns true if file has changed or is not cached.
func (ia *IncrementalAnalyzer) ShouldAnalyze(filePath string) (bool, error) {
	currentHash, err := CalculateFileHash(filePath)
	if err != nil {
		return true, fmt.Errorf("hashing file %s: %w", filePath, err)
	}

	_, hit, err := ia.cache.GetCachedFindings(filePath, currentHash)
	if err != nil {
		return true, fmt.Errorf("checking cache for %s: %w", filePath, err)
	}

	return !hit, nil
}

// GetCachedOrAnalyze returns cached findings if available, or signals that analysis is needed.
// Returns (findings, fromCache, error).
func (ia *IncrementalAnalyzer) GetCachedOrAnalyze(filePath string) ([]validation.Finding, bool, error) {
	currentHash, err := CalculateFileHash(filePath)
	if err != nil {
		return nil, false, fmt.Errorf("hashing file %s: %w", filePath, err)
	}

	findings, hit, err := ia.cache.GetCachedFindings(filePath, currentHash)
	if err != nil {
		return nil, false, fmt.Errorf("checking cache for %s: %w", filePath, err)
	}

	return findings, hit, nil
}

// CacheResults stores analysis results for future use
func (ia *IncrementalAnalyzer) CacheResults(filePath string, findings []validation.Finding) error {
	fileHash, err := CalculateFileHash(filePath)
	if err != nil {
		return fmt.Errorf("hashing file %s: %w", filePath, err)
	}

	return ia.cache.StoreFindingsInCache(filePath, fileHash, findings)
}
