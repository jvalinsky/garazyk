#import "Network/HttpRetryPolicy.h"
#import <math.h>

@implementation HttpRetryResult

- (instancetype)initWithDecision:(HttpRetryDecision)decision delay:(NSTimeInterval)delay {
    self = [super init];
    if (self) {
        _decision = decision;
        _retryDelay = delay;
    }
    return self;
}

@end

@implementation HttpRetryPolicy

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxRetries = 3;
        _initialDelay = 0.5;
        _backoffMultiplier = 2.0;
    }
    return self;
}

- (HttpRetryResult *)evaluateStatusCode:(NSInteger)statusCode
                           networkError:(nullable NSError *)error
                          attemptNumber:(NSInteger)attempt {
    // Determine if it's a transient failure
    BOOL isTransientFailure = (error != nil) || (statusCode >= 500);

    if (isTransientFailure) {
        if (attempt < self.maxRetries) {
            NSTimeInterval delay = self.initialDelay * pow(self.backoffMultiplier, attempt);
            return [[HttpRetryResult alloc] initWithDecision:HttpRetryDecisionRetryAfter delay:delay];
        } else {
            return [[HttpRetryResult alloc] initWithDecision:HttpRetryDecisionFail delay:0.0];
        }
    }

    if (statusCode >= 200 && statusCode < 300) {
        return [[HttpRetryResult alloc] initWithDecision:HttpRetryDecisionSucceed delay:0.0];
    }

    // Any other status code (like 4xx or 3xx) fails immediately (not retryable)
    return [[HttpRetryResult alloc] initWithDecision:HttpRetryDecisionFail delay:0.0];
}

@end