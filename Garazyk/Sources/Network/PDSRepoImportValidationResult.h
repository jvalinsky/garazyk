// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepoImportValidationResult : NSObject
@property (nonatomic, strong) NSArray<PDSDatabaseBlock *> *blocks;
@property (nonatomic, strong) NSArray<PDSDatabaseRecord *> *records;
@end

NS_ASSUME_NONNULL_END
