// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (Helpers)
- (NSDictionary *)parseJSONBody:(NSData *)data;
- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input;
- (NSString *)iso8601StringFromDate:(NSDate *)date;
- (NSDate *)dateFromISO8601String:(NSString *)dateString;
- (void)setCorsHeaders:(HttpResponse *)response
            forRequest:(HttpRequest *)request;
@end

NS_ASSUME_NONNULL_END
