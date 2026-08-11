// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/AdminUI/GZPLCAdminUIConfiguration.h"

NSString *GZPLCAdminPasswordFromFile(NSString *path, NSError **error) {
    NSError *readError = nil;
    NSString *password = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
    if (!password) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZPLCAdminUIConfiguration"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"PLC admin password file could not be read",
                                                NSUnderlyingErrorKey: readError ?: [NSNull null]}];
        }
        return nil;
    }
    password = [password stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (password.length > 0) return password;
    if (error) {
        *error = [NSError errorWithDomain:@"GZPLCAdminUIConfiguration"
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: @"PLC admin password file is empty"}];
    }
    return nil;
}
