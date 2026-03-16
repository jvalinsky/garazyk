// standalone_driver.cpp
// Used when the compiler does not support -fsanitize=fuzzer (e.g. GCC, older Clang).
// Reads each file named on the command line and passes its contents to the fuzzer entry point.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size);

// Allow fuzzers to provide custom initialization (weak symbol, optional).
extern "C" __attribute__((weak)) int LLVMFuzzerInitialize(int* argc, char*** argv);

int main(int argc, char** argv) {
    if (LLVMFuzzerInitialize) {
        LLVMFuzzerInitialize(&argc, &argv);
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file> [input_file ...]\n", argv[0]);
        fprintf(stderr, "Runs the fuzzer entry point on each file.\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        FILE* f = fopen(argv[i], "rb");
        if (!f) {
            fprintf(stderr, "Cannot open: %s\n", argv[i]);
            continue;
        }
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size <= 0) {
            fclose(f);
            continue;
        }
        uint8_t* buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(size)));
        if (!buf) {
            fclose(f);
            continue;
        }
        size_t read = fread(buf, 1, static_cast<size_t>(size), f);
        fclose(f);
        LLVMFuzzerTestOneInput(buf, read);
        free(buf);
    }
    return 0;
}
