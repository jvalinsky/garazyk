# Makefile for test-audit-validator
# Handles CGO configuration for libclang and provides repeatable audit workflows.

SHELL := /bin/bash

# Detect OS
UNAME_S := $(shell uname -s)

# Configure libclang paths based on OS
ifeq ($(UNAME_S),Darwin)
	XCODE_TOOLCHAIN := /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
	LIBCLANG_PATH := $(XCODE_TOOLCHAIN)/usr/lib
	LIBCLANG_INCLUDE := $(XCODE_TOOLCHAIN)/usr/include
	export CGO_CFLAGS := -I$(LIBCLANG_INCLUDE)
	export CGO_LDFLAGS := -L$(LIBCLANG_PATH) -Wl,-rpath,$(LIBCLANG_PATH)
else
	LIBCLANG_PATH := /usr/lib/llvm-14/lib
	LIBCLANG_INCLUDE := /usr/lib/llvm-14/include
	export CGO_CFLAGS := -I$(LIBCLANG_INCLUDE)
	export CGO_LDFLAGS := -L$(LIBCLANG_PATH) -Wl,-rpath,$(LIBCLANG_PATH)
endif

BIN := bin/test-audit-validator
TEST_ROOT ?= ../../Garazyk/Tests
COMPILE_COMMANDS_DIR ?= ../../build
ARTIFACTS_DIR ?= .artifacts/test-audit
AUDIT_CACHE ?= .test_audit_cache.db

COMMON_AUDIT_FLAGS := --format json --quiet --cache $(AUDIT_CACHE)

.PHONY: \
	all help build test test-coverage clean install \
	test-analysis test-discovery test-models \
	artifacts audit audit-report audit-simple-json audit-auto-json \
	audit-clang-json audit-clang-json-soft audit-matrix-json audit-summary \
	audit-gate audit-clang-gate \
	build-all

all: build

help:
	@echo "test-audit-validator Makefile"
	@echo ""
	@echo "Build/Test:"
	@echo "  build               Build $(BIN)"
	@echo "  test                Run full test suite"
	@echo "  test-coverage       Generate coverage.out and coverage.html"
	@echo "  clean               Remove build and coverage artifacts"
	@echo ""
	@echo "Audit workflows (JSON):"
	@echo "  audit-simple-json   Run parser=simple -> $(ARTIFACTS_DIR)/audit-simple.json"
	@echo "  audit-auto-json     Run parser=auto   -> $(ARTIFACTS_DIR)/audit-auto.json"
	@echo "  audit-clang-json    Run parser=clang  -> $(ARTIFACTS_DIR)/audit-clang.json (strict)"
	@echo "  audit-clang-json-soft  Same as clang strict, but does not fail make"
	@echo "  audit-matrix-json   Run simple + auto + clang-soft"
	@echo "  audit-summary       Print compact summary from JSON artifacts"
	@echo "  audit-gate          Enforce auto-mode parser gate (no parser errors/fallbacks)"
	@echo "  audit-clang-gate    Enforce strict clang gate (no parser errors, no fallbacks)"
	@echo ""
	@echo "Variables:"
	@echo "  TEST_ROOT=$(TEST_ROOT)"
	@echo "  COMPILE_COMMANDS_DIR=$(COMPILE_COMMANDS_DIR)"
	@echo "  ARTIFACTS_DIR=$(ARTIFACTS_DIR)"
	@echo "  AUDIT_CACHE=$(AUDIT_CACHE)"
	@echo ""
	@echo "Environment:"
	@echo "  OS: $(UNAME_S)"
	@echo "  CGO_CFLAGS: $(CGO_CFLAGS)"
	@echo "  CGO_LDFLAGS: $(CGO_LDFLAGS)"

build:
	@echo "Building $(BIN)..."
	go build -o $(BIN) ./cmd/test-audit-validator

test:
	@echo "Running tests..."
	go test -v ./...

test-coverage:
	@echo "Running tests with coverage..."
	go test -cover ./...
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

clean:
	rm -rf bin/
	rm -rf $(ARTIFACTS_DIR)
	rm -f coverage.out coverage.html
	go clean

install: build
	@echo "Binary installed to $(BIN)"

