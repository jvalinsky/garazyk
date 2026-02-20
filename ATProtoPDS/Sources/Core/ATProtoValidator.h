#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoValidator
 
 @abstract Validates ATProto identifiers and data structures.
 
 @discussion Provides static methods for validating DIDs, handles, CIDs, TIDs,
 and Namespaced Identifiers (NSIDs) according to the AT Protocol specification.
 */
@interface ATProtoValidator : NSObject

/*!
 @method validateDID:error:
 
 @abstract Validates a DID string.
 
 @param did The DID string to validate (e.g., "did:plc:123...").
 @param error On return, contains an error if validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateDID:(NSString *)did error:(NSError **)error;

/*!
 @method validateHandle:error:
 
 @abstract Validates a user handle.
 
 @param handle The handle to validate (e.g., "alice.test").
 @param error On return, contains an error if validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method validateCID:error:
 
 @abstract Validates a CID string.
 
 @param cid The CID string to validate.
 @param error On return, contains an error if validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error;

/*!
 @method validateTID:error:
 
 @abstract Validates a TID string.
 
 @param tid The TID string to validate.
 @param error On return, contains an error if validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateTID:(NSString *)tid error:(NSError **)error;

/*!
 @method validateNSID:error:
 
 @abstract Validates a Namespaced Identifier (NSID).
 
 @param nsid The NSID key to validate (e.g., "app.bsky.feed.post").
 @param error On return, contains an error if validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
