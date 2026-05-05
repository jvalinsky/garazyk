//
//  ATURI.h
//  ATProtoPDS
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ATURIErrorDomain;

@interface ATURI : NSObject

@property (nonatomic, copy, readonly) NSString *uriString;
@property (nonatomic, copy, readonly) NSString *did;
@property (nonatomic, copy, readonly) NSString *collection;
@property (nonatomic, copy, readonly) NSString *rkey;

+ (nullable instancetype)uriWithString:(NSString *)string error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface ATDID : NSObject

@property (nonatomic, copy, readonly) NSString *didString;
@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly) NSString *identifier;

+ (nullable instancetype)didWithString:(NSString *)string error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