test-analysis:
	@echo "Testing analysis package..."
	go test -v ./internal/analysis

test-discovery:
	@echo "Testing discovery package..."
	go test -v ./internal/discovery

test-models:
	@echo "Testing models package..."
	go test -v ./internal/models

artifacts:
	@mkdir -p $(ARTIFACTS_DIR)

audit: build
	@echo "Running fail-on-critical audit against $(TEST_ROOT)..."
	./$(BIN) analyze --fail-on critical $(TEST_ROOT)

audit-report: build
	@echo "Generating Markdown report..."
	./$(BIN) analyze --format markdown --output audit-report.md $(TEST_ROOT)
	@echo "Report saved to audit-report.md"

audit-simple-json: build artifacts
	@echo "Running parser=simple audit..."
	./$(BIN) analyze \
		$(COMMON_AUDIT_FLAGS) \
		--parser simple \
		--output $(ARTIFACTS_DIR)/audit-simple.json \
		$(TEST_ROOT)

audit-auto-json: build artifacts
	@echo "Running parser=auto audit..."
	@set -euo pipefail; \
	args=( $(COMMON_AUDIT_FLAGS) --parser auto --output $(ARTIFACTS_DIR)/audit-auto.json "$(TEST_ROOT)" ); \
	if [[ -f "$(COMPILE_COMMANDS_DIR)/compile_commands.json" ]]; then \
		echo "Using compile_commands.json from $(COMPILE_COMMANDS_DIR)"; \
		args=( --compile-commands-dir "$(COMPILE_COMMANDS_DIR)" "$${args[@]}" ); \
	else \
		echo "No compile_commands.json at $(COMPILE_COMMANDS_DIR); relying on auto fallback args"; \
	fi; \
	./$(BIN) analyze "$${args[@]}"

audit-clang-json: build artifacts
	@echo "Running parser=clang strict audit..."
	@set -euo pipefail; \
	args=( $(COMMON_AUDIT_FLAGS) --parser clang --output $(ARTIFACTS_DIR)/audit-clang.json "$(TEST_ROOT)" ); \
	if [[ -f "$(COMPILE_COMMANDS_DIR)/compile_commands.json" ]]; then \
		echo "Using compile_commands.json from $(COMPILE_COMMANDS_DIR)"; \
		args=( --compile-commands-dir "$(COMPILE_COMMANDS_DIR)" "$${args[@]}" ); \
	else \
		echo "No compile_commands.json at $(COMPILE_COMMANDS_DIR); clang strict may fail"; \
	fi; \
	./$(BIN) analyze "$${args[@]}"

audit-clang-json-soft: build artifacts
	@echo "Running parser=clang strict audit (soft-fail)..."
	@set -euo pipefail; \
	if $(MAKE) audit-clang-json; then \
		echo "clang strict audit succeeded"; \
	else \
		echo "clang strict audit failed (expected in some environments); JSON output preserved at $(ARTIFACTS_DIR)/audit-clang.json"; \
	fi

audit-matrix-json: audit-simple-json audit-auto-json audit-clang-json-soft
	@echo "Completed matrix audits in $(ARTIFACTS_DIR)"

audit-summary:
	@python3 scripts/audit_summary.py "$(ARTIFACTS_DIR)"

audit-gate: audit-auto-json
	@echo "Validating auto-mode gate checks..."
	@python3 scripts/audit_gate.py \
		--path "$(ARTIFACTS_DIR)/audit-auto.json" \
		--parser-mode auto

audit-clang-gate: audit-clang-json
	@echo "Validating strict clang gate checks..."
	@python3 scripts/audit_gate.py \
		--path "$(ARTIFACTS_DIR)/audit-clang.json" \
		--parser-mode clang

# Cross-compile for multiple platforms (no CGO path)
build-all:
	@echo "Building cross-platform binaries..."
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o bin/test-audit-validator-darwin-arm64 ./cmd/test-audit-validator
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -o bin/test-audit-validator-darwin-amd64 ./cmd/test-audit-validator
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/test-audit-validator-linux-amd64 ./cmd/test-audit-validator
	@echo "Built binaries:"
	@ls -la bin/test-audit-validator-*
