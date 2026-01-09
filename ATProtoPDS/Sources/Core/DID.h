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

@property (nonatomic, strong) NSCache *cache;

/// Resolve a DID to its document
/// @param did The DID to resolve
/// @param completion Completion block with document or error
- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion;

/// Batch resolution for multiple DIDs
- (void)resolveMultipleDIDs:(NSArray<NSString *> *)dids completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *results, NSError *error))completion;

/// Synchronous resolution (for testing)
- (nullable DIDDocument *)resolveDIDSync:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END