#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <fstream>
#include <iostream>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file> [file...]\n", argv[0]);
        fprintf(stderr, "Running without inputs...\n");
        // Optional: Run with empty input
        LLVMFuzzerTestOneInput(NULL, 0);
        return 0;
    }

    for (int i = 1; i < argc; i++) {
        std::ifstream file(argv[i], std::ios::binary | std::ios::ate);
        if (!file) {
            fprintf(stderr, "Error: cannot open %s\n", argv[i]);
            continue;
        }
        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);

        std::vector<uint8_t> buffer(size);
        if (file.read((char*)buffer.data(), size)) {
            printf("Running: %s (%ld bytes)\n", argv[i], (long)size);
            LLVMFuzzerTestOneInput(buffer.data(), buffer.size());
        }
    }
    return 0;
}
