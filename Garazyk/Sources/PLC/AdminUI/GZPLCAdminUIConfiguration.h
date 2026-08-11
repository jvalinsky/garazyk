// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Loads a nonempty admin password from a credential file without exposing its contents in errors. */
FOUNDATION_EXPORT NSString * _Nullable GZPLCAdminPasswordFromFile(NSString *path, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
