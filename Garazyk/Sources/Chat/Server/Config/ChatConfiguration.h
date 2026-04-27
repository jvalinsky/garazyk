/*!
 @file ChatConfiguration.h
 @brief Configuration for the standalone Chat service.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChatConfiguration : NSObject

@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, assign) NSUInteger httpPort;
@property (nonatomic, copy) NSString *adminSecret;
@property (nonatomic, copy) NSString *pdsUrl;

+ (instancetype)defaultConfiguration;
- (BOOL)loadFromFile:(NSString *)path error:(NSError **)error;
- (void)loadFromEnvironment;

@end

NS_ASSUME_NONNULL_END
