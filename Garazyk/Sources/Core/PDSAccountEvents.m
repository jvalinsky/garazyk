// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/PDSAccountEvents.h"

NSNotificationName const PDSAccountCreatedNotification =
    @"PDSAccountCreatedNotification";

NSNotificationName const PDSAccountActivatedNotification =
    @"PDSAccountActivatedNotification";

NSNotificationName const PDSAccountDeactivatedNotification =
    @"PDSAccountDeactivatedNotification";

NSString * const PDSAccountEventDidKey = @"did";
NSString * const PDSAccountEventHandleKey = @"handle";
NSString * const PDSAccountEventStatusKey = @"status";
