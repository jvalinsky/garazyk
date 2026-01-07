#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OAuthServerMetadata : NSObject

@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *authorizationEndpoint;
@property (nonatomic, copy) NSString *tokenEndpoint;
@property (nonatomic, copy) NSString *pushedAuthorizationRequestEndpoint;
@property (nonatomic, strong) NSArray<NSString *> *responseTypesSupported;
@property (nonatomic, strong) NSArray<NSString *> *grantTypesSupported;
@property (nonatomic, strong) NSArray<NSString *> *codeChallengeMethodsSupported;
@property (nonatomic, strong) NSArray<NSString *> *tokenEndpointAuthMethodsSupported;
@property (nonatomic, strong) NSArray<NSString *> *tokenEndpointAuthSigningAlgValuesSupported;
@property (nonatomic, strong) NSArray<NSString *> *scopesSupported;
@property (nonatomic, strong) NSArray<NSString *> *dpopSigngingAlgValuesSupported;
@property (nonatomic, assign) BOOL authorizationResponseIssParameterSupported;
@property (nonatomic, assign) BOOL requirePushedAuthorizationRequests;
@property (nonatomic, assign) BOOL clientIdMetadataDocumentSupported;
@property (nonatomic, assign) BOOL requireRequestUriRegistration;

+ (instancetype)defaultMetadata;

- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
