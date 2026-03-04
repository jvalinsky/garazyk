# Makefile for test-audit-validator
# Handles CGO configuration for libclang on macOS and Linux

# Detect OS
UNAME_S := $(shell uname -s)

# Configure libclang paths based on OS
ifeq ($(UNAME_S),Darwin)
    # macOS - use Xcode's libclang
    XCODE_TOOLCHAIN := /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
    LIBCLANG_PATH := $(XCODE_TOOLCHAIN)/usr/lib
    LIBCLANG_INCLUDE := $(XCODE_TOOLCHAIN)/usr/include
    
    export CGO_CFLAGS := -I$(LIBCLANG_INCLUDE)
    export CGO_LDFLAGS := -L$(LIBCLANG_PATH) -Wl,-rpath,$(LIBCLANG_PATH)
else
    # Linux - use system libclang
    LIBCLANG_PATH := /usr/lib/llvm-14/lib
    LIBCLANG_INCLUDE := /usr/lib/llvm-14/include
    
    export CGO_CFLAGS := -I$(LIBCLANG_INCLUDE)
    export CGO_LDFLAGS := -L$(LIBCLANG_PATH) -Wl,-rpath,$(LIBCLANG_PATH)
endif

.PHONY: all build test clean install help

all: build

help:
	@echo "test-audit-validator Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  build    - Build the test-audit-validator binary"
	@echo "  test     - Run all tests"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Install binary to bin/"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Environment:"
	@echo "  OS: $(UNAME_S)"
	@echo "  CGO_CFLAGS: $(CGO_CFLAGS)"
	@echo "  CGO_LDFLAGS: $(CGO_LDFLAGS)"

build:
	@echo "Building test-audit-validator..."
	@echo "CGO_CFLAGS=$(CGO_CFLAGS)"
	@echo "CGO_LDFLAGS=$(CGO_LDFLAGS)"
	go build -o bin/test-audit-validator ./cmd/test-audit-validator

test:
	@echo "Running tests..."
	@echo "CGO_CFLAGS=$(CGO_CFLAGS)"
	@echo "CGO_LDFLAGS=$(CGO_LDFLAGS)"
	go test -v ./...

test-coverage:
	@echo "Running tests with coverage..."
	go test -cover ./...
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

clean:
	rm -rf bin/
	rm -f coverage.out coverage.html
	go clean

install: build
	@echo "Binary installed to bin/test-audit-validator"

# Quick test for just the analysis package
test-analysis:
	@echo "Testing analysis package..."
	go test -v ./internal/analysis

# Quick test for just the discovery package
test-discovery:
	@echo "Testing discovery package..."
	go test -v ./internal/discovery

# Quick test for just the models package
test-models:
	@echo "Testing models package..."
	go test -v ./internal/models
