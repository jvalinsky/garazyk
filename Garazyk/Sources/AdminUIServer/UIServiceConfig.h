#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIServiceConfig : NSObject

@property(nonatomic, copy) NSString *host;
@property(nonatomic, assign) NSUInteger port;
@property(nonatomic, copy) NSString *adminPassword;

@property(nonatomic, strong) NSURL *pdsBaseURL;
@property(nonatomic, strong) NSURL *plcBaseURL;
@property(nonatomic, strong) NSURL *relayBaseURL;
@property(nonatomic, strong) NSURL *appViewBaseURL;
@property(nonatomic, strong) NSURL *chatBaseURL;

@property(nonatomic, copy, nullable) NSString *pdsAdminToken;
@property(nonatomic, copy, nullable) NSString *plcAdminToken;
@property(nonatomic, copy, nullable) NSString *relayAdminToken;
@property(nonatomic, copy, nullable) NSString *appViewAdminToken;
@property(nonatomic, copy, nullable) NSString *chatAdminToken;

+ (instancetype)configurationFromEnvironment;

@end

NS_ASSUME_NONNULL_END

