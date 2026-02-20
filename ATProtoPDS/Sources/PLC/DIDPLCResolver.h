#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const DIDPLCResolverErrorDomain;

typedef NS_ENUM(NSInteger, DIDPLCResolverErrorCode) {
    DIDPLCResolverErrorInvalidDID = 1,
    DIDPLCResolverErrorNotFound = 2,
    DIDPLCResolverErrorNetworkError = 3,
    DIDPLCResolverErrorInvalidResponse = 4
};

/// A robust DID PLC Resolver with configurable timeouts and caching for the AT Protocol.
@interface DIDPLCResolver : NSObject

/// The base URL of the PLC server (e.g., https://plc.directory).
@property (nonatomic, copy, readonly) NSString *plcUrl;

/// The timeout interval for HTTP requests in seconds. Default is 5.0.
@property (nonatomic, assign) NSTimeInterval timeout;

/// Initializes the resolver with a specific PLC server URL.
/// @param url The base URL string of the PLC server.
- (instancetype)initWithPlcUrl:(NSString *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Resolves a DID synchronously.
/// @param did The DID (e.g. did:plc:...) to resolve.
/// @param error A pointer to an error object that will be populated upon failure.
/// @return The resolved DID document JSON dictionary, or nil if resolution failed or was not found.
- (nullable NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error;

/// Resolves a DID asynchronously with optional backoff retries.
/// @param did The DID to resolve.
/// @param completion A block called when resolution is complete. Error is nil on success.
- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary * _Nullable document, NSError * _Nullable error))completion;

/// Synchronously fetches the audit log for a DID.
/// @param did The DID to fetch the log for.
/// @param error A pointer to an error object.
/// @return An array of operations in the PLCs audit log, or nil on failure.
- (nullable NSArray *)resolveAuditLogForDID:(NSString *)did error:(NSError **)error;

/// Asynchronously fetches the audit log for a DID.
- (void)resolveAuditLogForDID:(NSString *)did completion:(void (^)(NSArray * _Nullable log, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
