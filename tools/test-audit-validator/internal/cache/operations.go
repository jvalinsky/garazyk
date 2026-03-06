package cache

import (
	"fmt"
	"os"
	"time"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

// GetCachedFindings retrieves cached findings for a file if the cache is valid.
// Returns findings and true if cache hit, nil and false if cache miss.
func (cm *CacheManager) GetCachedFindings(filePath, currentHash string) ([]validation.Finding, bool, error) {
	var storedHash string
	err := cm.db.QueryRow(
		"SELECT file_hash FROM cache_entries WHERE file_path = ?",
		filePath,
	).Scan(&storedHash)
	if err != nil {
		return nil, false, nil // cache miss
	}

	if storedHash != currentHash {
		return nil, false, nil // hash mismatch
	}

	rows, err := cm.db.Query(
		`SELECT rule_name, severity, test_method, test_class, line_number,
		        message, recommendation, confidence
		 FROM cached_findings WHERE file_path = ?`,
		filePath,
	)
	if err != nil {
		return nil, false, fmt.Errorf("querying cached findings: %w", err)
	}
	defer rows.Close()

	var findings []validation.Finding
	for rows.Next() {
		var f validation.Finding
		var sevStr string
		if err := rows.Scan(
			&f.RuleName, &sevStr, &f.TestMethod, &f.TestClass,
			&f.LineNumber, &f.Message, &f.Recommendation, &f.Confidence,
		); err != nil {
			return nil, false, fmt.Errorf("scanning cached finding: %w", err)
		}
		sev, ok := validation.ParseSeverity(sevStr)
		if !ok {
			return nil, false, fmt.Errorf("unknown severity %q in cache", sevStr)
		}
		f.Severity = sev
		f.FilePath = filePath
		findings = append(findings, f)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterating cached findings: %w", err)
	}

	return findings, true, nil
}

// StoreFindingsInCache saves analysis findings for a file
func (cm *CacheManager) StoreFindingsInCache(filePath, fileHash string, findings []validation.Finding) error {
	tx, err := cm.db.Begin()
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback()

	// Remove old entries for this file
	if _, err := tx.Exec("DELETE FROM cached_findings WHERE file_path = ?", filePath); err != nil {
		return fmt.Errorf("deleting old findings: %w", err)
	}
	if _, err := tx.Exec("DELETE FROM dependency_hashes WHERE file_path = ?", filePath); err != nil {
		return fmt.Errorf("deleting old dependency hashes: %w", err)
	}
	if _, err := tx.Exec("DELETE FROM cache_entries WHERE file_path = ?", filePath); err != nil {
		return fmt.Errorf("deleting old cache entry: %w", err)
	}

	// Insert new cache entry
	now := time.Now().UTC().Format(time.RFC3339)
	if _, err := tx.Exec(
		"INSERT INTO cache_entries (file_path, file_hash, modified_at, analyzed_at) VALUES (?, ?, ?, ?)",
		filePath, fileHash, now, now,
	); err != nil {
		return fmt.Errorf("inserting cache entry: %w", err)
	}

	// Insert findings
	stmt, err := tx.Prepare(
		`INSERT INTO cached_findings
		 (file_path, rule_name, severity, test_method, test_class, line_number,
		  message, recommendation, confidence)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
	)
	if err != nil {
		return fmt.Errorf("preparing findings insert: %w", err)
	}
	defer stmt.Close()

	for _, f := range findings {
		if _, err := stmt.Exec(
			filePath, f.RuleName, f.Severity.String(), f.TestMethod, f.TestClass,
			f.LineNumber, f.Message, f.Recommendation, f.Confidence,
		); err != nil {
			return fmt.Errorf("inserting finding: %w", err)
		}
	}

	return tx.Commit()
}

// InvalidateFile removes cached data for a specific file
func (cm *CacheManager) InvalidateFile(filePath string) error {
	_, err := cm.db.Exec("DELETE FROM cache_entries WHERE file_path = ?", filePath)
	if err != nil {
		return fmt.Errorf("invalidating cache for %s: %w", filePath, err)
	}
	return nil
}

// CleanStaleEntries removes cache entries for files that no longer exist on disk
func (cm *CacheManager) CleanStaleEntries() (int, error) {
	rows, err := cm.db.Query("SELECT file_path FROM cache_entries")
	if err != nil {
		return 0, fmt.Errorf("querying cache entries: %w", err)
	}
	defer rows.Close()

	var stalePaths []string
	for rows.Next() {
		var fp string
		if err := rows.Scan(&fp); err != nil {
			return 0, fmt.Errorf("scanning file path: %w", err)
		}
		if _, err := os.Stat(fp); os.IsNotExist(err) {
			stalePaths = append(stalePaths, fp)
		}
	}
	if err := rows.Err(); err != nil {
		return 0, fmt.Errorf("iterating cache entries: %w", err)
	}

	for _, fp := range stalePaths {
		if _, err := cm.db.Exec("DELETE FROM cache_entries WHERE file_path = ?", fp); err != nil {
			return 0, fmt.Errorf("deleting stale entry %s: %w", fp, err)
		}
	}

	return len(stalePaths), nil
}

// StoreDependencyHash records a dependency hash for a file
func (cm *CacheManager) StoreDependencyHash(filePath, depPath, depHash string) error {
	_, err := cm.db.Exec(
		`INSERT OR REPLACE INTO dependency_hashes (file_path, dependency_path, dependency_hash)
		 VALUES (?, ?, ?)`,
		filePath, depPath, depHash,
	)
	if err != nil {
		return fmt.Errorf("storing dependency hash: %w", err)
	}
	return nil
}

// GetDependencyHashes retrieves stored dependency hashes for a file
func (cm *CacheManager) GetDependencyHashes(filePath string) (map[string]string, error) {
	rows, err := cm.db.Query(
		"SELECT dependency_path, dependency_hash FROM dependency_hashes WHERE file_path = ?",
		filePath,
	)
	if err != nil {
		return nil, fmt.Errorf("querying dependency hashes: %w", err)
	}
	defer rows.Close()

	hashes := make(map[string]string)
	for rows.Next() {
		var depPath, depHash string
		if err := rows.Scan(&depPath, &depHash); err != nil {
			return nil, fmt.Errorf("scanning dependency hash: %w", err)
		}
		hashes[depPath] = depHash
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating dependency hashes: %w", err)
	}

	return hashes, nil
}
