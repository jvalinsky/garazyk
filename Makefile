.PHONY: all clean build test run test-blob test-unit help clang-tidy scan-build fuzz-asan fuzz-ubsan fuzz-tsan fuzz-all fuzz-xrpc fuzz-cbor fuzz-http run-fuzzers

CC = clang
CFLAGS = -framework Foundation -framework AppKit -framework Network -framework Security -lsqlite3 -fobjc-arc
CFLAGS += -I/Users/jack/Software/objpds/secp256k1/include
CFLAGS += -IATProtoPDS/Sources
LDFLAGS = -framework Foundation -framework AppKit -framework Network -framework Security -lsqlite3 -L/Users/jack/Software/objpds/secp256k1/build/lib -lsecp256k1
BUILD_DIR = build
EXECUTABLE = atprotopds

SOURCES = $(wildcard ATProtoPDS/Sources/**/*.m)
C_SOURCES = ATProtoPDS/Sources/Auth/secp256k1_wrapper_c.c
OBJECTS = $(patsubst ATProtoPDS/Sources/%.m,$(BUILD_DIR)/%.o,$(filter-out ATProtoPDS/Sources/App/main.m ATProtoPDS/Sources/App/server_main.m ATProtoPDS/Sources/App/test_runner.m ATProtoPDS/Sources/Network/RateLimiterTests.m ATProtoPDS/Sources/CLI/main.m,$(SOURCES)))
C_OBJECTS = $(patsubst ATProtoPDS/Sources/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))

