package cache

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

func newTestCacheManager(t *testing.T) *CacheManager {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "test_cache.db")
	cm, err := NewCacheManager(dbPath)
	if err != nil {
		t.Fatalf("NewCacheManager: %v", err)
	}
	t.Cleanup(func() { cm.Close() })
	return cm
}

func sampleFindings() []validation.Finding {
	return []validation.Finding{
		{
			RuleName:       "test-rule-1",
			Severity:       validation.HIGH,
			TestMethod:     "testExample",
			TestClass:      "ExampleTests",
			FilePath:       "/tmp/test.m",
			LineNumber:     42,
			Message:        "Test does not assert anything",
			Recommendation: "Add assertions",
			Confidence:     0.95,
		},
		{
			RuleName:       "test-rule-2",
			Severity:       validation.LOW,
			TestMethod:     "testOther",
			TestClass:      "OtherTests",
			FilePath:       "/tmp/test.m",
			LineNumber:     100,
			Message:        "Weak assertion",
			Recommendation: "Use stronger assertion",
			Confidence:     0.7,
		},
	}
}

func TestNewCacheManager(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "cache.db")
	cm, err := NewCacheManager(dbPath)
	if err != nil {
		t.Fatalf("NewCacheManager: %v", err)
	}
	defer cm.Close()

	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		t.Error("database file was not created")
	}

	// Verify schema by inserting into each table
	_, err = cm.db.Exec(
		"INSERT INTO cache_entries (file_path, file_hash, modified_at, analyzed_at) VALUES (?, ?, ?, ?)",
		"/test", "abc", "2024-01-01", "2024-01-01",
	)
	if err != nil {
		t.Fatalf("cache_entries table not usable: %v", err)
	}
}

func TestCacheManager_StoreAndRetrieve(t *testing.T) {
	cm := newTestCacheManager(t)
	filePath := "/tmp/test.m"
	fileHash := "abc123"
	findings := sampleFindings()

	if err := cm.StoreFindingsInCache(filePath, fileHash, findings); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	got, hit, err := cm.GetCachedFindings(filePath, fileHash)
	if err != nil {
		t.Fatalf("GetCachedFindings: %v", err)
	}
	if !hit {
		t.Fatal("expected cache hit")
	}
	if len(got) != len(findings) {
		t.Fatalf("got %d findings, want %d", len(got), len(findings))
	}

	for i, f := range got {
		want := findings[i]
		if f.RuleName != want.RuleName {
			t.Errorf("[%d] RuleName = %q, want %q", i, f.RuleName, want.RuleName)
		}
		if f.Severity != want.Severity {
			t.Errorf("[%d] Severity = %v, want %v", i, f.Severity, want.Severity)
		}
		if f.TestMethod != want.TestMethod {
			t.Errorf("[%d] TestMethod = %q, want %q", i, f.TestMethod, want.TestMethod)
		}
		if f.TestClass != want.TestClass {
			t.Errorf("[%d] TestClass = %q, want %q", i, f.TestClass, want.TestClass)
		}
		if f.LineNumber != want.LineNumber {
			t.Errorf("[%d] LineNumber = %d, want %d", i, f.LineNumber, want.LineNumber)
		}
		if f.Message != want.Message {
			t.Errorf("[%d] Message = %q, want %q", i, f.Message, want.Message)
		}
		if f.Recommendation != want.Recommendation {
			t.Errorf("[%d] Recommendation = %q, want %q", i, f.Recommendation, want.Recommendation)
		}
		if f.Confidence != want.Confidence {
			t.Errorf("[%d] Confidence = %f, want %f", i, f.Confidence, want.Confidence)
		}
	}
}

func TestCacheManager_CacheMiss(t *testing.T) {
	cm := newTestCacheManager(t)

	got, hit, err := cm.GetCachedFindings("/nonexistent", "somehash")
	if err != nil {
		t.Fatalf("GetCachedFindings: %v", err)
	}
	if hit {
		t.Error("expected cache miss for unknown file")
	}
	if got != nil {
		t.Errorf("expected nil findings, got %v", got)
	}
}

func TestCacheManager_CacheInvalidation(t *testing.T) {
	cm := newTestCacheManager(t)
	filePath := "/tmp/test.m"

	if err := cm.StoreFindingsInCache(filePath, "hash1", sampleFindings()); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	// Different hash should miss
	_, hit, err := cm.GetCachedFindings(filePath, "hash2")
	if err != nil {
		t.Fatalf("GetCachedFindings: %v", err)
	}
	if hit {
		t.Error("expected cache miss when hash differs")
	}
}

func TestCacheManager_InvalidateFile(t *testing.T) {
	cm := newTestCacheManager(t)
	filePath := "/tmp/test.m"

	if err := cm.StoreFindingsInCache(filePath, "hash1", sampleFindings()); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	if err := cm.InvalidateFile(filePath); err != nil {
		t.Fatalf("InvalidateFile: %v", err)
	}

	_, hit, err := cm.GetCachedFindings(filePath, "hash1")
	if err != nil {
		t.Fatalf("GetCachedFindings: %v", err)
	}
	if hit {
		t.Error("expected cache miss after invalidation")
	}
}

