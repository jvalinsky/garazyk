package main

import (
	"fmt"
	"io"
	"strings"
	"sync/atomic"

	"github.com/september-pds/test-audit-validator/internal/models"
)

const (
	parserModeAuto   = "auto"
	parserModeClang  = "clang"
	parserModeSimple = "simple"
)

type fileAnalyzerFn func(filePath string) (*models.TestFile, error)

type parserSelector struct {
	mode   string
	simple fileAnalyzerFn
	clang  fileAnalyzerFn
	warn   io.Writer

	clangAttempted atomic.Int64
	clangSucceeded atomic.Int64
	clangFallbacks atomic.Int64
}

func newParserSelector(mode string, simpleAnalyzer, clangAnalyzer fileAnalyzerFn, warn io.Writer) (*parserSelector, error) {
	mode = strings.ToLower(strings.TrimSpace(mode))
	if mode == "" {
		mode = parserModeAuto
	}
	switch mode {
	case parserModeAuto, parserModeClang, parserModeSimple:
		// valid
	default:
		return nil, fmt.Errorf("invalid parser mode %q", mode)
	}

	if simpleAnalyzer == nil {
		return nil, fmt.Errorf("simple analyzer is required")
	}

	return &parserSelector{
		mode:   mode,
		simple: simpleAnalyzer,
		clang:  clangAnalyzer,
		warn:   warn,
	}, nil
}

type parserSelectorStats struct {
	Mode           string
	ClangAttempted int
	ClangSucceeded int
	ClangFallbacks int
}

func (s *parserSelector) stats() parserSelectorStats {
	return parserSelectorStats{
		Mode:           s.mode,
		ClangAttempted: int(s.clangAttempted.Load()),
		ClangSucceeded: int(s.clangSucceeded.Load()),
		ClangFallbacks: int(s.clangFallbacks.Load()),
	}
}

func (s *parserSelector) analyzeWithClang(filePath string) (*models.TestFile, error) {
	if s.clang == nil {
		return nil, fmt.Errorf("clang analyzer not configured")
	}

	s.clangAttempted.Add(1)
	tf, err := s.clang(filePath)
	if err == nil {
		s.clangSucceeded.Add(1)
	}
	return tf, err
}

func (s *parserSelector) analyze(filePath string) (*models.TestFile, error) {
	switch s.mode {
	case parserModeSimple:
		return s.simple(filePath)
	case parserModeClang:
		return s.analyzeWithClang(filePath)
	default: // auto
		if s.clang != nil {
			tf, err := s.analyzeWithClang(filePath)
			if err == nil {
				return tf, nil
			}
			s.clangFallbacks.Add(1)
			if s.warn != nil {
				fmt.Fprintf(s.warn, "Warning: libclang parse failed for %s, falling back to simple parser: %v\n", filePath, err)
			}
		}
		return s.simple(filePath)
	}
}
