// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import <Foundation/Foundation.h>
#import "Network/PDSRepoImportValidationResult.h"
#import "Repository/CAR.h"
#import "Repository/RepoCommit.h"
#import "Database/Pool/DatabasePool.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepoImportValidator : NSObject
+ (nullable PDSRepoImportValidationResult *)validateCARData:(NSData *)carData
                                                     reader:(CARReader *)reader
                                                     commit:(RepoCommit *)commit
                                                        did:(NSString *)did
                                              databasePool:(PDSDatabasePool *)databasePool
                                     allowLocalKeyFallback:(BOOL)allowLocalKeyFallback
                                                     error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