func TestCacheManager_CleanStaleEntries(t *testing.T) {
	cm := newTestCacheManager(t)

	// Store entry for a file that doesn't exist
	fakePath := filepath.Join(t.TempDir(), "nonexistent.m")
	if err := cm.StoreFindingsInCache(fakePath, "hash1", sampleFindings()); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	// Store entry for a file that does exist
	realFile := filepath.Join(t.TempDir(), "real.m")
	if err := os.WriteFile(realFile, []byte("test"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	if err := cm.StoreFindingsInCache(realFile, "hash2", nil); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	cleaned, err := cm.CleanStaleEntries()
	if err != nil {
		t.Fatalf("CleanStaleEntries: %v", err)
	}
	if cleaned != 1 {
		t.Errorf("cleaned %d entries, want 1", cleaned)
	}

	// Stale entry should be gone
	_, hit, _ := cm.GetCachedFindings(fakePath, "hash1")
	if hit {
		t.Error("stale entry still present after cleaning")
	}

	// Real entry should remain
	_, hit, _ = cm.GetCachedFindings(realFile, "hash2")
	if !hit {
		t.Error("real entry was incorrectly cleaned")
	}
}

func TestCalculateFileHash(t *testing.T) {
	tmpFile := filepath.Join(t.TempDir(), "hashtest.txt")
	content := []byte("hello world\n")
	if err := os.WriteFile(tmpFile, content, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	hash1, err := CalculateFileHash(tmpFile)
	if err != nil {
		t.Fatalf("CalculateFileHash: %v", err)
	}
	if hash1 == "" {
		t.Fatal("empty hash")
	}

	// Same content should produce same hash
	hash2, err := CalculateFileHash(tmpFile)
	if err != nil {
		t.Fatalf("CalculateFileHash: %v", err)
	}
	if hash1 != hash2 {
		t.Errorf("hash not consistent: %q vs %q", hash1, hash2)
	}

	// Different content should produce different hash
	if err := os.WriteFile(tmpFile, []byte("different"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	hash3, err := CalculateFileHash(tmpFile)
	if err != nil {
		t.Fatalf("CalculateFileHash: %v", err)
	}
	if hash1 == hash3 {
		t.Error("different content produced same hash")
	}
}

func TestCalculateCacheKey(t *testing.T) {
	deps := map[string]string{
		"b.m": "hash_b",
		"a.m": "hash_a",
	}

	key1 := CalculateCacheKey("filehash", deps)
	if key1 == "" {
		t.Fatal("empty cache key")
	}

	// Same inputs should produce same key
	key2 := CalculateCacheKey("filehash", deps)
	if key1 != key2 {
		t.Errorf("cache key not deterministic: %q vs %q", key1, key2)
	}

	// Different file hash should produce different key
	key3 := CalculateCacheKey("otherhash", deps)
	if key1 == key3 {
		t.Error("different file hash produced same cache key")
	}
}

func TestIncrementalAnalyzer_ShouldAnalyze(t *testing.T) {
	cm := newTestCacheManager(t)
	ia := NewIncrementalAnalyzer(cm)

	tmpFile := filepath.Join(t.TempDir(), "analyze.m")
	if err := os.WriteFile(tmpFile, []byte("@implementation Test @end"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// New file should need analysis
	needed, err := ia.ShouldAnalyze(tmpFile)
	if err != nil {
		t.Fatalf("ShouldAnalyze: %v", err)
	}
	if !needed {
		t.Error("new file should need analysis")
	}
}

func TestIncrementalAnalyzer_CachedResults(t *testing.T) {
	cm := newTestCacheManager(t)
	ia := NewIncrementalAnalyzer(cm)

	tmpFile := filepath.Join(t.TempDir(), "cached.m")
	if err := os.WriteFile(tmpFile, []byte("@implementation Test @end"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	findings := sampleFindings()
	if err := ia.CacheResults(tmpFile, findings); err != nil {
		t.Fatalf("CacheResults: %v", err)
	}

	// File should not need re-analysis
	needed, err := ia.ShouldAnalyze(tmpFile)
	if err != nil {
		t.Fatalf("ShouldAnalyze: %v", err)
	}
	if needed {
		t.Error("cached file should not need re-analysis")
	}

	// GetCachedOrAnalyze should return cached findings
	got, fromCache, err := ia.GetCachedOrAnalyze(tmpFile)
	if err != nil {
		t.Fatalf("GetCachedOrAnalyze: %v", err)
	}
	if !fromCache {
		t.Error("expected fromCache=true")
	}
	if len(got) != len(findings) {
		t.Errorf("got %d findings, want %d", len(got), len(findings))
	}
}

func TestStoreDependencyHash(t *testing.T) {
	cm := newTestCacheManager(t)
	filePath := "/tmp/test.m"

	// Must store a cache entry first (foreign key)
	if err := cm.StoreFindingsInCache(filePath, "hash1", nil); err != nil {
		t.Fatalf("StoreFindingsInCache: %v", err)
	}

	if err := cm.StoreDependencyHash(filePath, "/tmp/dep1.h", "dephash1"); err != nil {
		t.Fatalf("StoreDependencyHash: %v", err)
	}
	if err := cm.StoreDependencyHash(filePath, "/tmp/dep2.h", "dephash2"); err != nil {
		t.Fatalf("StoreDependencyHash: %v", err)
	}

	hashes, err := cm.GetDependencyHashes(filePath)
	if err != nil {
		t.Fatalf("GetDependencyHashes: %v", err)
	}

	if len(hashes) != 2 {
		t.Fatalf("got %d dependency hashes, want 2", len(hashes))
	}
	if hashes["/tmp/dep1.h"] != "dephash1" {
		t.Errorf("dep1 hash = %q, want %q", hashes["/tmp/dep1.h"], "dephash1")
	}
	if hashes["/tmp/dep2.h"] != "dephash2" {
		t.Errorf("dep2 hash = %q, want %q", hashes["/tmp/dep2.h"], "dephash2")
	}
}
