package cache

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"sort"
)

// CalculateFileHash computes SHA-256 hash of file contents
func CalculateFileHash(filePath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("opening file for hashing: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("reading file for hashing: %w", err)
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}

// CalculateCacheKey computes combined cache key from file hash and dependency hashes
func CalculateCacheKey(fileHash string, depHashes map[string]string) string {
	paths := make([]string, 0, len(depHashes))
	for p := range depHashes {
		paths = append(paths, p)
	}
	sort.Strings(paths)

	h := sha256.New()
	h.Write([]byte(fileHash))
	for _, p := range paths {
		h.Write([]byte(depHashes[p]))
	}

	return hex.EncodeToString(h.Sum(nil))
}
