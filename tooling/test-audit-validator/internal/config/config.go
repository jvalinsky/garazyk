package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/spf13/viper"
)

// Config holds all configuration settings for the analyzer
type Config struct {
	// Analysis settings
	RootDirectory string   `json:"root_directory" mapstructure:"root_directory"`
	CachePath     string   `json:"cache_path" mapstructure:"cache_path"`
	Incremental   bool     `json:"incremental" mapstructure:"incremental"`
	Parser        string   `json:"parser" mapstructure:"parser"`                             // "auto", "clang", "simple"
	CompileCommandsDir string `json:"compile_commands_dir" mapstructure:"compile_commands_dir"` // Directory containing compile_commands.json
	ClangArgs     []string `json:"clang_args" mapstructure:"clang_args"`                     // Extra clang args appended after resolved args

	// Output settings
	OutputFormat string `json:"output_format" mapstructure:"output_format"` // "markdown", "json", "html"
	OutputFile   string `json:"output_file" mapstructure:"output_file"`
	Quiet        bool   `json:"quiet" mapstructure:"quiet"`

	// Filtering
	Domains     []string `json:"domains" mapstructure:"domains"`         // ["Auth", "Core", "Network"]
	Severities  []string `json:"severities" mapstructure:"severities"`   // ["critical", "high"]
	TestTypes   []string `json:"test_types" mapstructure:"test_types"`   // ["unit", "integration"]
	TestClasses []string `json:"test_classes" mapstructure:"test_classes"` // specific class names

	// CI settings
	FailOn string `json:"fail_on" mapstructure:"fail_on"` // "critical", "high", "medium", "low"

	// Analysis limits
	MaxFileSize int64 `json:"max_file_size" mapstructure:"max_file_size"` // bytes, default 1MB
	FileTimeout int   `json:"file_timeout" mapstructure:"file_timeout"`   // seconds, default 30
	Workers     int   `json:"workers" mapstructure:"workers"`             // parallel workers, default runtime.NumCPU()
}

// DefaultConfig returns a Config with sensible defaults
func DefaultConfig() *Config {
	return &Config{
		RootDirectory: ".",
		CachePath:     ".test_audit_cache.db",
		Incremental:   false,
		Parser:        "auto",
		CompileCommandsDir: "",
		ClangArgs:     nil,
		OutputFormat:  "markdown",
		OutputFile:    "",
		Quiet:         false,
		Domains:       nil,
		Severities:    nil,
		TestTypes:     nil,
		TestClasses:   nil,
		FailOn:        "",
		MaxFileSize:   1024 * 1024, // 1MB
		FileTimeout:   30,
		Workers:       runtime.NumCPU(),
	}
}

// LoadConfig loads configuration from file, environment, and returns merged config
func LoadConfig(configPath string) (*Config, error) {
	v := viper.New()

	// Set defaults from DefaultConfig
	defaults := DefaultConfig()
	v.SetDefault("root_directory", defaults.RootDirectory)
	v.SetDefault("cache_path", defaults.CachePath)
	v.SetDefault("incremental", defaults.Incremental)
	v.SetDefault("parser", defaults.Parser)
	v.SetDefault("compile_commands_dir", defaults.CompileCommandsDir)
	v.SetDefault("clang_args", defaults.ClangArgs)
	v.SetDefault("output_format", defaults.OutputFormat)
	v.SetDefault("output_file", defaults.OutputFile)
	v.SetDefault("quiet", defaults.Quiet)
	v.SetDefault("fail_on", defaults.FailOn)
	v.SetDefault("max_file_size", defaults.MaxFileSize)
	v.SetDefault("file_timeout", defaults.FileTimeout)
	v.SetDefault("workers", defaults.Workers)

	// Read config file
	if configPath != "" {
		v.SetConfigFile(configPath)
		if err := v.ReadInConfig(); err != nil {
			return nil, fmt.Errorf("reading config file %s: %w", configPath, err)
		}
	} else {
		// Look for .test_audit_config.json in the root directory
		v.SetConfigName(".test_audit_config")
		v.SetConfigType("json")
		v.AddConfigPath(".")
		// Ignore error — config file is optional when not explicitly specified
		_ = v.ReadInConfig()
	}

	// Read environment variables with TAV_ prefix
	v.SetEnvPrefix("TAV")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("unmarshaling config: %w", err)
	}

	return &cfg, nil
}

// Validate checks the configuration for errors
func (c *Config) Validate() error {
	// Check root directory exists
	info, err := os.Stat(c.RootDirectory)
	if err != nil {
		return fmt.Errorf("root directory %q: %w", c.RootDirectory, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("root directory %q is not a directory", c.RootDirectory)
	}

	// Check output format
	switch c.OutputFormat {
	case "markdown", "json", "html":
		// valid
	default:
		return fmt.Errorf("invalid output format %q: must be markdown, json, or html", c.OutputFormat)
	}

	// Check parser mode
	c.Parser = strings.ToLower(strings.TrimSpace(c.Parser))
	if c.Parser == "" {
		c.Parser = "auto"
	}
	switch c.Parser {
	case "auto", "clang", "simple":
		// valid
	default:
		return fmt.Errorf("invalid parser %q: must be auto, clang, or simple", c.Parser)
	}

	// Check compile_commands dir if specified
	if c.CompileCommandsDir != "" {
		info, err := os.Stat(c.CompileCommandsDir)
		if err != nil {
			return fmt.Errorf("compile_commands_dir %q: %w", c.CompileCommandsDir, err)
		}
		if !info.IsDir() {
			return fmt.Errorf("compile_commands_dir %q is not a directory", c.CompileCommandsDir)
		}
	}

	// Check output file directory exists if specified
	if c.OutputFile != "" {
		dir := filepath.Dir(c.OutputFile)
		if _, err := os.Stat(dir); err != nil {
			return fmt.Errorf("output file directory %q: %w", dir, err)
		}
	}

	// Check fail-on severity
	if c.FailOn != "" {
		switch c.FailOn {
		case "critical", "high", "medium", "low":
			// valid
		default:
			return fmt.Errorf("invalid fail-on severity %q: must be critical, high, medium, or low", c.FailOn)
		}
	}

	// Check numeric limits
	if c.MaxFileSize <= 0 {
		return fmt.Errorf("max_file_size must be positive, got %d", c.MaxFileSize)
	}
	if c.FileTimeout <= 0 {
		return fmt.Errorf("file_timeout must be positive, got %d", c.FileTimeout)
	}
	if c.Workers <= 0 {
		return fmt.Errorf("workers must be positive, got %d", c.Workers)
	}

	return nil
}
