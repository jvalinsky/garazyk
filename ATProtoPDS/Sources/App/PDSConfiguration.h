#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSConfigErrorDomain;

typedef NS_ENUM(NSInteger, PDSConfigError) {
    PDSConfigErrorFileNotFound = 1,
    PDSConfigErrorInvalidFormat = 2,
    PDSConfigErrorMissingValue = 3
};

@interface PDSConfiguration : NSObject

@property (nonatomic, readonly) NSString *serverHost;
@property (nonatomic, readonly) NSUInteger serverPort;
@property (nonatomic, readonly) NSString *dataDirectory;

@property (nonatomic, readonly) NSString *plcURL;
@property (nonatomic, readonly) NSUInteger plcRetryCount;
@property (nonatomic, readonly) NSUInteger plcRetryDelayMs;

@property (nonatomic, readonly) BOOL debugSkipPlcOperations;
@property (nonatomic, readonly) BOOL debugVerboseLogging;
@property (nonatomic, readonly) BOOL debugInMemoryDatabases;
@property (nonatomic, readonly) BOOL debugResetOnStartup;

@property (nonatomic, readonly) NSUInteger userDatabasePoolMaxSize;
@property (nonatomic, readonly) NSUInteger serviceDatabasePoolMaxSize;
@property (nonatomic, readonly) NSUInteger didCachePoolMaxSize;
@property (nonatomic, readonly) NSUInteger sequencerPoolMaxSize;

@property (nonatomic, readonly) NSUInteger accessTokenTtlSeconds;
@property (nonatomic, readonly) NSUInteger refreshTokenTtlSeconds;
@property (nonatomic, readonly) BOOL inviteCodeRequired;

@property (nonatomic, readonly) BOOL rateLimitEnabled;
@property (nonatomic, readonly) NSUInteger rateLimitRequestsPerMinute;
@property (nonatomic, readonly) NSUInteger rateLimitBurstSize;

+ (nullable instancetype)sharedConfiguration;
+ (nullable instancetype)configurationWithPath:(NSString *)path error:(NSError **)error;

- (BOOL)loadFromPath:(NSString *)path error:(NSError **)error;
- (nullable NSString *)stringForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
