#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class PDSController;

NS_ASSUME_NONNULL_BEGIN

@interface APIParameterDescriptor : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *in;  // query, path, header
@property (nonatomic, copy) NSString *type;  // string, integer, boolean
@property (nonatomic, copy, nullable) NSString *paramDescription;
@property (nonatomic, assign) BOOL required;
@property (nonatomic, assign) BOOL deprecated;

- (NSDictionary *)openAPIDict;
+ (instancetype)initWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required;

@end

@interface APIResponseDescriptor : NSObject

@property (nonatomic, copy) NSString *statusCode;  // "200", "400", "404", etc.
@property (nonatomic, copy) NSString *responseDescription;
@property (nonatomic, copy, nullable) NSString *schemaRef;  // e.g., "#/components/schemas/Account"
@property (nonatomic, copy, nullable) NSString *arrayItemRef;  // e.g., "#/components/schemas/Record" for array responses

- (NSDictionary *)openAPIDict;
+ (instancetype)initWithStatusCode:(NSString *)statusCode description:(NSString *)description;

@end

@interface APIEndpointDescriptor : NSObject

@property (nonatomic, copy) NSString *path;  // e.g., "/accounts"
@property (nonatomic, copy) NSString *method;  // get, post
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy, nullable) NSString *endpointName;  // e.g., "accounts"
@property (nonatomic, copy, nullable) NSString *endpointDescription;
@property (nonatomic, copy, nullable) NSString *operationId;
@property (nonatomic, copy, nullable) NSArray<NSString *> *tags;
@property (nonatomic, strong) NSArray<APIParameterDescriptor *> *parameters;
@property (nonatomic, strong) NSArray<APIResponseDescriptor *> *responses;
@property (nonatomic, assign) BOOL deprecated;

- (NSDictionary *)openAPIDict;

+ (instancetype)descriptorWithPath:(NSString *)path
                            method:(NSString *)method
                           summary:(NSString *)summary
                      endpointName:(nullable NSString *)endpointName
                      operationId:(nullable NSString *)operationId
                             tags:(nullable NSArray<NSString *> *)tags
                        parameters:(NSArray<APIParameterDescriptor *> *)parameters
                        responses:(NSArray<APIResponseDescriptor *> *)responses;

@end

@interface ExploreHandler : NSObject

+ (instancetype)sharedHandler;

- (void)setController:(PDSController *)controller;

- (BOOL)canHandleRequest:(HttpRequest *)request;
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
