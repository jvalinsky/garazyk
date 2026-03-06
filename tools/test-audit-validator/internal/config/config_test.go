package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.RootDirectory != "." {
		t.Errorf("expected RootDirectory '.', got %q", cfg.RootDirectory)
	}
	if cfg.CachePath != ".test_audit_cache.db" {
		t.Errorf("expected CachePath '.test_audit_cache.db', got %q", cfg.CachePath)
	}
	if cfg.OutputFormat != "markdown" {
		t.Errorf("expected OutputFormat 'markdown', got %q", cfg.OutputFormat)
	}
	if cfg.MaxFileSize != 1024*1024 {
		t.Errorf("expected MaxFileSize 1048576, got %d", cfg.MaxFileSize)
	}
	if cfg.FileTimeout != 30 {
		t.Errorf("expected FileTimeout 30, got %d", cfg.FileTimeout)
	}
	if cfg.Workers != runtime.NumCPU() {
		t.Errorf("expected Workers %d, got %d", runtime.NumCPU(), cfg.Workers)
	}
	if cfg.Incremental {
		t.Error("expected Incremental false")
	}
	if cfg.Quiet {
		t.Error("expected Quiet false")
	}
}

func TestConfig_Validate(t *testing.T) {
	t.Run("valid config", func(t *testing.T) {
		cfg := DefaultConfig()
		if err := cfg.Validate(); err != nil {
			t.Errorf("expected valid config, got error: %v", err)
		}
	})

	t.Run("invalid output format", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.OutputFormat = "xml"
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for invalid output format")
		}
	})

	t.Run("invalid fail-on severity", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.FailOn = "extreme"
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for invalid fail-on severity")
		}
	})

	t.Run("valid fail-on severities", func(t *testing.T) {
		for _, sev := range []string{"critical", "high", "medium", "low", ""} {
			cfg := DefaultConfig()
			cfg.FailOn = sev
			if err := cfg.Validate(); err != nil {
				t.Errorf("expected no error for fail-on %q, got: %v", sev, err)
			}
		}
	})

	t.Run("nonexistent root directory", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.RootDirectory = "/nonexistent/path/that/does/not/exist"
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for nonexistent root directory")
		}
	})

	t.Run("invalid workers", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.Workers = 0
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for zero workers")
		}
	})

	t.Run("invalid max file size", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.MaxFileSize = -1
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for negative max file size")
		}
	})

	t.Run("invalid file timeout", func(t *testing.T) {
		cfg := DefaultConfig()
		cfg.FileTimeout = 0
		if err := cfg.Validate(); err == nil {
			t.Error("expected error for zero file timeout")
		}
	})
}

