#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for DID operations
extern NSErrorDomain const DIDErrorDomain;

/// DID operation error codes
typedef NS_ENUM(NSInteger, DIDErrorCode) {
    DIDErrorInvalidIdentifier = 1,
    DIDErrorResolutionFailed = 2,
    DIDErrorNetworkError = 3,
    DIDErrorInvalidDocument = 4
};

/// Cache status for DID documents
typedef NS_ENUM(NSUInteger, DIDCacheStatus) {
    DIDCacheStatusFresh,
    DIDCacheStatusStale,
    DIDCacheStatusExpired,
};

/// DID Document structure
@interface DIDDocument : NSObject <NSSecureCoding>

@property (readonly, nonatomic, strong) NSDictionary *jsonDictionary;
@property (readonly, nonatomic, strong) NSString *id;
@property (readonly, nonatomic, strong, nullable) NSArray<NSString *> *alsoKnownAs;
@property (readonly, nonatomic, strong, nullable) NSDictionary *service;

+ (nullable instancetype)documentWithJSON:(NSDictionary *)json error:(NSError **)error;

@end

/// DID resolver for different DID methods
@interface DIDResolver : NSObject

/// Resolve a DID to its document
/// @param did The DID to resolve
/// @param forceRefresh If YES, bypass cache and force network resolution
/// @param completion Completion block with document or error
- (void)resolveDID:(NSString *)did
     forceRefresh:(BOOL)forceRefresh
       completion:(void (^)(DIDDocument * _Nullable document, NSError * _Nullable error))completion;

/// Synchronous resolution (for testing)
- (nullable DIDDocument *)resolveDIDSync:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END