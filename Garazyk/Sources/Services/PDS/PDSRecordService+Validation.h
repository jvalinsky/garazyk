// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordService+Validation.h

 @abstract Validation constants, error domain, and helper functions for PDSRecordService.
 */

#import "PDSRecordService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

extern const NSTimeInterval kATProtoCreatedAtMaxSkewSeconds;
extern const NSInteger kPDSRecordServiceMaxJSONNestingDepth;

NSError *PDSRecordServiceShapeError(NSString *message);
BOOL PDSRecordServiceValidateJSONShapeAtDepth(id value, NSInteger depth, NSString *context, NSError **error);
BOOL PDSRecordServiceValidateRecordJSONShape(NSDictionary *record, NSError **error);
NSString *PDSRecordServiceDIDFromATURI(NSString *uri);
NSDictionary *PDSRecordServiceJSONObjectFromRecordValue(id value);
BOOL PDSRecordServiceRecordMentionsDID(NSDictionary *record, NSString *did);
NSError *PDSRecordServiceReplyNotAllowedError(void);
BOOL validateCreatedAtCoherence(NSString *collection, NSString *rkey, NSDictionary *value, PDSValidationMode mode, NSError **error);
BOOL rejectUnknownBuiltInCollection(NSString *collection, PDSValidationMode mode, NSError **error);

NS_ASSUME_NONNULL_END
