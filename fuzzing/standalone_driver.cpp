// Standalone fuzzer driver for macOS (when libFuzzer is not available)
// This provides the entry point that the fuzzer harness code expects
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>

// Forward declaration - implemented in each harness
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

constexpr size_t MAX_FILE_SIZE = 64 * 1024 * 1024; // 64 MiB

static int ProcessFile(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        return 0; // Skip files that can't be opened
    }

    struct stat st;
    if (fstat(fileno(f), &st) != 0) {
        fclose(f);
        return 0;
    }

    size_t size = st.st_size;
    if (size > MAX_FILE_SIZE) {
        size = MAX_FILE_SIZE;
    }

    uint8_t *data = new uint8_t[size];
    if (fread(data, 1, size, f) != size) {
        delete[] data;
        fclose(f);
        return 0;
    }

    LLVMFuzzerTestOneInput(data, size);
    delete[] data;
    fclose(f);
    return 0;
}

static int ProcessPath(const char *path);  // Forward declaration for recursion

static int ProcessPath(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) {
        return 1; // Error: path doesn't exist
    }

    if (S_ISREG(st.st_mode)) {
        return ProcessFile(path);
    }

    if (!S_ISDIR(st.st_mode)) {
        return 0;
    }

    DIR *dir = opendir(path);
    if (!dir) {
        return 1; // Error: can't open directory
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != nullptr) {
        // DT_UNKNOWN can occur on certain filesystems; use stat as fallback
        int isRegularFile = (entry->d_type == DT_REG);
        int isDirectory = (entry->d_type == DT_DIR);

        if (entry->d_type == DT_UNKNOWN) {
            // Fall back to stat to determine type
            size_t pathlen = strlen(path) + strlen(entry->d_name) + 2;
            char *fullpath = new char[pathlen];
            snprintf(fullpath, pathlen, "%s/%s", path, entry->d_name);

            struct stat entryStat;
            if (stat(fullpath, &entryStat) == 0) {
                isRegularFile = S_ISREG(entryStat.st_mode);
                isDirectory = S_ISDIR(entryStat.st_mode);
            }
            delete[] fullpath;
        }

        if (isRegularFile) {
            size_t pathlen = strlen(path) + strlen(entry->d_name) + 2;
            char *fullpath = new char[pathlen];
            snprintf(fullpath, pathlen, "%s/%s", path, entry->d_name);
            ProcessFile(fullpath);
            delete[] fullpath;
        } else if (isDirectory && entry->d_name[0] != '.') {
            // Recursively process subdirectories (skip . and ..)
            size_t pathlen = strlen(path) + strlen(entry->d_name) + 2;
            char *fullpath = new char[pathlen];
            snprintf(fullpath, pathlen, "%s/%s", path, entry->d_name);
            ProcessPath(fullpath);
            delete[] fullpath;
        }
    }

    closedir(dir);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <corpus_dir> [corpus_dir2 ...] [-jobs=N] [-runs=N] [-timeout=N] [-max_len=N]\n", argv[0]);
        return 1;
    }

    int result = 0;
    for (int i = 1; i < argc; i++) {
        // Skip libFuzzer flags
        if (argv[i][0] == '-') {
            continue;
        }

        if (ProcessPath(argv[i]) != 0) {
            fprintf(stderr, "Error: could not open path: %s\n", argv[i]);
            result = 1;
        }
    }

    return result;
}