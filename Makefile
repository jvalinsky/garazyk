.PHONY: all clean build test run test-blob test-unit

CC = clang
CFLAGS = -framework Foundation -framework Network -framework Security -lsqlite3 -fobjc-arc
CFLAGS += -I/Users/jack/Software/objpds/secp256k1/include
CFLAGS += -I/Users/jack/Software/objpds/ATProtoPDS/ATProtoPDS/Auth
LDFLAGS = -L/Users/jack/Software/objpds/secp256k1/build/lib -lsecp256k1
SRC_DIR = ATProtoPDS/ATProtoPDS
BUILD_DIR = build
EXECUTABLE = atprotopds

CORE_SRC = CID.m DID.m PDSController.m TID.m HandleResolver.m
AUTH_SRC = DPoPUtil.m JWT.m KeyManager.m OAuth2.m OAuthServerMetadata.m OAuthSession.m PKCEUtil.m Secp256k1.m Session.m
AUTH_SRC += secp256k1_wrapper_c.c
BLOB_SRC = BlobStorage.m
DB_SRC = PDSDatabase.m Schema.m
NET_SRC = HttpRequest.m HttpResponse.m HttpServer.m XrpcHandler.m XrpcMethodRegistry.m
REPO_SRC = CAR.m CBOR.m MST.m MSTPersistence.m RepoCommit.m
SYNC_SRC = EventFormatter.m Firehose.m WebSocketConnection.m WebSocketServer.m SubscribeReposHandler.m

OBJECTS = $(patsubst %.m,$(BUILD_DIR)/%.o,$(CORE_SRC))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Auth/%.o,$(filter-out secp256k1_wrapper_c.c,$(AUTH_SRC)))
OBJECTS += $(patsubst secp256k1_wrapper_c.c,$(BUILD_DIR)/Auth/secp256k1_wrapper_c.o,$(filter secp256k1_wrapper_c.c,$(AUTH_SRC)))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Blob/%.o,$(BLOB_SRC))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Database/%.o,$(DB_SRC))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Network/%.o,$(NET_SRC))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Repository/%.o,$(REPO_SRC))
OBJECTS += $(patsubst %.m,$(BUILD_DIR)/Sync/%.o,$(SYNC_SRC))

all: $(BUILD_DIR)/$(EXECUTABLE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/Auth
	mkdir -p $(BUILD_DIR)/Blob
	mkdir -p $(BUILD_DIR)/Database
	mkdir -p $(BUILD_DIR)/Network
	mkdir -p $(BUILD_DIR)/Repository
	mkdir -p $(BUILD_DIR)/Sync

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/blob_storage_tests.o: $(SRC_DIR)/blob_storage_tests.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Auth/%.o: $(SRC_DIR)/Auth/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Auth/secp256k1_wrapper_c.o: $(SRC_DIR)/Auth/secp256k1_wrapper_c.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Blob/%.o: $(SRC_DIR)/Blob/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Database/%.o: $(SRC_DIR)/Database/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Network/%.o: $(SRC_DIR)/Network/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Repository/%.o: $(SRC_DIR)/Repository/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/Sync/%.o: $(SRC_DIR)/Sync/%.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(BUILD_DIR)/$(EXECUTABLE): $(OBJECTS) $(SRC_DIR)/streaming_main.m
	$(CC) $(CFLAGS) $(OBJECTS) -c $(SRC_DIR)/streaming_main.m -o $(BUILD_DIR)/streaming_main.o
	$(CC) $(CFLAGS) $(OBJECTS) $(BUILD_DIR)/streaming_main.o $(LDFLAGS) -o $@

clean:
	rm -rf build

build: $(BUILD_DIR)/$(EXECUTABLE)

run: $(BUILD_DIR)/$(EXECUTABLE)
	./$(BUILD_DIR)/$(EXECUTABLE)

test: $(BUILD_DIR)/$(EXECUTABLE)
	@echo "Running basic connectivity test..."
	@timeout 3 ./$(BUILD_DIR)/$(EXECUTABLE) || true
	@echo "Server test complete"

test-unit: $(BUILD_DIR)/blob_storage_tests
	@echo "Running blob storage unit tests..."
	./$(BUILD_DIR)/blob_storage_tests

test-blob: $(BUILD_DIR)/$(EXECUTABLE)
	@echo "Running blob storage integration tests..."
	./test_blob_storage.sh

$(BUILD_DIR)/blob_storage_tests: $(BUILD_DIR)/blob_storage_tests.o $(OBJECTS)
	$(CC) $(CFLAGS) $(BUILD_DIR)/blob_storage_tests.o $(filter-out $(BUILD_DIR)/server_main.o, $(OBJECTS)) $(LDFLAGS) -o $@

help:
	@echo "ATProto PDS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build the executable (default)"
	@echo "  build      - Build the executable"
	@echo "  run        - Build and run the server"
	@echo "  test       - Build and run a quick connectivity test"
	@echo "  test-unit  - Build and run blob storage unit tests"
	@echo "  test-blob  - Build and run blob storage integration tests"
	@echo "  clean      - Remove build artifacts"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Build artifacts are stored in: $(BUILD_DIR)/"
