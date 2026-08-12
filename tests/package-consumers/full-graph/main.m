// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoRuntime/ATProtoRuntime.h"

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        ATProtoServiceConfiguration *config = [[ATProtoServiceConfiguration alloc] init];
        if (!config) {
            return 1;
        }
    }
    return 0;
}
