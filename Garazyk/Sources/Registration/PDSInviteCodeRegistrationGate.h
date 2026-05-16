// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSInviteCodeRegistrationGate.h

 @abstract Invite code registration gate.

 @discussion
    Validates that a createAccount request includes a valid invite
    code. Extracts the inline invite code logic from XrpcServerPack
    into a reusable gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Registration/PDSRegistrationGate.h"

@class PDSServiceDatabases;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSInviteCodeRegistrationGate

 @abstract Requires a valid invite code for account registration.
 */
@interface PDSInviteCodeRegistrationGate : NSObject <PDSRegistrationGate>

/*! Initialize with the service databases for invite code validation. */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

@end

NS_ASSUME_NONNULL_END
