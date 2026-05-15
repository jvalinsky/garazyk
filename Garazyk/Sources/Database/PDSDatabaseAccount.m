// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase.h"

@implementation PDSDatabaseAccount

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _did = row[@"did"];
        _handle = row[@"handle"];
        _email = row[@"email"];
        _passwordHash = row[@"password_hash"];
        _passwordSalt = row[@"password_salt"];
        _accessJwt = row[@"access_jwt"];
        _refreshJwt = row[@"refresh_jwt"];
        _status = row[@"status"];
        _deactivatedAt = [row[@"deactivated_at"] doubleValue];
        _createdAt = [row[@"created_at"] doubleValue];
        _updatedAt = [row[@"updated_at"] doubleValue];
        _inviteEnabled = [row[@"invite_enabled"] boolValue];
        _tfaEnabled = [row[@"tfa_enabled"] boolValue];
        _webauthnEnabled = [row[@"webauthn_enabled"] boolValue];
        _tfaSecret = row[@"tfa_secret"];
        _recoveryCodes = row[@"recovery_codes"];
        _ageAssurance = row[@"age_assurance"];
        _ageVerifiedAt = row[@"age_verified_at"];
    }
    return self;
}

@end
