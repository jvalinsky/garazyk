package cache

import (
	"database/sql"
	"fmt"

	_ "github.com/mattn/go-sqlite3"
)

// CacheManager manages SQLite-based analysis cache
type CacheManager struct {
	db     *sql.DB
	dbPath string
}

// NewCacheManager creates a new cache manager with the given database path
func NewCacheManager(dbPath string) (*CacheManager, error) {
	db, err := sql.Open("sqlite3", dbPath+"?_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("opening cache database: %w", err)
	}

	cm := &CacheManager{
		db:     db,
		dbPath: dbPath,
	}

	if err := cm.initSchema(); err != nil {
		db.Close()
		return nil, fmt.Errorf("initializing cache schema: %w", err)
	}

	return cm, nil
}

// Close closes the database connection
func (cm *CacheManager) Close() error {
	return cm.db.Close()
}

// initSchema creates the cache tables if they don't exist
func (cm *CacheManager) initSchema() error {
	schema := `
CREATE TABLE IF NOT EXISTS cache_entries (
    file_path TEXT PRIMARY KEY,
    file_hash TEXT NOT NULL,
    modified_at TEXT NOT NULL,
    analyzed_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cached_findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    rule_name TEXT NOT NULL,
    severity TEXT NOT NULL,
    test_method TEXT NOT NULL,
    test_class TEXT NOT NULL,
    line_number INTEGER NOT NULL,
    message TEXT NOT NULL,
    recommendation TEXT NOT NULL,
    confidence REAL NOT NULL,
    FOREIGN KEY (file_path) REFERENCES cache_entries(file_path) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dependency_hashes (
    file_path TEXT NOT NULL,
    dependency_path TEXT NOT NULL,
    dependency_hash TEXT NOT NULL,
    PRIMARY KEY (file_path, dependency_path),
    FOREIGN KEY (file_path) REFERENCES cache_entries(file_path) ON DELETE CASCADE
);`

	_, err := cm.db.Exec(schema)
	if err != nil {
		return fmt.Errorf("creating cache tables: %w", err)
	}

	return nil
}