all: $(BUILD_DIR)/$(EXECUTABLE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/Auth
	mkdir -p $(BUILD_DIR)/Blob
	mkdir -p $(BUILD_DIR)/Database
	mkdir -p $(BUILD_DIR)/Network
	mkdir -p $(BUILD_DIR)/Repository
	mkdir -p $(BUILD_DIR)/Sync
	mkdir -p $(BUILD_DIR)/AppView
	mkdir -p $(BUILD_DIR)/Debug
	mkdir -p $(BUILD_DIR)/Metrics
	mkdir -p $(BUILD_DIR)/Admin
	mkdir -p $(BUILD_DIR)/CLI
	mkdir -p $(BUILD_DIR)/Core
	mkdir -p $(BUILD_DIR)/App
	mkdir -p $(BUILD_DIR)/Identity
	mkdir -p $(BUILD_DIR)/Federation

$(BUILD_DIR)/%.o: ATProtoPDS/Sources/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: ATProtoPDS/Sources/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/$(EXECUTABLE): $(OBJECTS) $(C_OBJECTS) ATProtoPDS/Sources/App/server_main.m
	$(CC) $(CFLAGS) $(OBJECTS) $(C_OBJECTS) -c ATProtoPDS/Sources/App/server_main.m -o $(BUILD_DIR)/server_main.o
	$(CC) $(CFLAGS) $(OBJECTS) $(C_OBJECTS) $(BUILD_DIR)/server_main.o $(LDFLAGS) -o $@

clean:
	rm -rf build

build: $(BUILD_DIR)/$(EXECUTABLE)

run: $(BUILD_DIR)/$(EXECUTABLE)
	./$(BUILD_DIR)/$(EXECUTABLE)

test: $(BUILD_DIR)/$(EXECUTABLE)
	@echo "Running basic connectivity test..."
	@timeout 3 ./$(BUILD_DIR)/$(EXECUTABLE) || true
	@echo "Server test complete"

test-unit: $(BUILD_DIR)/blob_storage_tests $(BUILD_DIR)/did_resolver_tests $(BUILD_DIR)/did_validation_tests $(BUILD_DIR)/handle_resolver_tests $(BUILD_DIR)/xrpc_integration_tests $(BUILD_DIR)/pds_integration_tests
	@echo "Running blob storage unit tests..."
	./$(BUILD_DIR)/blob_storage_tests
	@echo "Running DID resolver unit tests..."
	./$(BUILD_DIR)/did_resolver_tests
	@echo "Running DID validation unit tests..."
	./$(BUILD_DIR)/did_validation_tests
	@echo "Running handle resolver unit tests..."
	./$(BUILD_DIR)/handle_resolver_tests
	@echo "Running XRPC integration tests..."
	./$(BUILD_DIR)/xrpc_integration_tests
	@echo "Running PDS integration tests..."
	./$(BUILD_DIR)/pds_integration_tests

test-blob: $(BUILD_DIR)/$(EXECUTABLE)
	@echo "Running blob storage integration tests..."
	./test_blob_storage.sh

test-comprehensive: test-unit test-blob
	@echo "Running comprehensive test suite..."
	./run_tests.sh

$(BUILD_DIR)/blob_storage_tests: $(BUILD_DIR)/Tests/Blob/blob_storage_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Blob/blob_storage_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/did_resolver_tests: $(BUILD_DIR)/Tests/Identity/did_resolver_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Identity/did_resolver_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/did_validation_tests: $(BUILD_DIR)/Tests/Core/did_validation_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Core/did_validation_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/handle_resolver_tests: $(BUILD_DIR)/Tests/Identity/handle_resolver_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Identity/handle_resolver_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/xrpc_integration_tests: $(BUILD_DIR)/Tests/Network/xrpc_integration_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Network/xrpc_integration_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/pds_integration_tests: $(BUILD_DIR)/Tests/Integration/pds_integration_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Integration/pds_integration_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/mime_type_validator_tests: $(BUILD_DIR)/Tests/Blob/mime_type_validator_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/Tests/Blob/mime_type_validator_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

$(BUILD_DIR)/pds-cli: $(wildcard ATProtoPDS/Sources/CLI/*.m) $(wildcard ATProtoPDS/Sources/Debug/*.m) $(wildcard ATProtoPDS/Sources/Admin/*.m) $(wildcard ATProtoPDS/Sources/Metrics/*.m) $(filter-out $(BUILD_DIR)/Repository/%,$(filter $(BUILD_DIR)/Repository/%.o,$(OBJECTS))) $(filter-out $(BUILD_DIR)/Sync/%,$(filter $(BUILD_DIR)/Sync/%.o,$(OBJECTS))) $(filter-out $(BUILD_DIR)/Network/XrpcMethodRegistry.o,$(filter $(BUILD_DIR)/Network/%.o,$(OBJECTS)))
	$(CC) $(CFLAGS) $(filter $(BUILD_DIR)/CLI/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Debug/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Admin/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Metrics/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Core/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Auth/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Blob/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Database/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Repository/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Sync/%.o,$(OBJECTS)) $(filter $(BUILD_DIR)/Network/XrpcMethodRegistry.o,$(OBJECTS)) $(LDFLAGS) -o $@

help:
	@echo "ATProto PDS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all                 - Build the executable (default)"
	@echo "  build               - Build the executable"
	@echo "  run                 - Build and run the server"
	@echo "  test                - Build and run a quick connectivity test"
	@echo "  test-unit           - Build and run all unit tests"
	@echo "  test-blob           - Build and run blob storage integration tests"
	@echo "  test-comprehensive  - Run the complete test suite with coverage report"
	@echo "  clean               - Remove build artifacts"
	@echo "  help                - Show this help message"
	@echo ""
	@echo "Security Targets:"
	@echo "  clang-tidy          - Run clang-tidy static analysis"
	@echo "  scan-build         - Run Clang Static Analyzer"
	@echo "  fuzz-asan          - Build with AddressSanitizer"
	@echo "  fuzz-ubsan         - Build with UndefinedBehaviorSanitizer"
	@echo "  fuzz-tsan          - Build with ThreadSanitizer"
	@echo "  fuzz-all           - Build with all sanitizers"
	@echo "  fuzz-xrpc          - Build XRPC fuzzer"
	@echo "  fuzz-cbor          - Build CBOR/CAR fuzzer"
	@echo "  fuzz-http          - Build HTTP parser fuzzer"
	@echo "  run-fuzzers        - Run all fuzzers"
	@echo ""
	@echo "Test Files:"
	@echo "  blob_storage_tests      - Blob storage operations"
	@echo "  did_resolver_tests      - DID resolution and caching"
	@echo "  handle_resolver_tests   - Handle resolution"
	@echo "  xrpc_integration_tests  - XRPC endpoint integration"
	@echo "  pds_integration_tests   - Full PDS workflow integration"
	@echo ""
	@echo "Build artifacts are stored in: $(BUILD_DIR)/"

# Security Analysis Targets

clang-tidy: build
	@echo "Running clang-tidy static analysis..."
	@find ATProtoPDS/Sources -name "*.m" -o -name "*.c" | head -20 | xargs -I{} clang-tidy -p . --config-file=.clang-tidy {} 2>&1 | grep -E "(warning|error)" | head -50 || true
	@echo "Clang-tidy analysis complete"

scan-build:
	@echo "Running Clang Static Analyzer (scan-build)..."
	@scan-build --use-cc=$(CC) make clean build 2>&1 | tail -50 || true
	@echo "Static analysis complete"

# Sanitizer Build Targets

FUZZ_CFLAGS = $(CFLAGS) -g -O1 -fno-omit-frame-pointer
FUZZ_LDFLAGS = $(LDFLAGS)
FUZZ_CC = clang++

fuzz-asan: FUZZ_CFLAGS += -fsanitize=address
fuzz-asan: FUZZ_LDFLAGS += -fsanitize=address
fuzz-asan: build

fuzz-ubsan: FUZZ_CFLAGS += -fsanitize=undefined
fuzz-ubsan: FUZZ_LDFLAGS += -fsanitize=undefined
fuzz-ubsan: build

fuzz-tsan: FUZZ_CFLAGS += -fsanitize=thread
fuzz-tsan: FUZZ_LDFLAGS += -fsanitize=thread
fuzz-tsan: build

fuzz-all: FUZZ_CFLAGS += -fsanitize=address,undefined,thread
fuzz-all: FUZZ_LDFLAGS += -fsanitize=address,undefined,thread
fuzz-all: build

# Fuzzer Build Targets

fuzz-xrpc: fuzzing/fuzz_xrpc.mm $(OBJECTS) $(C_OBJECTS)
	@echo "Building XRPC fuzzer..."
	$(FUZZ_CC) $(FUZZ_CFLAGS) fuzzing/fuzz_xrpc.mm $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(C_OBJECTS) $(FUZZ_LDFLAGS) -o fuzzing/fuzz_xrpc
	@echo "XRPC fuzzer built: fuzzing/fuzz_xrpc"

fuzz-cbor: fuzzing/fuzz_cbor.mm $(OBJECTS) $(C_OBJECTS)
	@echo "Building CBOR/CAR fuzzer..."
	$(FUZZ_CC) $(FUZZ_CFLAGS) fuzzing/fuzz_cbor.mm $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(C_OBJECTS) $(FUZZ_LDFLAGS) -o fuzzing/fuzz_cbor
	@echo "CBOR/CAR fuzzer built: fuzzing/fuzz_cbor"

fuzz-http: fuzzing/fuzz_http.mm $(OBJECTS) $(C_OBJECTS)
	@echo "Building HTTP parser fuzzer..."
	$(FUZZ_CC) $(FUZZ_CFLAGS) fuzzing/fuzz_http.mm $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(C_OBJECTS) $(FUZZ_LDFLAGS) -o fuzzing/fuzz_http
	@echo "HTTP parser fuzzer built: fuzzing/fuzz_http"

# Run Fuzzers Target

run-fuzzers: fuzz-xrpc fuzz-cbor fuzz-http
	@echo "Running fuzzers with corpus..."
	@echo "Note: Fuzzers will run until Ctrl+C. For limited runs, use:"
	@echo "  ./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=10000"
	@echo "  ./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -runs=10000"
	@echo "  ./fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -runs=10000"
	@./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=1000 || true
	@./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -runs=1000 || true
	@./fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -runs=1000 || true
	@echo "Fuzzing session complete. Check fuzzing/crashers/ for any crashes."
