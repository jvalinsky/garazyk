// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class ATProtoServiceConfiguration;

NS_ASSUME_NONNULL_BEGIN

NSString *XrpcDidWebIdentifierFromIssuer(NSString *issuer, NSString *fallbackHost);
NSArray<NSString *> *XrpcServiceAuthExpectedAudiences(ATProtoServiceConfiguration *config);

NS_ASSUME_NONNULL_END
