#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HttpStatusCode) {
    HttpStatusOK = 200,
    HttpStatusCreated = 201,
    HttpStatusAccepted = 202,
    HttpStatusNoContent = 204,
    HttpStatusBadRequest = 400,
    HttpStatusUnauthorized = 401,
    HttpStatusForbidden = 403,
    HttpStatusNotFound = 404,
    HttpStatusMethodNotAllowed = 405,
    HttpStatusConflict = 409,
    HttpStatusInternalServerError = 500,
    HttpStatusNotImplemented = 501,
    HttpStatusServiceUnavailable = 503
};

@interface HttpResponse : NSObject

@property (nonatomic, assign) HttpStatusCode statusCode;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, copy, nullable) NSString *contentType;
@property (nonatomic, copy, nullable) NSData *body;
@property (nonatomic, copy, nullable) NSDictionary *jsonBody;
@property (nonatomic, copy, nullable) NSString *bodyString;
@property (nonatomic, copy) NSMutableDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) BOOL keepAlive;

+ (instancetype)response;
+ (instancetype)responseWithStatusCode:(HttpStatusCode)statusCode;
+ (instancetype)jsonResponse:(NSDictionary *)json statusCode:(HttpStatusCode)statusCode;
+ (instancetype)textResponse:(NSString *)text statusCode:(HttpStatusCode)statusCode;

- (void)setHeader:(NSString *)value forKey:(NSString *)key;
- (void)setJsonBody:(NSDictionary *)json;
- (void)setBodyString:(NSString *)body;
- (void)setBodyData:(NSData *)data;

- (NSData *)serialize;

@end

NS_ASSUME_NONNULL_END
