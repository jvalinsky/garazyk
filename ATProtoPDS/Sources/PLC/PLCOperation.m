#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const PLCErrorDomain = @"com.atproto.plc";

@implementation PLCOperation

+ (nullable instancetype)operationFromDictionary:(NSDictionary *)dict error:(NSError **)error {
    NSString *did = dict[@"did"];
    NSString *sig = dict[@"sig"];
    NSDictionary *data = dict[@"data"];
    NSString *prev = dict[@"prev"];

    if (![did isKindOfClass:[NSString class]] ||
        ![sig isKindOfClass:[NSString class]] ||
        ![data isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or missing required fields in PLC operation"}];
        }
        return nil;
    }

    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = sig;
    op.data = data;
    op.prev = prev;

    return op;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"did"] = self.did;
    dict[@"sig"] = self.sig;
    dict[@"data"] = self.data;
    if (self.prev) {
        dict[@"prev"] = self.prev;
    }
    return [dict copy];
}

@end

NS_ASSUME_NONNULL_END
