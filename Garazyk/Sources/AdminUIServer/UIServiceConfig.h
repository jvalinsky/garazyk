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
@property(nonatomic, strong) NSURL *videoBaseURL;

@property(nonatomic, copy, nullable) NSString *pdsAdminToken;
@property(nonatomic, copy, nullable) NSString *pdsAdminPassword;
@property(nonatomic, copy, nullable) NSString *plcAdminToken;
@property(nonatomic, copy, nullable) NSString *relayAdminToken;
@property(nonatomic, copy, nullable) NSString *appViewAdminToken;
@property(nonatomic, copy, nullable) NSString *chatAdminToken;
@property(nonatomic, copy, nullable) NSString *videoAdminToken;

/*! Directory containing static assets (CSS, JS, images). Defaults to Assets/ next to the binary. */
@property(nonatomic, copy, nullable) NSString *assetsDirectory;

+ (instancetype)configurationFromEnvironment;

/*! Update service URLs and tokens from the given dictionary. Keys: pdsURL, plcURL, relayURL, appViewURL, chatURL, videoURL, pdsToken, plcToken, relayToken, appViewToken, chatToken, videoToken. Returns YES if all URLs were valid. */
- (BOOL)updateWithDictionary:(NSDictionary<NSString *, NSString *> *)updates;

@end

NS_ASSUME_NONNULL_END

