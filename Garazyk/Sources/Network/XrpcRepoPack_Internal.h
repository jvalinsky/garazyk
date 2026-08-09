// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Service/ServiceDatabases.h"
#import "Admin/PDSAdminController.h"
#import "Services/PDS/PDSRecordService.h"

@protocol XrpcRoutePackServices;

typedef NS_ENUM(NSInteger, PDSRepoPackValidationErrorCode) {
    PDSRepoPackValidationErrorInvalidRequest = 1,
    PDSRepoPackValidationErrorPayloadTooLarge = 2,
};

extern NSString * const _Nonnull PDSRepoPackValidationErrorDomain;

BOOL isReplyNotAllowedError(NSError * _Nonnull error);
BOOL rejectUnavailableRepoDid(NSString * _Nonnull did,
                              id<XrpcRoutePackServices> _Nonnull services,
                              ATProtoHttpResponse * _Nonnull response);
BOOL rejectUnavailableRepoDidIfKnown(NSString * _Nonnull did,
                                     id<XrpcRoutePackServices> _Nonnull services,
                                     ATProtoHttpResponse * _Nonnull response);
BOOL rejectRecordTakedown(NSString * _Nonnull uri,
                          id<XrpcRoutePackServices> _Nonnull services,
                          ATProtoHttpResponse * _Nonnull response);
PDSValidationMode validationModeFromValidateParameter(id _Nullable validateParam);
NSString * _Nonnull normalizedMimeType(NSString * _Nullable contentType);
BOOL isActiveUploadMimeType(NSString * _Nullable contentType);
void applyRepoBlobDownloadHeaders(NSString * _Nonnull mimeType, ATProtoHttpResponse * _Nonnull response);
BOOL validateApplyWritesPayload(id _Nullable writes, NSError * _Nullable * _Nullable error);
NSString * _Nullable normalizedApplyWriteAction(NSDictionary * _Nonnull write);
NSError * _Nonnull repoPackValidationError(PDSRepoPackValidationErrorCode code, NSString * _Nullable message);
NSString * _Nullable normalizedAtHandleFromAlsoKnownAs(NSArray<NSString *> * _Nullable alsoKnownAs);
