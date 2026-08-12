// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// This file must fail to compile: DatabasePool.h is not part of the public header closure.
#import "Database/Pool/DatabasePool.h"

int main(void) {
    return 0;
}