func TestLoadConfig_FromFile(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.json")

	cfgData := map[string]interface{}{
		"root_directory": tmpDir,
		"cache_path":     "custom_cache.db",
		"output_format":  "json",
		"quiet":          true,
		"max_file_size":  2097152,
		"workers":        4,
		"domains":        []string{"Auth", "Core"},
		"severities":     []string{"critical", "high"},
		"fail_on":        "high",
	}

	data, err := json.Marshal(cfgData)
	if err != nil {
		t.Fatalf("marshaling config: %v", err)
	}
	if err := os.WriteFile(configPath, data, 0o644); err != nil {
		t.Fatalf("writing config file: %v", err)
	}

	cfg, err := LoadConfig(configPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	if cfg.RootDirectory != tmpDir {
		t.Errorf("expected RootDirectory %q, got %q", tmpDir, cfg.RootDirectory)
	}
	if cfg.CachePath != "custom_cache.db" {
		t.Errorf("expected CachePath 'custom_cache.db', got %q", cfg.CachePath)
	}
	if cfg.OutputFormat != "json" {
		t.Errorf("expected OutputFormat 'json', got %q", cfg.OutputFormat)
	}
	if !cfg.Quiet {
		t.Error("expected Quiet true")
	}
	if cfg.MaxFileSize != 2097152 {
		t.Errorf("expected MaxFileSize 2097152, got %d", cfg.MaxFileSize)
	}
	if cfg.Workers != 4 {
		t.Errorf("expected Workers 4, got %d", cfg.Workers)
	}
	if len(cfg.Domains) != 2 || cfg.Domains[0] != "Auth" || cfg.Domains[1] != "Core" {
		t.Errorf("expected Domains [Auth Core], got %v", cfg.Domains)
	}
	if len(cfg.Severities) != 2 || cfg.Severities[0] != "critical" || cfg.Severities[1] != "high" {
		t.Errorf("expected Severities [critical high], got %v", cfg.Severities)
	}
	if cfg.FailOn != "high" {
		t.Errorf("expected FailOn 'high', got %q", cfg.FailOn)
	}
}

func TestLoadConfig_MissingFileError(t *testing.T) {
	_, err := LoadConfig("/nonexistent/config.json")
	if err == nil {
		t.Error("expected error for nonexistent config file")
	}
}

func TestLoadConfig_NoFileUsesDefaults(t *testing.T) {
	cfg, err := LoadConfig("")
	if err != nil {
		t.Fatalf("LoadConfig with empty path: %v", err)
	}
	if cfg.OutputFormat != "markdown" {
		t.Errorf("expected default OutputFormat 'markdown', got %q", cfg.OutputFormat)
	}
}

// Test finding helpers

func sampleFindings() []validation.Finding {
	return []validation.Finding{
		{
			RuleName:   "empty-test",
			Severity:   validation.CRITICAL,
			TestMethod: "testAuth",
			TestClass:  "AuthTests",
			FilePath:   "ATProtoPDS/Tests/Auth/AuthTests.m",
		},
		{
			RuleName:   "no-assert",
			Severity:   validation.HIGH,
			TestMethod: "testNetwork",
			TestClass:  "NetworkTests",
			FilePath:   "ATProtoPDS/Tests/Network/NetworkTests.m",
		},
		{
			RuleName:   "name-mismatch",
			Severity:   validation.MEDIUM,
			TestMethod: "testCore",
			TestClass:  "CoreTests",
			FilePath:   "ATProtoPDS/Tests/Core/CoreTests.m",
		},
		{
			RuleName:   "weak-assert",
			Severity:   validation.LOW,
			TestMethod: "testHelper",
			TestClass:  "AuthTests",
			FilePath:   "ATProtoPDS/Tests/Auth/AuthHelperTests.m",
		},
	}
}

func TestFilterFindings_BySeverity(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Severities = []string{"critical"}

	result := FilterFindings(sampleFindings(), cfg)
	if len(result) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(result))
	}
	if result[0].Severity != validation.CRITICAL {
		t.Errorf("expected critical finding, got %s", result[0].Severity)
	}
}

func TestFilterFindings_ByDomain(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Domains = []string{"Auth"}

	result := FilterFindings(sampleFindings(), cfg)
	if len(result) != 2 {
		t.Fatalf("expected 2 findings, got %d", len(result))
	}
	for _, f := range result {
		if f.TestClass != "AuthTests" {
			t.Errorf("expected AuthTests class, got %s", f.TestClass)
		}
	}
}

func TestFilterFindings_ByClass(t *testing.T) {
	cfg := DefaultConfig()
	cfg.TestClasses = []string{"NetworkTests"}

	result := FilterFindings(sampleFindings(), cfg)
	if len(result) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(result))
	}
	if result[0].TestClass != "NetworkTests" {
		t.Errorf("expected NetworkTests, got %s", result[0].TestClass)
	}
}

func TestFilterFindings_Combined(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Domains = []string{"Auth"}
	cfg.Severities = []string{"critical"}

	result := FilterFindings(sampleFindings(), cfg)
	if len(result) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(result))
	}
	if result[0].TestClass != "AuthTests" || result[0].Severity != validation.CRITICAL {
		t.Errorf("expected critical AuthTests finding, got %s %s", result[0].Severity, result[0].TestClass)
	}
}

func TestFilterFindings_NoFilters(t *testing.T) {
	cfg := DefaultConfig()
	findings := sampleFindings()

	result := FilterFindings(findings, cfg)
	if len(result) != len(findings) {
		t.Errorf("expected %d findings, got %d", len(findings), len(result))
	}
}
