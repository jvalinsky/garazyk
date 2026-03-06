package runner

import (
	"fmt"
	"os"
)

// DefaultMaxFileSize is the default maximum file size (1MB).
const DefaultMaxFileSize int64 = 1024 * 1024

// DefaultFileTimeout is the default per-file timeout in seconds.
const DefaultFileTimeout = 30

// CheckFileSize returns an error if the file exceeds the size limit.
func CheckFileSize(filePath string, maxSize int64) error {
	info, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("stat %s: %w", filePath, err)
	}
	if info.Size() > maxSize {
		return fmt.Errorf("file %s exceeds size limit (%d > %d bytes)", filePath, info.Size(), maxSize)
	}
	return nil
}
