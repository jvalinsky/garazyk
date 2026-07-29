// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAuth.m

 @abstract PDS-specific AccountPolicy adapter implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/PDS/PDSAuth.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

NSString * const PDSAuthErrorDomain = @"com.atproto.pds.auth";

#pragma mark - PDSAccountPolicy

@interface PDSAccountPolicy ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) id adminController;
@end

@implementation PDSAccountPolicy

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    return [self initWithDatabase:database adminController:nil];
}

- (instancetype)initWithDatabase:(PDSDatabase *)database
                adminController:(id)adminController {
    self = [super init];
    if (self) {
        _database = database;
        _adminController = adminController;
    }
    return self;
}

- (void)setAdminController:(id)adminController {
    _adminController = adminController;
}

- (BOOL)isAccountAllowed:(NSString *)did
                   error:(NSError **)error {
    if (!self.adminController) {
        // Fail closed: a missing admin controller means we cannot determine
        // takedown status, so deny access rather than silently allowing.
        GZ_LOG_CORE_ERROR(@"PDSAccountPolicy.isAccountAllowed: no adminController configured — denying all");
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account policy not configured: missing admin controller"}];
        }
        return NO;
    }
    if ([self.adminController respondsToSelector:@selector(isAccountTakedownActive:error:)]) {
        NSError *takedownError = nil;
        BOOL isTakedown = [self.adminController isAccountTakedownActive:did error:&takedownError];
        return !isTakedown;
    }
    return YES;
}

- (BOOL)isAdmin:(NSString *)did
           error:(NSError **)error {
    if ([self.adminController respondsToSelector:@selector(isAdmin:error:)]) {
        return [self.adminController isAdmin:did error:error];
    }
    return NO;
}

@end
