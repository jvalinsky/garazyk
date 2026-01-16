#import "XRPCError.h"

NSString * const XRPCErrorDomain = @"com.atproto.xrpc.error";

@interface XRPCError ()
@property (nonatomic, copy, readwrite) NSString *error;
@property (nonatomic, copy, readwrite) NSString *message;
@property (nonatomic, assign, readwrite) NSInteger statusCode;
@end

@implementation XRPCError

+ (nullable instancetype)errorWithData:(NSData *)data statusCode:(NSInteger)statusCode {
    NSError *parseError = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    return [self errorWithDictionary:dict statusCode:statusCode];
}

+ (nullable instancetype)errorWithDictionary:(NSDictionary *)dict statusCode:(NSInteger)statusCode {
    NSString *error = dict[@"error"];
    NSString *message = dict[@"message"];
    
    if (!error && !message) {
        return nil;
    }
    
    return [[XRPCError alloc] initWithError:error ?: @"UnknownError"
                                     message:message ?: @"An unknown error occurred"
                                  statusCode:statusCode];
}

- (instancetype)initWithError:(NSString *)error
                      message:(NSString *)message
                   statusCode:(NSInteger)statusCode {
    self = [super init];
    if (self) {
        _error = [error copy];
        _message = [message copy];
        _statusCode = statusCode;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"XRPCError %ld: %@ - %@", 
            (long)self.statusCode, self.error, self.message];
}

- (NSError *)toNSError {
    return [NSError errorWithDomain:XRPCErrorDomain
                               code:self.statusCode
                           userInfo:@{NSLocalizedDescriptionKey: self.message,
                                    @"XRPCErrorCode": self.error ?: [NSNull null]}];
}

@end
