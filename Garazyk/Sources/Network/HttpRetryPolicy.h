/*!
 @file HttpRetryPolicy.h

 @abstract Defines retry-decision policy interfaces for network requests and transient failures.

 @discussion Declares policy inputs and outputs used to evaluate whether an operation should retry, fail, or back off based on status codes and error classes. Separates retry semantics from caller transport code.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HttpRetryDecision) {
    HttpRetryDecisionSucceed,      // request succeeded, use response
    HttpRetryDecisionRetryAfter,   // retry after `retryDelay` seconds
    HttpRetryDecisionFail          // give up, return error
};

@interface HttpRetryResult : NSObject
@property (nonatomic, readonly) HttpRetryDecision decision;
@property (nonatomic, readonly) NSTimeInterval retryDelay;

- (instancetype)initWithDecision:(HttpRetryDecision)decision delay:(NSTimeInterval)delay;
@end

@interface HttpRetryPolicy : NSObject

@property (nonatomic, assign) NSInteger maxRetries;           // default 3
@property (nonatomic, assign) NSTimeInterval initialDelay;    // default 0.5
@property (nonatomic, assign) double backoffMultiplier;       // default 2.0

// Evaluate an HTTP response or error
- (HttpRetryResult *)evaluateStatusCode:(NSInteger)statusCode
                           networkError:(nullable NSError *)error
                          attemptNumber:(NSInteger)attempt;

@end

NS_ASSUME_NONNULL_END