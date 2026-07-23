// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (PasskeyAuth)
- (void)handlePasskeyChallenge:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handlePasskeySignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)cleanupExpiredPasskeyChallengesLocked;
- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId;
@end

NS_ASSUME_NONNULL_END
