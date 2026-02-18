#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <fstream>
#include <iostream>
#include <dirent.h>
#include <sys/stat.h>
#include <string>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

void process_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
        fprintf(stderr, "Error: cannot open %s\n", path.c_str());
        return;
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (file.read((char*)buffer.data(), size)) {
        printf("Running: %s (%ld bytes)\n", path.c_str(), (long)size);
        LLVMFuzzerTestOneInput(buffer.data(), buffer.size());
    }
}

void process_path(const std::string& path) {
    struct stat s;
    if (stat(path.c_str(), &s) == 0) {
        if (s.st_mode & S_IFDIR) {
            // Directory
            DIR *dir;
            struct dirent *ent;
            if ((dir = opendir(path.c_str())) != NULL) {
                while ((ent = readdir(dir)) != NULL) {
                    if (ent->d_name[0] == '.') continue;
                    std::string fullPath = path;
                    if (fullPath.back() != '/') fullPath += "/";
                    fullPath += ent->d_name;
                    
                    struct stat child_s;
                    if (stat(fullPath.c_str(), &child_s) == 0 && (child_s.st_mode & S_IFREG)) {
                        process_file(fullPath);
                    }
                }
                closedir(dir);
            }
        } else if (s.st_mode & S_IFREG) {
            // File
            process_file(path);
        }
    } else {
        fprintf(stderr, "Error: cannot stat %s\n", path.c_str());
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file_or_directory> [file_or_directory...]\n", argv[0]);
        fprintf(stderr, "Running without inputs...\n");
        LLVMFuzzerTestOneInput(NULL, 0);
        return 0;
    }

    for (int i = 1; i < argc; i++) {
        const char *arg_str = argv[i];
        if (!arg_str || arg_str[0] == '\0') continue;
        
        if (arg_str[0] == '-') {
            // Explicitly skip anything starting with -
            continue;
        }
        
        std::string path = arg_str;
        process_path(path);
    }
    return 0;
}
