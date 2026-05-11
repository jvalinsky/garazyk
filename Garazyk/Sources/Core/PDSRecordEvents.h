// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordEvents.h

 @abstract Shared record event names used across services and sync modules.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Posted when a record is written (put or delete). */
extern NSNotificationName const PDSRecordDidChangeNotification;

NS_ASSUME_NONNULL_END

