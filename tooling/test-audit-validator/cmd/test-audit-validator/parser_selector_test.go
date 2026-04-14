package main

import (
	"bytes"
	"errors"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestParserSelectorAutoUsesClangOnSuccess(t *testing.T) {
	t.Parallel()

	simpleCalls := 0
	clangCalls := 0

	s := mustSelector(t, parserModeAuto,
		func(filePath string) (*models.TestFile, error) {
			simpleCalls++
			return &models.TestFile{Path: filePath}, nil
		},
		func(filePath string) (*models.TestFile, error) {
			clangCalls++
			return &models.TestFile{Path: "clang:" + filePath}, nil
		},
		nil,
	)

	tf, err := s.analyze("a.m")
	if err != nil {
		t.Fatalf("analyze returned error: %v", err)
	}
	if tf.Path != "clang:a.m" {
		t.Fatalf("expected clang result, got %q", tf.Path)
	}
	if clangCalls != 1 {
		t.Fatalf("expected clang analyzer to be called once, got %d", clangCalls)
	}
	if simpleCalls != 0 {
		t.Fatalf("expected simple analyzer not to be called, got %d", simpleCalls)
	}
	stats := s.stats()
	if stats.ClangAttempted != 1 || stats.ClangSucceeded != 1 || stats.ClangFallbacks != 0 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
}

func TestParserSelectorAutoFallsBackOnClangError(t *testing.T) {
	t.Parallel()

	simpleCalls := 0
	clangCalls := 0
	var warn bytes.Buffer

	s := mustSelector(t, parserModeAuto,
		func(filePath string) (*models.TestFile, error) {
			simpleCalls++
			return &models.TestFile{Path: "simple:" + filePath}, nil
		},
		func(filePath string) (*models.TestFile, error) {
			clangCalls++
			return nil, errors.New("clang failed")
		},
		&warn,
	)

	tf, err := s.analyze("a.m")
	if err != nil {
		t.Fatalf("analyze returned error: %v", err)
	}
	if tf.Path != "simple:a.m" {
		t.Fatalf("expected simple fallback result, got %q", tf.Path)
	}
	if clangCalls != 1 {
		t.Fatalf("expected clang analyzer to be called once, got %d", clangCalls)
	}
	if simpleCalls != 1 {
		t.Fatalf("expected simple analyzer to be called once, got %d", simpleCalls)
	}
	if got := warn.String(); got == "" {
		t.Fatalf("expected warning output for fallback, got empty string")
	}
	stats := s.stats()
	if stats.ClangAttempted != 1 || stats.ClangSucceeded != 0 || stats.ClangFallbacks != 1 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
}

func TestParserSelectorClangModeNoFallback(t *testing.T) {
	t.Parallel()

	simpleCalls := 0
	clangCalls := 0

	s := mustSelector(t, parserModeClang,
		func(filePath string) (*models.TestFile, error) {
			simpleCalls++
			return &models.TestFile{Path: filePath}, nil
		},
		func(filePath string) (*models.TestFile, error) {
			clangCalls++
			return nil, errors.New("clang failed")
		},
		nil,
	)

	_, err := s.analyze("a.m")
	if err == nil {
		t.Fatal("expected clang mode to return error")
	}
	if clangCalls != 1 {
		t.Fatalf("expected clang analyzer to be called once, got %d", clangCalls)
	}
	if simpleCalls != 0 {
		t.Fatalf("expected no simple fallback in clang mode, got %d calls", simpleCalls)
	}
	stats := s.stats()
	if stats.ClangAttempted != 1 || stats.ClangSucceeded != 0 || stats.ClangFallbacks != 0 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
}

func TestParserSelectorSimpleModeBypassesClang(t *testing.T) {
	t.Parallel()

	simpleCalls := 0
	clangCalls := 0

	s := mustSelector(t, parserModeSimple,
		func(filePath string) (*models.TestFile, error) {
			simpleCalls++
			return &models.TestFile{Path: "simple:" + filePath}, nil
		},
		func(filePath string) (*models.TestFile, error) {
			clangCalls++
			return &models.TestFile{Path: "clang:" + filePath}, nil
		},
		nil,
	)

	tf, err := s.analyze("a.m")
	if err != nil {
		t.Fatalf("analyze returned error: %v", err)
	}
	if tf.Path != "simple:a.m" {
		t.Fatalf("expected simple parser output, got %q", tf.Path)
	}
	if simpleCalls != 1 {
		t.Fatalf("expected simple analyzer to be called once, got %d", simpleCalls)
	}
	if clangCalls != 0 {
		t.Fatalf("expected clang analyzer not to be called, got %d", clangCalls)
	}
	stats := s.stats()
	if stats.ClangAttempted != 0 || stats.ClangSucceeded != 0 || stats.ClangFallbacks != 0 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
}

func TestParserSelectorInvalidMode(t *testing.T) {
	t.Parallel()

	_, err := newParserSelector("wat", func(filePath string) (*models.TestFile, error) {
		return &models.TestFile{Path: filePath}, nil
	}, nil, nil)
	if err == nil {
		t.Fatal("expected invalid mode error")
	}
}

func mustSelector(
	t *testing.T,
	mode string,
	simpleAnalyzer fileAnalyzerFn,
	clangAnalyzer fileAnalyzerFn,
	warn *bytes.Buffer,
) *parserSelector {
	t.Helper()

	s, err := newParserSelector(mode, simpleAnalyzer, clangAnalyzer, warn)
	if err != nil {
		t.Fatalf("newParserSelector returned error: %v", err)
	}
	return s
}
