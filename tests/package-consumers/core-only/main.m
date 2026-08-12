// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/CID.h"
#import "Core/TID.h"

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        ATProtoCID *cid = [ATProtoCID cidFromString:@"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"];
        if (!cid) {
            return 1;
        }
        ATProtoTID *tid = [ATProtoTID tid];
        if (!tid) {
            return 2;
        }
    }
    return 0;
}
