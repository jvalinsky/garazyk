#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSKeyEnvelope : NSObject

/**
 * Seals data into a versioned envelope using AES-256-CBC and HMAC-SHA256 (encrypt-then-MAC).
 */
+ (nullable NSData *)seal:(NSData *)data
                  withKey:(NSData *)key
                    error:(NSError **)error;

/**
 * Opens a versioned envelope, verifying the MAC and decrypting the content.
 */
+ (nullable NSData *)openEnvelope:(NSData *)envelope
                         withKey:(NSData *)key
                           error:(NSError **)error;

/**
 * Returns YES if the data starts with the PDS key envelope magic bytes.
 */
+ (BOOL)isVersionedEnvelope:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
