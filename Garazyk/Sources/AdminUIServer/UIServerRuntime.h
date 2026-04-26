#import <Foundation/Foundation.h>

@class UIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

@interface UIServerRuntime : NSObject

@property(nonatomic, strong, readonly) UIServiceConfig *configuration;
@property(nonatomic, assign, readonly, getter=isRunning) BOOL running;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

