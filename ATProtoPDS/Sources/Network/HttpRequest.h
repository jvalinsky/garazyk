#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HttpMethod) {
    HttpMethodGET,
    HttpMethodPOST,
    HttpMethodPUT,
    HttpMethodDELETE,
    HttpMethodPATCH,
    HttpMethodOPTIONS,
    HttpMethodHEAD,
    HttpMethodUnknown
};

@interface HttpRequest : NSObject

@property (nonatomic, readonly) HttpMethod method;
@property (nonatomic, readonly, copy) NSString *methodString;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *queryString;
@property (nonatomic, readonly, nullable, copy) NSDictionary<NSString *, NSString *> *queryParams;
@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, readonly, nullable, copy) NSData *body;
@property (nonatomic, readonly, nullable, copy) NSDictionary *jsonBody;
@property (nonatomic, readonly, nullable, copy) NSDictionary *multipartFormData;
@property (nonatomic, readonly, nullable, copy) NSString *remoteAddress;

+ (instancetype)requestWithData:(NSData *)data;
+ (instancetype)requestWithData:(NSData *)data remoteAddress:(NSString *)remoteAddress;

- (instancetype)initWithMethod:(HttpMethod)method
                     methodString:(NSString *)methodString
                           path:(NSString *)path
                    queryString:(NSString *)queryString
                     queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                         version:(NSString *)version
                         headers:(NSDictionary<NSString *, NSString *> *)headers
                            body:(NSData *)body
                    remoteAddress:(NSString *)remoteAddress;

- (NSString *)headerForKey:(NSString *)key;
- (NSString *)queryParamForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
