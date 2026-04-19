#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdminPartialHandler : NSObject

+ (instancetype)sharedHandler;

- (nullable NSString *)renderPartialWithTemplate:(NSString *)templateName
                                          context:(NSDictionary *)context;

- (nullable NSString *)handlePartialRequestWithPath:(NSString *)path
                                            headers:(NSDictionary<NSString *, NSString *> *)headers
                                               body:(nullable NSData *)body;

#pragma mark - Data Access

/// Get detailed user info for the detail view
- (nullable NSDictionary *)getUserDetailForDid:(NSString *)did;

/// Get list of moderation reports
- (nullable NSArray *)getModerationReports;

@end

NS_ASSUME_NONNULL_END
