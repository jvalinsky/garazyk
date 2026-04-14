#import <Foundation/Foundation.h>

@class PDSConfiguration;

NS_ASSUME_NONNULL_BEGIN

NSString *XrpcDidWebIdentifierFromIssuer(NSString *issuer, NSString *fallbackHost);
NSArray<NSString *> *XrpcServiceAuthExpectedAudiences(PDSConfiguration *config);

NS_ASSUME_NONNULL_END
